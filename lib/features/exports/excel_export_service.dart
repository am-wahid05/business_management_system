import 'dart:io';

import 'package:excel/excel.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../../domain/models/delivery.dart';
import '../receiving/delivery_repository.dart';
import '../suppliers/supplier_statement.dart';

/// A row of the built-in spreadsheet, in the shape the export writer needs.
///
/// This keeps the spreadsheet feature from depending on the grid, while the
/// workbook itself is still written by this one export service.
class ExcelExportRow {
  const ExcelExportRow({
    required this.date,
    required this.supplierId,
    required this.supplierName,
    required this.productId,
    required this.productName,
    required this.numberOfBags,
    required this.totalWeight,
    required this.recordedBy,
    required this.status,
    this.recordType = DeliveryRecordType.individual,
    this.notes,
  });

  final DateTime date;
  final String supplierId;
  final String supplierName;
  final String productId;
  final String productName;
  final int? numberOfBags;
  final double? totalWeight;
  final String recordedBy;
  final String status;

  /// Individual or bulk. A bulk row exports its stored total and bag count and
  /// never any per-bag values.
  final DeliveryRecordType recordType;

  /// Optional remarks, used mainly for a weighing-bridge record.
  final String? notes;
}

/// The value written into the Record Type column.
String excelRecordTypeLabel(DeliveryRecordType type) => switch (type) {
  DeliveryRecordType.individual => 'Individual',
  DeliveryRecordType.bulk => 'Bulk',
};

class ExcelExportService implements SupplierStatementExporter {
  ExcelExportService(
    this.deliveryRepository, {
    Future<Directory> Function()? directoryProvider,
    this.companyNameProvider,
    this.recorderNamesProvider,
  }) : _directoryProvider = directoryProvider ?? _defaultDirectory;

  final DeliveryRepository deliveryRepository;
  final String Function()? companyNameProvider;
  final Future<Map<String, String>> Function()? recorderNamesProvider;
  final Future<Directory> Function() _directoryProvider;

  String get _companyPrefix =>
      _safeName(companyNameProvider?.call() ?? 'Company');

  Future<File> exportDaily(DateTime date) async {
    return _write(
      '${_companyPrefix}_Daily_Report_${_datePart(date)}.xlsx',
      await deliveryRepository.forDate(date),
    );
  }

  Future<File> exportMonthly(int year, int month) async {
    final start = DateTime(year, month);
    return _write(
      '${_companyPrefix}_Monthly_Report_${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}.xlsx',
      await deliveryRepository.forRange(start, DateTime(year, month + 1)),
    );
  }

  Future<File> exportYearly(int year) async {
    return _write(
      '${_companyPrefix}_Yearly_Report_$year.xlsx',
      await deliveryRepository.forRange(DateTime(year), DateTime(year + 1)),
    );
  }

  Future<File> exportSupplierHistory(
    String supplierId,
    String supplierName,
  ) async {
    return _write(
      '${_companyPrefix}_Supplier_${_safeName(supplierName)}.xlsx',
      await deliveryRepository.forRange(
        DateTime(2000),
        DateTime(2100),
        supplierId: supplierId,
      ),
    );
  }

  @override
  Future<File> export(SupplierStatement statement) async {
    return _writeStatement(
      '${_companyPrefix}_Statement_${_safeName(statement.supplier.name)}_${_datePart(statement.from)}_${_datePart(statement.to)}.xlsx',
      statement,
    );
  }

  /// Records for one product, or for every product when [productId] is blank.
  ///
  /// A blank filter used to be forwarded as `product_id = ''`, which matched
  /// nothing and produced an empty workbook while looking like a successful
  /// export. Treating a blank id as "no product filter" means the Admin can ask
  /// for all product records without having to know an id first.
  Future<File> exportProductReport(String productId, String productName) async {
    final hasProduct = productId.trim().isNotEmpty;
    return _write(
      hasProduct
          ? '${_companyPrefix}_Product_${_safeName(productName)}.xlsx'
          // No product chosen: name the file for the products as a whole and
          // cover the full history, because there is no single product's dates.
          : '${_companyPrefix}_Products.xlsx',
      await deliveryRepository.forRange(
        DateTime(2000),
        DateTime(2100),
        productId: hasProduct ? productId.trim() : null,
      ),
    );
  }

