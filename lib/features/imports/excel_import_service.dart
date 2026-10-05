import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:sqflite/sqflite.dart';

import '../../domain/models/delivery.dart';
import '../../domain/models/product.dart';
import '../../domain/models/supplier.dart';
import '../receiving/bulk_receiving_input.dart';
import '../receiving/delivery_repository.dart';
import '../receiving/receiving_service.dart';
import 'excel_cell_parser.dart';
import 'excel_workbook_repair.dart';
import 'import_header_detector.dart';
import 'import_models.dart';
import 'import_sheet_builder.dart';
import 'workbook_formula_cache.dart';
import 'workbook_grid_model.dart';

export 'import_models.dart';

class ExcelImportService {
  ExcelImportService({
    required this.database,
    required this.deliveryRepository,
    required this.userId,
    this.companyIdProvider,
    this.receivingService,
    this.catalogueProvider,
  });

  final Database database;
  final DeliveryRepository deliveryRepository;
  final String userId;
  final String? Function()? companyIdProvider;
  final ReceivingService? receivingService;

  /// Supplies the company's products so a workbook with no Product ID column
  /// can still resolve a product from its name.
  final Future<List<Product>> Function()? catalogueProvider;

  /// Products used to infer a product ID, defaulting to the seeded catalogue.
  Future<List<Product>> _catalogue() async =>
      await catalogueProvider?.call() ?? Product.initialProducts;

  /// Reads a workbook into typed cells, locating the header row.
  ///
  /// CSV is supported because it needs no extra package: the same header
  /// detection is reused by wrapping each field as a text cell.
  ///
  /// Before decoding, [ExcelWorkbookRepair] normalises a defect that real
  /// Microsoft Excel workbooks - accounting sheets in particular - routinely
  /// contain, and which otherwise makes the package abort the whole read with
  /// "custom numFmtId starts at 164 but found a value of N". The repair only
  /// renumbers style ids; cell values, types, dates and numbers are untouched.
  /// `.xlsm` is accepted here for the same reason: it is the same OOXML
  /// package, and its macro part is simply never read.
  ImportWorkbook readWorkbook(Uint8List bytes, String filename) {
    if (filename.toLowerCase().endsWith('.csv')) {
      return readCsv(bytes, filename);
    }
    final Excel workbook;
    try {
      workbook = Excel.decodeBytes(ExcelWorkbookRepair.repair(bytes));
    } on UnsupportedError {
      throw StateError(
        'Excel workbook could not be read. This workbook uses an Excel '
        'format/style feature that is not supported by the current importer. '
        'Saving it as a plain .xlsx workbook usually resolves this.',
      );
    } catch (error) {
      throw StateError('Excel workbook could not be read: $error');
    }
    final sheets = <String, ImportSheet>{};
    for (final entry in workbook.tables.entries) {
      final sourceRows = entry.value.rows;
      if (sourceRows.isEmpty) continue;

      // Every cell is converted with its type preserved.
      final grid = sourceRows
          .map((row) => row.map((cell) => parseCellValue(cell?.value)).toList())
          .toList();

      final sheet = buildImportSheet(entry.key, grid);
      if (sheet != null) sheets[entry.key] = sheet;
    }
    if (sheets.isEmpty) {
      throw StateError('The workbook contains no readable sheets');
    }
    return ImportWorkbook(filename: filename, sheets: sheets);
  }

