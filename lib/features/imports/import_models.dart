import '../../domain/models/delivery.dart';
import 'excel_cell_parser.dart';

/// A column that can be mapped from a spreadsheet.
enum ImportField {
  date,
  supplierId,
  supplierName,
  supplierType,
  town,
  district,
  region,
  productId,
  productName,
  recordedBy,
  totalWeight,
  bagWeights,

  /// How the delivery was weighed. Optional: a file without this column keeps
  /// the original individual behaviour.
  recordType,

  /// The number of bags on a weighing-bridge record. A count is never read as
  /// a list of bag weights.
  bagCount,
  notes,
}

class ImportWorkbook {
  const ImportWorkbook({required this.filename, required this.sheets});

  final String filename;
  final Map<String, ImportSheet> sheets;
}

class ImportSheet {
  ImportSheet({
    required this.name,
    required this.headers,
    required this.rows,
    this.headerRowIndex = 0,
  });

  final String name;

  /// The column headers, taken from [headerRowIndex].
  final List<String> headers;

  /// Data rows below the header, each as typed cells.
  final List<List<ParsedCell>> rows;

  /// Index of the row the headers were found on, so row numbers reported to the
  /// user match the spreadsheet even when a title row comes first.
  final int headerRowIndex;

  /// Plain-text view of a row, used for the preview table.
  List<String> textRow(int index) =>
      rows[index].map((cell) => cell.text).toList(growable: false);
}

/// An editable, not-yet-committed import row.
///
/// Every value the user can fix in the preview is held here, so validation can
/// be re-run after an edit without re-reading the file.
class ImportDraft {
  ImportDraft({
    required this.rowNumber,
    required this.cells,
    required this.supplierName,
    required this.productName,
    this.productId = '',
    required this.date,
    required this.totalWeight,
    required this.bagWeights,
    this.recordType = DeliveryRecordType.individual,
    this.bagCount = '',
    this.notes = '',
    this.error,
  });

  /// The 1-based spreadsheet row number this draft came from.
  final int rowNumber;

  /// Typed cells as read from the file, retained for the preview.
  final List<ParsedCell> cells;

  String supplierName;
  String productName;
  String productId;
  String date;
  String totalWeight;
  String bagWeights;

  /// Whether this row is an individual weighing or a weighing-bridge bulk
  /// record. A file with no record type column is entirely individual, which is
  /// the original Phase 1 behaviour.
  DeliveryRecordType recordType;

  /// The reported number of bags, used only for a bulk row.
  String bagCount;

  /// Optional remarks, used only for a bulk row.
  String notes;

  /// Set when the row cannot be imported as it stands.
  String? error;

  bool get hasError => error != null;

  ImportDraft copy() => ImportDraft(
    rowNumber: rowNumber,
    cells: cells,
    supplierName: supplierName,
    productName: productName,
    productId: productId,
    date: date,
    totalWeight: totalWeight,
    bagWeights: bagWeights,
    recordType: recordType,
    bagCount: bagCount,
    notes: notes,
    error: error,
  );
}

class ImportMapping {
  const ImportMapping(this.columns);

  final Map<ImportField, String?> columns;

  String? column(ImportField field) => columns[field];
}

class ImportRowResult {
  const ImportRowResult({
    required this.rowNumber,
    this.delivery,
    this.error,
    this.warning,
  });

  final int rowNumber;
  final Delivery? delivery;
  final String? error;
  final String? warning;

  bool get isValid => delivery != null && error == null;
}

class ImportValidation {
  const ImportValidation({required this.rows});

  final List<ImportRowResult> rows;

  int get validCount =>
      rows.where((row) => row.isValid && row.warning == null).length;
  int get warningCount =>
      rows.where((row) => row.isValid && row.warning != null).length;
  int get failedCount => rows.where((row) => !row.isValid).length;
}

class ImportSummary {
  const ImportSummary({
    required this.filename,
    required this.rowsTotal,
    required this.imported,
    required this.skipped,
    required this.failed,
    this.suppliersCreated = 0,
  });

  final String filename;
  final int rowsTotal;
  final int imported;
  final int skipped;
  final int failed;

  /// How many supplier profiles this import had to create, so the user is told
  /// about new suppliers as well as imported records.
  final int suppliersCreated;
}