  /// Records for several products at once, within a date range.
  ///
  /// As with [exportSuppliersRange], the products are merged into one workbook
  /// and de-duplicated by delivery id, so an export of several products stays a
  /// single filterable document instead of one file per product.
  Future<File> exportProductsRange(
    List<String> productIds,
    DateTime from,
    DateTime to,
  ) async {
    final start = DateTime(from.year, from.month, from.day);
    final end = DateTime(
      to.year,
      to.month,
      to.day,
    ).add(const Duration(days: 1));
    final seen = <String>{};
    final deliveries = <Delivery>[];
    for (final productId in productIds) {
      final rows = await deliveryRepository.forRange(
        start,
        end,
        productId: productId,
      );
      for (final delivery in rows) {
        if (seen.add(delivery.id)) deliveries.add(delivery);
      }
    }
    deliveries.sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
    return _write(
      '${_companyPrefix}_Products_${_datePart(start)}_to_${_datePart(to)}.xlsx',
      deliveries,
    );
  }

  Future<File> exportSelected(List<String> deliveryIds) async {
    final deliveries = <Delivery>[];
    for (final id in deliveryIds) {
      final delivery = await deliveryRepository.findById(id);
      if (delivery != null) deliveries.add(delivery);
    }
    return _write(
      '${_companyPrefix}_Selected_Deliveries_${_datePart(DateTime.now())}.xlsx',
      deliveries,
    );
  }

  /// Writes the built-in spreadsheet grid to an .xlsx file.
  ///
  /// The columns are the ones the importer reads, so a spreadsheet export can
  /// be imported straight back into the grid or the Excel import screen.
  Future<File> exportGrid(List<ExcelExportRow> rows) {
    final workbook = Excel.createExcel();
    final sheet = workbook['Spreadsheet'];
    sheet.appendRow(
      [
        'Record Type',
        'Date',
        'Supplier ID',
        'Supplier Name',
        'Product ID',
        'Product',
        'Number of Bags',
        'Total Weight',
        'Recorded By',
        'Status',
        'Notes',
      ].map(TextCellValue.new).toList(),
    );
    for (final row in rows) {
      sheet.appendRow([
        TextCellValue(excelRecordTypeLabel(row.recordType)),
        DateCellValue.fromDateTime(row.date),
        TextCellValue(row.supplierId),
        TextCellValue(row.supplierName),
        TextCellValue(row.productId),
        TextCellValue(row.productName),
        if (row.numberOfBags == null)
          TextCellValue('')
        else
          IntCellValue(row.numberOfBags!),
        if (row.totalWeight == null)
          TextCellValue('')
        else
          DoubleCellValue(row.totalWeight!),
        TextCellValue(row.recordedBy),
        TextCellValue(row.status),
        TextCellValue(row.notes ?? ''),
      ]);
    }
    return _saveWorkbook(
      '${_companyPrefix}_Spreadsheet_${_datePart(DateTime.now())}.xlsx',
      workbook,
    );
  }

  /// Every receiving record in an arbitrary date range, for the active company.
  ///
  /// [to] is inclusive by date: a range ending 30/09/2026 includes everything
  /// recorded on that day. The underlying repository takes an exclusive end, so
  /// the extra day is added here rather than being left to the caller, which is
  /// what stops the last day of a range being silently dropped.
  ///
  /// The data still comes from [deliveryRepository], which is already scoped to
  /// the active company, so there is no path by which another company's records
  /// can reach this workbook.
  Future<File> exportRange(DateTime from, DateTime to) async {
    final start = DateTime(from.year, from.month, from.day);
    final end = DateTime(
      to.year,
      to.month,
      to.day,
    ).add(const Duration(days: 1));
    return _write(
      '${_companyPrefix}_Records_${_datePart(start)}_to_${_datePart(to)}.xlsx',
      await deliveryRepository.forRange(start, end),
    );
  }