  /// Reads every worksheet of a workbook as a spreadsheet, in its original
  /// shape.
  ///
  /// This is the counterpart to [readWorkbook]. That method is built for the
  /// business importer, so it looks for a header row, discards everything above
  /// it, drops blank rows and renames empty columns. All of that is wrong for a
  /// file the user simply wants to *see*, because a real workbook is not a
  /// delivery sheet: its row 1 is not a header, a blank row is a position the
  /// user may rely on, and a column may legitimately hold anything at all.
  ///
  /// So this reads the same repaired bytes through the same [parseCellValue],
  /// but keeps the grid exactly as written:
  ///
  /// * every row is kept, blank rows included, so A1 is really A1;
  /// * the column count is the widest row, not a detected header;
  /// * no mapping, no synonym matching and no per-row validation is applied, so
  ///   a row that is not a delivery never produces "Invalid date: (empty)";
  /// * a formula stays the formula text the decoder reported.
  WorkbookGridBook readWorkbookGrids(Uint8List bytes, String filename) {
    if (filename.toLowerCase().endsWith('.csv')) {
      return WorkbookGridBook(
        filename: filename,
        sheets: [_gridFromCsv(bytes, filename)],
      );
    }

    final Excel workbook;
    try {
      workbook = Excel.decodeBytes(ExcelWorkbookRepair.repair(bytes));
    } on UnsupportedError {
      throw StateError(
        'Excel workbook could not be read. This workbook uses an Excel '
        'format/style feature that is not supported by the current importer. '
        'Saving it as a plain .xlsx workbook usually resolves this.',
      );
    } catch (error) {
      throw StateError('Excel workbook could not be read: $error');
    }

    // The `excel` package can only keep the expression or the cached result of a
    // formula cell, never both, so the worksheet XML is read alongside it to
    // recover whichever part the package dropped.
    final formulas = WorkbookFormulaCache.read(bytes);
    final sheets = <WorkbookGrid>[];
    for (final entry in workbook.tables.entries) {
      final rows = entry.value.rows;
      if (rows.isEmpty) continue;
      // Cell types are preserved exactly as the decoder reported them, and the
      // presentation the workbook gave a cell is read alongside the value.
      final cells = <List<ParsedCell>>[];
      final styles = <String, WorkbookCellStyle>{};
      for (var row = 0; row < rows.length; row++) {
        final line = <ParsedCell>[];
        for (var column = 0; column < rows[row].length; column++) {
          final cell = rows[row][column];
          final parsed = parseCellValue(cell?.value);
          final parts = formulas.partsFor(entry.key, row, column);
          line.add(
            parts == null
                ? parsed
                : ParsedCell(
                    // The expression is the cell's real content; the cached
                    // result is kept beside it rather than replacing it.
                    text: parsed.isFormula ? '=${parts.formula}' : parsed.text,
                    number: parsed.number,
                    date: parsed.date,
                    isFormula: true,
                    formula: parts.formula,
                    cachedText: parts.cachedText,
                  ),
          );
          final style = _styleOf(cell);
          if (style != null && !style.isPlain) styles['$row#$column'] = style;
        }
        cells.add(line);
      }
      sheets.add(
        WorkbookGrid(
          name: entry.key,
          sourceFilename: filename,
          cells: cells,
          merges: _mergesOf(entry.value),
          styles: styles,
        ),
      );
    }
    if (sheets.isEmpty) {
      throw StateError('The workbook contains no readable sheets');
    }
    return WorkbookGridBook(filename: filename, sheets: sheets);
  }

  /// Reads the presentation the workbook gave one cell.
  ///
  /// The cell type is [Data], which is what `Sheet.rows` actually holds; there
  /// is no `Cell` type in the package.
  ///
  /// Only attributes the decoder exposes reliably are carried across, and only
  /// when they differ from the plain default, so an unstyled sheet costs
  /// nothing. Colours are normalised to a plain hex string so the grid can hand
  /// them straight to Flutter.
  static WorkbookCellStyle? _styleOf(Data? cell) {
    final style = cell?.cellStyle;
    if (style == null) return null;
    return WorkbookCellStyle(
      // The package exposes these as isBold / isItalic and as
      // horizontalAlignment / verticalAlignment, not as bare field names.
      bold: style.isBold,
      italic: style.isItalic,
      fontSize: style.fontSize,
      horizontalAlign: _alignName(style.horizontalAlignment.name),
      verticalAlign: _alignName(style.verticalAlignment.name),
      // The colours are ExcelColor values, so the hex is read from each one.
      textColor: _hex(style.fontColor.colorHex),
      backgroundColor: _hex(style.backgroundColor.colorHex),
    );
  }

