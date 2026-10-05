import '../../domain/models/product.dart';
import '../imports/excel_cell_parser.dart';
import '../imports/import_header_detector.dart';
import '../imports/import_models.dart';
import '../imports/import_sheet_builder.dart';
import 'spreadsheet_row.dart';

/// Builds grid rows from a spreadsheet using the Phase 1 reader.
///
/// The grid deliberately reuses the same reader the Excel import uses, so a file
/// that imports correctly also previews correctly, and no second parser exists.
List<SpreadsheetRow> spreadsheetRowsFromSheet(ImportSheet sheet) {
  final mapping = guessMapping(sheet.headers);
  final rows = <SpreadsheetRow>[];
  for (var index = 0; index < sheet.rows.length; index++) {
    final cells = sheet.rows[index];
    String text(String? header) {
      if (header == null) return '';
      final position = sheet.headers.indexOf(header);
      return position >= 0 && position < cells.length
          ? cells[position].text.trim()
          : '';
    }

    // A total weight column is used when a row has no individual bag weights.
    final totalWeight = text(mapping.column(ImportField.totalWeight));
    final bagWeights = text(mapping.column(ImportField.bagWeights));
    final weights = bagWeights.isNotEmpty ? bagWeights : totalWeight;
    if (weights.isEmpty &&
        text(mapping.column(ImportField.supplierName)).isEmpty) {
      // A completely empty row carries no information.
      continue;
    }

    rows.add(
      SpreadsheetRow(
        supplierId: text(mapping.column(ImportField.supplierId)),
        supplierName: text(mapping.column(ImportField.supplierName)),
        productName: text(mapping.column(ImportField.productName)),
        date: text(mapping.column(ImportField.date)),
        weights: weights,
        recorderName: text(mapping.column(ImportField.recordedBy)),
        status: 'received',
        state: SpreadsheetRowState.created,
      ),
    );
  }
  return rows;
}

/// Converts grid rows into a sheet the Phase 1 export writer understands.
///
/// The exported columns match the columns the importer reads, so a spreadsheet
/// export can be imported straight back.
ImportSheet? spreadsheetSheetFromRows(List<SpreadsheetRow> rows) {
  final live = rows.where((row) => !row.isRemoved).toList(growable: false);
  if (live.isEmpty) return null;
  final grid = <List<String>>[
    const [
      'Record Type',
      'Date',
      'Supplier ID',
      'Supplier Name',
      'Product',
      'Number of Bags',
      'Total Weight',
      'Bag Weights',
      'Notes',
      'Recorded By',
      'Status',
    ],
  ];
  for (final row in live) {
    final weights = row.isBulk ? null : row.parsedWeights;
    grid.add([
      row.isBulk ? 'Bulk' : 'Individual',
      row.date,
      row.supplierId,
      row.supplierName,
      row.productName,
      '${row.numberOfBags ?? ''}',
      row.totalWeight == null
          ? row.weights
          : formatImportNumber(row.totalWeight!),
      // The individual bag weights are written, so re-importing the file
      // rebuilds the same bags rather than one combined weight. A bulk row
      // writes nothing here, because it has no bag weights.
      weights == null ? '' : weights.map(formatImportNumber).join(','),
      row.notes ?? '',
      row.recorderName,
      row.status,
    ]);
  }
  return buildImportSheetFromCsv(
    grid.map((row) => row.map(_escape).join(',')).join('\n'),
  );
}

String _escape(String value) {
  if (!value.contains(',') && !value.contains('"') && !value.contains('\n')) {
    return value;
  }
  return '"${value.replaceAll('"', '""')}"';
}

/// Resolves a product id for a row, using the company's catalogue.
Future<String?> productIdFor(
  SpreadsheetRow row,
  List<Product> catalogue,
) async {
  if (row.productId != null && row.productId!.isNotEmpty) return row.productId;
  return inferProductId(row.productName, catalogue);
}