  /// Records for one supplier within a date range.
  Future<File> exportSupplierRange(
    String supplierId,
    String supplierName,
    DateTime from,
    DateTime to,
  ) async {
    final start = DateTime(from.year, from.month, from.day);
    final end = DateTime(
      to.year,
      to.month,
      to.day,
    ).add(const Duration(days: 1));
    return _write(
      '${_companyPrefix}_Supplier_${_safeName(supplierName)}_${_datePart(start)}_to_${_datePart(to)}.xlsx',
      await deliveryRepository.forRange(start, end, supplierId: supplierId),
    );
  }

  /// Records for several suppliers at once, within a date range.
  ///
  /// The suppliers are merged into one workbook rather than producing a file per
  /// supplier, so an Admin exporting a set gets a single document that can still
  /// be filtered by the Supplier ID column. Duplicates are possible if one
  /// delivery matches more than one selected supplier, so the combined rows are
  /// de-duplicated by delivery id.
  Future<File> exportSuppliersRange(
    Map<String, String> suppliersById,
    DateTime from,
    DateTime to,
  ) async {
    final start = DateTime(from.year, from.month, from.day);
    final end = DateTime(
      to.year,
      to.month,
      to.day,
    ).add(const Duration(days: 1));
    final seen = <String>{};
    final deliveries = <Delivery>[];
    for (final entry in suppliersById.entries) {
      final rows = await deliveryRepository.forRange(
        start,
        end,
        supplierId: entry.key,
      );
      for (final delivery in rows) {
        if (seen.add(delivery.id)) deliveries.add(delivery);
      }
    }
    // Newest first, matching the order every other export uses.
    deliveries.sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
    return _write(
      '${_companyPrefix}_Suppliers_${_datePart(start)}_to_${_datePart(to)}.xlsx',
      deliveries,
    );
  }

  /// The file name an export would use, so the save dialog can offer it as the
  /// default while still letting the Admin change it.
  String suggestFileName(String label, DateTime from, DateTime to) =>
      '${_companyPrefix}_${_safeName(label)}_${_datePart(from)}_to_${_datePart(to)}.xlsx';

  /// The file name for a single-day export.
  ///
  /// A one-day export should not read `2026-01-01_to_2026-01-01`, so the
  /// range form is used only when the two dates differ.
  String suggestDailyFileName(DateTime date) =>
      '${_companyPrefix}_Daily_Report_${_datePart(date)}.xlsx';

  Future<File> _write(String filename, List<Delivery> deliveries) async {
    final workbook = await _buildReceivingWorkbook(deliveries);
    return _saveWorkbook(filename, workbook);
  }

  /// Builds the receiving workbook.
  ///
  /// Shared by every export that writes receiving records, so the default-folder
  /// export and the user-chosen-location export cannot drift into two different
  /// column layouts.
  Future<Excel> _buildReceivingWorkbook(List<Delivery> deliveries) async {
    final recorderNames = await recorderNamesProvider?.call() ?? const {};
    final workbook = Excel.createExcel();
    final sheet = workbook['Receiving'];
    // Only individual deliveries have per-bag columns. A weighing-bridge
    // record can carry thousands of bags, so counting it here would generate
    // thousands of empty columns.
    final maxBags = deliveries
        .where((delivery) => !delivery.isBulk)
        .fold<int>(
          0,
          (maximum, delivery) => delivery.bagWeights.length > maximum
              ? delivery.bagWeights.length
              : maximum,
        );
    final headers = <String>[
      'Record Type',
      'Date',
      'Supplier ID',
      'Supplier Name',
      'Supplier Type',
      'Town',
      'District',
      'Region',
      'Product ID',
      'Product',
      'Number of Bags',
      'Total Weight',
      'Recorded By',
      'Notes',
      ...List.generate(
        maxBags,
        (index) => ['Bag ${index + 1} Weight', 'Bag ${index + 1} Recorded By'],
      ).expand((values) => values),
    ];
    sheet.appendRow(headers.map(TextCellValue.new).toList());
    for (final delivery in deliveries) {
      sheet.appendRow([
        TextCellValue(excelRecordTypeLabel(delivery.recordType)),
        // A native date cell is written rather than text, so the exported file
        // is a normal Excel date and re-imports as the same calendar day.
        DateCellValue.fromDateTime(delivery.recordedAt),
        TextCellValue(delivery.supplier.id),
        TextCellValue(delivery.supplier.name),
        TextCellValue(delivery.supplier.type.name),
        TextCellValue(delivery.supplier.town),
        TextCellValue(delivery.supplier.district),
        TextCellValue(delivery.supplier.region),
        TextCellValue(delivery.product.id),
        TextCellValue(delivery.product.name),
        IntCellValue(delivery.numberOfBags),
        DoubleCellValue(delivery.totalWeight),
        TextCellValue(
          recorderDisplayName(delivery.recordedByUserId, recorderNames),
        ),
        TextCellValue(delivery.notes ?? ''),
        for (var index = 0; index < maxBags; index++) ...[
          if (index < delivery.bagWeights.length)
            DoubleCellValue(delivery.bagWeights[index])
          else
            TextCellValue(''),
          if (index < delivery.bagWeights.length)
            TextCellValue(
              recorderDisplayName(
                delivery.recorderForBag(index),
                recorderNames,
              ),
            )
          else
            TextCellValue(''),
        ],
      ]);
    }
    return workbook;
  }