  /// Normalises the decoder's alignment enum name to a short stable word.
  static String? _alignName(String name) {
    final lower = name.toLowerCase();
    for (final candidate in const [
      'left',
      'center',
      'centre',
      'right',
      'general',
      'top',
      'bottom',
    ]) {
      if (lower.contains(candidate)) {
        return candidate == 'centre' ? 'center' : candidate;
      }
    }
    return null;
  }

  /// A usable colour hex, or null when the cell has no fill or a transparent one.
  static String? _hex(String? value) {
    if (value == null) return null;
    final cleaned = value.replaceAll('#', '').trim();
    if (cleaned.isEmpty) return null;
    // 'None' and a fully transparent 00 alpha mean "no colour to draw".
    if (cleaned.length == 8 && cleaned.substring(0, 2) == '00') return null;
    return cleaned;
  }

  /// Reads merged ranges the decoder exposes, in grid coordinates.
  ///
  /// The decoder reports spans as A1-style text such as `A1:C3`, which is
  /// converted to zero-based row/column pairs. A span the file declares but the
  /// decoder does not report is left out rather than guessed at, so the grid
  /// never invents a merge the workbook does not have.
  static List<WorkbookMerge> _mergesOf(Sheet sheet) {
    final merges = <WorkbookMerge>[];
    for (final span in sheet.spannedItems) {
      final parts = span.split(':');
      if (parts.length != 2) continue;
      final start = _parseAddress(parts[0]);
      final end = _parseAddress(parts[1]);
      if (start == null || end == null) continue;
      final merge = WorkbookMerge(
        startRow: start.$1,
        startColumn: start.$2,
        endRow: end.$1,
        endColumn: end.$2,
      );
      if (merge.isSpanned) merges.add(merge);
    }
    return merges;
  }

  /// Parses an A1-style reference into a zero-based (row, column) pair.
  static (int, int)? _parseAddress(String address) {
    final match = RegExp(r'^([A-Za-z]+)(\d+)$').firstMatch(address.trim());
    if (match == null) return null;
    var column = 0;
    for (final unit in match.group(1)!.toUpperCase().codeUnits) {
      column = column * 26 + (unit - 64);
    }
    final row = int.tryParse(match.group(2)!);
    if (row == null || row < 1) return null;
    return (row - 1, column - 1);
  }

  /// Builds a grid from CSV, using the same splitter the business reader uses.
  ///
  /// CSV has no types and no merges, so every cell is text, but the row and
  /// column positions are preserved in the same way an .xlsx grid is.
  WorkbookGrid _gridFromCsv(Uint8List bytes, String filename) {
    String text;
    try {
      text = utf8.decode(bytes);
    } on FormatException {
      // Fall back to Latin-1, which older desktop exports often use.
      text = String.fromCharCodes(bytes);
    }
    return WorkbookGrid(
      name: 'Sheet1',
      sourceFilename: filename,
      cells: splitCsvLines(text)
          .map((line) => line.map((value) => ParsedCell(text: value)).toList())
          .toList(),
    );
  }

  /// Reads a UTF-8 CSV file using the same header detection as .xlsx.
  ImportWorkbook readCsv(Uint8List bytes, String filename) {
    String text;
    try {
      text = utf8.decode(bytes);
    } on FormatException {
      // Fall back to Latin-1, which older desktop exports often use.
      text = String.fromCharCodes(bytes);
    }
    final sheet = buildImportSheetFromCsv(text);
    if (sheet == null) {
      throw StateError('The file contains no readable data');
    }
    return ImportWorkbook(filename: filename, sheets: {'Sheet1': sheet});
  }

