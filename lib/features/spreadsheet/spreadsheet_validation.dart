import '../imports/excel_cell_parser.dart';
import 'spreadsheet_row.dart';

/// The result of saving the grid.
class SpreadsheetSaveResult {
  const SpreadsheetSaveResult({
    this.created = 0,
    this.updated = 0,
    this.unchanged = 0,
    this.skippedDuplicates = 0,
    this.failed = 0,
    this.suppliersCreated = 0,
    this.errors = const <String>[],
  });

  final int created;
  final int updated;
  final int unchanged;
  final int skippedDuplicates;
  final int failed;
  final int suppliersCreated;
  final List<String> errors;

  int get totalSaved => created + updated;

  bool get hasChanges => totalSaved > 0;

  /// A short human readable summary, used in the result dialog.
  String get summary {
    final parts = <String>[
      '$created added',
      '$updated updated',
      '$unchanged unchanged',
    ];
    if (skippedDuplicates > 0)
      parts.add('$skippedDuplicates duplicates skipped');
    if (suppliersCreated > 0) parts.add('$suppliersCreated suppliers created');
    if (failed > 0) parts.add('$failed failed');
    return parts.join(', ');
  }
}

/// What a row validation produced.
class SpreadsheetRowCheck {
  const SpreadsheetRowCheck({this.error, this.warning});

  final String? error;
  final String? warning;

  bool get isValid => error == null;
}

/// Validates a single grid row.
///
/// A row must have a readable date, a supplier, a product and at least one
/// positive bag weight, because that is what the existing delivery model
/// requires. The same rules apply to new and existing rows.
SpreadsheetRowCheck validateSpreadsheetRow(SpreadsheetRow row) {
  if (row.isRemoved) {
    return const SpreadsheetRowCheck(warning: 'Removed');
  }
  if (row.recorderName.trim().isEmpty && !row.isNew) {
    return const SpreadsheetRowCheck(
      error: 'The recorder for this row is unknown',
    );
  }
  // The date is checked first. A cell holding something that is not a date at
  // all is a specific, actionable problem, and reporting it hides nothing: an
  // empty date still reports "Date is required", and a valid date falls through
  // to the supplier, product and weight checks below.
  final recordedAt = row.recordedAt;
  if (recordedAt == null) {
    return SpreadsheetRowCheck(
      error: row.date.trim().isEmpty
          ? 'Date is required'
          : 'Invalid date: ${row.date.trim()}',
    );
  }
  if (row.supplierName.trim().isEmpty) {
    return const SpreadsheetRowCheck(error: 'Supplier is required');
  }
  if (row.productName.trim().isEmpty) {
    return const SpreadsheetRowCheck(error: 'Product is required');
  }
  if (row.parsedWeights == null) {
    return const SpreadsheetRowCheck(
      error: 'Enter at least one bag weight greater than zero',
    );
  }
  return const SpreadsheetRowCheck();
}

/// Applies [validateSpreadsheetRow] to a row, storing any message on the row.
SpreadsheetRowCheck applyRowValidation(SpreadsheetRow row) {
  final check = validateSpreadsheetRow(row);
  row.error = check.error;
  return check;
}

/// Counts the rows in each state, used for the save confirmation.
({int created, int edited, int unchanged, int removed}) summariseRows(
  List<SpreadsheetRow> rows,
) => (
  created: rows.where((row) => row.state == SpreadsheetRowState.created).length,
  edited: rows.where((row) => row.state == SpreadsheetRowState.edited).length,
  unchanged: rows
      .where((row) => row.state == SpreadsheetRowState.unchanged)
      .length,
  removed: rows.where((row) => row.state == SpreadsheetRowState.deleted).length,
);

/// Formats a parsed weight list back to the text shown in the grid.
String formatWeights(Iterable<double> weights) =>
    weights.map(formatImportNumber).join(',');