  Future<File> _writeStatement(
    String filename,
    SupplierStatement statement,
  ) async {
    final recorderNames = await recorderNamesProvider?.call() ?? const {};
    final workbook = Excel.createExcel();
    final sheet = workbook['Statement'];
    sheet.appendRow([
      TextCellValue('Supplier'),
      TextCellValue(statement.supplier.name),
    ]);
    sheet.appendRow([
      TextCellValue('From'),
      TextCellValue(_datePart(statement.from)),
    ]);
    sheet.appendRow([
      TextCellValue('To'),
      TextCellValue(_datePart(statement.to)),
    ]);
    sheet.appendRow(const []);
    sheet.appendRow([
      TextCellValue('Date'),
      TextCellValue('Product'),
      TextCellValue('Number of Bags'),
      TextCellValue('Total Weight'),
      TextCellValue('Recorded By'),
    ]);
    for (final delivery in statement.deliveries) {
      sheet.appendRow([
        TextCellValue(_datePart(delivery.recordedAt)),
        TextCellValue(delivery.product.name),
        IntCellValue(delivery.numberOfBags),
        DoubleCellValue(delivery.totalWeight),
        TextCellValue(
          recorderDisplayName(delivery.recordedByUserId, recorderNames),
        ),
      ]);
    }
    sheet.appendRow(const []);
    sheet.appendRow([
      TextCellValue('TOTAL BAGS'),
      IntCellValue(statement.totalBags),
    ]);
    sheet.appendRow([
      TextCellValue('TOTAL WEIGHT'),
      DoubleCellValue(statement.totalWeight),
    ]);
    return _saveWorkbook(filename, workbook);
  }

  /// Where the user asked for exports to be written, via the platform save
  /// dialog.
  ///
  /// When null, exports keep their previous behaviour and land in the default
  /// folder. Setting this is how "choose where to save" reaches every export
  /// method at once, so the user-chosen location applies to the daily, monthly,
  /// yearly, supplier, product and range exports alike instead of only to some
  /// of them.
  String? destinationPath;

  /// Set once the save dialog has been used, so the UI can say where files are
  /// going and offer to change it.
  String get effectiveDestinationPath =>
      destinationPath ?? 'the default folder';

  Future<File> _saveWorkbook(String filename, Excel workbook) async {
    final bytes = workbook.encode();
    if (bytes == null || bytes.isEmpty) {
      throw StateError('Excel workbook could not be encoded');
    }
    // A location the user picked in the save dialog wins over the default
    // folder, so nothing is ever written somewhere they did not ask for.
    final directory = destinationPath != null
        ? Directory(destinationPath!)
        : await _directoryProvider();
    if (!await directory.exists()) {
      throw StateError(
        'The chosen folder is no longer available: ${directory.path}',
      );
    }
    try {
      final file = File(path.join(directory.path, filename));
      return await file.writeAsBytes(bytes, flush: true);
    } on FileSystemException catch (error) {
      throw StateError('Excel file could not be written: ${error.message}');
    }
  }

  static String _datePart(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  static String _safeName(String value) =>
      value.trim().replaceAll(RegExp(r'[^a-zA-Z0-9_-]+'), '_');

  static Future<Directory> _defaultDirectory() async =>
      await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
}