  /// Builds an editable draft for every data row, so the preview can be
  /// reviewed and corrected before anything is written.
  List<ImportDraft> buildDrafts(ImportSheet sheet, ImportMapping mapping) {
    final drafts = <ImportDraft>[];
    for (var index = 0; index < sheet.rows.length; index++) {
      final row = sheet.rows[index];
      // Row numbers are 1-based and include any title rows above the header,
      // so the number shown matches the number in Excel.
      final rowNumber = index + sheet.headerRowIndex + 2;
      drafts.add(
        ImportDraft(
          rowNumber: rowNumber,
          cells: row,
          supplierName: _value(
            sheet,
            row,
            mapping.column(ImportField.supplierName),
          ),
          productName: _value(
            sheet,
            row,
            mapping.column(ImportField.productName),
          ),
          productId: _value(sheet, row, mapping.column(ImportField.productId)),
          date: _value(sheet, row, mapping.column(ImportField.date)),
          totalWeight: _value(
            sheet,
            row,
            mapping.column(ImportField.totalWeight),
          ),
          bagWeights: _value(
            sheet,
            row,
            mapping.column(ImportField.bagWeights),
          ),
          recordType: parseImportRecordType(
            _value(sheet, row, mapping.column(ImportField.recordType)),
          ),
          bagCount: _value(sheet, row, mapping.column(ImportField.bagCount)),
          notes: _value(sheet, row, mapping.column(ImportField.notes)),
        ),
      );
    }
    return drafts;
  }

  /// Validates a single draft row, returning the delivery it will create.
  ///
  /// A draft is re-validated after every edit in the preview, so the row shown
  /// and the row imported can never disagree.
  Future<Delivery> validateDraft(
    ImportDraft draft,
    ImportSheet sheet,
    ImportMapping mapping,
  ) async {
    final date = _parseDraftDate(draft, sheet, mapping);
    final supplierName = _required(draft.supplierName.trim(), 'Supplier name');
    final productName = _required(draft.productName.trim(), 'Product name');

    // The product ID is optional. When the workbook has no product ID column,
    // or leaves it blank, it is inferred from the product name so external
    // files that only carry a product name still import.
    var productId = draft.productId.trim();
    if (productId.isEmpty) {
      productId =
          inferProductId(productName, await _catalogue()) ?? productName;
    }

    // A bulk row is one weighing-bridge transaction: it stores the scale total
    // and the reported bag count and has NO bag weights, so nothing is ever
    // distributed across invented bags. Every other row keeps the original
    // individual behaviour exactly.
    final supplierType =
        _value(
          sheet,
          draft.cells,
          mapping.column(ImportField.supplierType),
        ).toLowerCase().contains('aggreg')
        ? SupplierType.aggregator
        : SupplierType.farmer;
    final isBulk = draft.recordType == DeliveryRecordType.bulk;
    if (isBulk) {
      final bulkInput = parseBulkReceivingInput(
        bags: draft.bagCount,
        totalWeight: draft.totalWeight,
        notes: draft.notes,
      );
      return Delivery(
        id: 'import-${draft.rowNumber}-${DateTime.now().microsecondsSinceEpoch}',
        supplier: Supplier(
          id: _value(
            sheet,
            draft.cells,
            mapping.column(ImportField.supplierId),
          ),
          name: supplierName,
          type: supplierType,
          town: _value(sheet, draft.cells, mapping.column(ImportField.town)),
          district: _value(
            sheet,
            draft.cells,
            mapping.column(ImportField.district),
          ),
          region: _value(
            sheet,
            draft.cells,
            mapping.column(ImportField.region),
          ),
        ),
        product: Product(id: productId, name: productName),
        recordedAt: date,
        bagWeights: const <double>[],
        recordedByUserId: null,
        companyId: companyIdProvider?.call(),
        recordType: DeliveryRecordType.bulk,
        bulkTotalWeight: bulkInput.totalWeight,
        bulkBagCount: bulkInput.bagCount,
        notes: bulkInput.notes,
      );
    }

    final weights = _draftWeights(draft);

    return Delivery(
      id: 'import-${draft.rowNumber}-${DateTime.now().microsecondsSinceEpoch}',
      supplier: Supplier(
        id: _value(sheet, draft.cells, mapping.column(ImportField.supplierId)),
        name: supplierName,
        type: supplierType,
        town: _value(sheet, draft.cells, mapping.column(ImportField.town)),
        district: _value(
          sheet,
          draft.cells,
          mapping.column(ImportField.district),
        ),
        region: _value(sheet, draft.cells, mapping.column(ImportField.region)),
      ),
      product: Product(id: productId, name: productName),
      recordedAt: date,
      bagWeights: weights,
      // A spreadsheet's recorder label is not a Supabase user identity.
      // The authenticated importer is assigned by ReceivingService when
      // it creates the new record; historical rows are never inferred.
      recordedByUserId: null,
      companyId: companyIdProvider?.call(),
    );
  }

  /// Validates every draft, attaching a readable message to any bad row.
  Future<ImportValidation> validateDrafts(
    List<ImportDraft> drafts,
    ImportSheet sheet,
    ImportMapping mapping,
  ) async {
    final results = <ImportRowResult>[];
    for (final draft in drafts) {
      try {
        results.add(
          ImportRowResult(
            rowNumber: draft.rowNumber,
            delivery: await validateDraft(draft, sheet, mapping),
          ),
        );
      } on FormatException catch (error) {
        draft.error = error.message;
        results.add(
          ImportRowResult(rowNumber: draft.rowNumber, error: error.message),
        );
      } on ArgumentError catch (error) {
        draft.error = error.message;
        results.add(
          ImportRowResult(rowNumber: draft.rowNumber, error: error.message),
        );
      }
    }
    return ImportValidation(rows: results);
  }

  Future<ImportValidation> validate(
    ImportSheet sheet,
    ImportMapping mapping,
  ) async => validateDrafts(buildDrafts(sheet, mapping), sheet, mapping);

  Future<ImportValidation> validateAsync(
    ImportSheet sheet,
    ImportMapping mapping,
  ) async {
    final initial = await validate(sheet, mapping);
    final results = <ImportRowResult>[];
    for (final result in initial.rows) {
      if (!result.isValid) {
        results.add(result);
        continue;
      }
      final delivery = result.delivery!;
      final duplicate = await deliveryRepository.hasLikelyDuplicate(
        recordedAt: delivery.recordedAt,
        supplierId: delivery.supplier.id,
        supplierName: delivery.supplier.name,
        productId: delivery.product.id,
        totalWeight: delivery.totalWeight,
      );
      results.add(
        ImportRowResult(
          rowNumber: result.rowNumber,
          delivery: delivery,
          warning: duplicate
              ? 'Likely duplicate of an existing delivery; it will be skipped.'
              : null,
        ),
      );
    }
    return ImportValidation(rows: results);
  }

  Future<ImportSummary> importValid(
    String filename,
    ImportValidation validation,
  ) async {
    if (companyIdProvider != null && companyIdProvider!() == null) {
      throw StateError(
        'Select an active company before importing business data.',
      );
    }
    var imported = 0;
    var skipped = validation.warningCount;
    var failed = validation.failedCount;
    final suppliersBefore = await _supplierCount();
    for (final result in validation.rows.where(
      (row) => row.isValid && row.warning == null,
    )) {
      final delivery = result.delivery!;
      if (await deliveryRepository.hasLikelyDuplicate(
        recordedAt: delivery.recordedAt,
        supplierId: delivery.supplier.id,
        supplierName: delivery.supplier.name,
        productId: delivery.product.id,
        totalWeight: delivery.totalWeight,
      )) {
        skipped++;
        continue;
      }
      try {
        final receiving = receivingService;
        if (receiving == null) {
          await deliveryRepository.save(delivery);
        } else {
          await receiving.saveDelivery(
            supplierId: delivery.supplier.id,
            supplierName: delivery.supplier.name,
            supplierType: delivery.supplier.type,
            town: delivery.supplier.town,
            district: delivery.supplier.district,
            region: delivery.supplier.region,
            selectedSupplier: null,
            delivery: delivery,
          );
        }
        imported++;
      } on Object {
        failed++;
      }
    }
    final suppliersAfter = await _supplierCount();
    final suppliersCreated = suppliersAfter > suppliersBefore
        ? suppliersAfter - suppliersBefore
        : 0;
    await database.insert('import_logs', {
      'id': 'import-log-${DateTime.now().microsecondsSinceEpoch}',
      'filename': filename,
      'imported_at': DateTime.now().toIso8601String(),
      'imported_by_user_id': userId,
      if (companyIdProvider != null) 'company_id': companyIdProvider!(),
      'rows_total': validation.rows.length,
      'rows_imported': imported,
      'rows_skipped': skipped,
      'rows_failed': failed,
    });
    return ImportSummary(
      filename: filename,
      rowsTotal: validation.rows.length,
      imported: imported,
      skipped: skipped,
      failed: failed,
      suppliersCreated: suppliersCreated,
    );
  }

  /// Counts suppliers in the active company, so the import can report how many
  /// supplier profiles it had to create.
  Future<int> _supplierCount() async {
    final activeCompanyId = companyIdProvider?.call();
    if (companyIdProvider != null && activeCompanyId == null) return 0;
    final rows = await database.rawQuery(
      'SELECT COUNT(*) AS count FROM suppliers'
      '${companyIdProvider == null ? '' : ' WHERE company_id IS ?'}',
      companyIdProvider == null ? null : [activeCompanyId],
    );
    return (rows.first['count'] as int?) ?? 0;
  }

  static String _value(
    ImportSheet sheet,
    List<ParsedCell> row,
    String? header,
  ) {
    if (header == null) return '';
    final index = sheet.headers.indexOf(header);
    return index >= 0 && index < row.length ? row[index].text.trim() : '';
  }

  static String _required(String value, String label) =>
      value.isEmpty ? (throw FormatException('$label is required')) : value;

  /// Reads the date from a draft.
  ///
  /// A native Excel date cell is already resolved, so no re-parsing or timezone
  /// conversion happens. An edited value is re-parsed from text, and a bare
  /// number is accepted as an Excel serial only in this date column.
  static DateTime _parseDraftDate(
    ImportDraft draft,
    ImportSheet sheet,
    ImportMapping mapping,
  ) {
    final dateHeader = mapping.column(ImportField.date);
    if (dateHeader != null) {
      final index = sheet.headers.indexOf(dateHeader);
      // Prefer the typed cell, so a native date keeps its exact calendar day.
      if (index >= 0 && index < draft.cells.length) {
        final typed = draft.cells[index].asDate(allowSerial: true);
        if (typed != null) return typed;
      }
    }
    final parsed = parseImportDate(draft.date, allowSerial: true);
    if (parsed != null) return parsed;
    throw FormatException(
      'Invalid date: ${draft.date.trim().isEmpty ? '(empty)' : draft.date.trim()}',
    );
  }

  /// Reads the bag weights from a draft.
  ///
  /// A row may carry a delimited list of individual bag weights, or a single
  /// total weight. Thousands separators are tolerated in both.
  static List<double> _draftWeights(ImportDraft draft) {
    final values = draft.bagWeights
        .split(RegExp(r'[,;|]'))
        .map((value) => parseImportNumber(value))
        .whereType<double>()
        .toList();
    if (values.isNotEmpty &&
        values.every((weight) => weight.isFinite && weight > 0)) {
      return values;
    }
    final total = parseImportNumber(draft.totalWeight);
    if (total != null && total.isFinite && total > 0) return [total];
    throw const FormatException(
      'At least one valid positive bag weight is required',
    );
  }
}
