import '../../domain/models/delivery.dart';
import '../imports/excel_cell_parser.dart';

/// What has happened to a row in the grid.
enum SpreadsheetRowState {
  /// Loaded from the database and not touched.
  unchanged,

  /// Loaded from the database and edited in the grid.
  edited,

  /// Added in the grid and not yet saved.
  created,

  /// A draft row the user removed before saving.
  deleted,
}

/// One row of the spreadsheet, backed by the existing individual delivery model.
///
/// The grid deliberately exposes only fields that already exist: the recorded
/// date, the supplier, the product, the bag weights (whose sum is the total
/// weight and whose count is the number of bags), the recorder and the status.
/// Nothing here adds a database field.
class SpreadsheetRow {
  SpreadsheetRow({
    required this.date,
    required this.supplierName,
    required this.productName,
    required this.weights,
    required this.recorderName,
    required this.status,
    this.deliveryId,
    this.productId,
    this.supplierId = '',
    this.recordedByUserId,
    this.bagRecordedByUserIds = const <String?>[],
    this.state = SpreadsheetRowState.unchanged,
    this.error,
    this.isFormula = false,
    this.recordType = DeliveryRecordType.individual,
    this.bagCount,
    this.bulkTotalWeight,
    this.notes,
  });

  /// Builds a grid row from a saved delivery.
  ///
  /// A bulk weighing-bridge delivery has no bag weights, so its weights column
  /// shows a clear marker rather than any invented per-bag values.
  factory SpreadsheetRow.fromDelivery(
    Delivery delivery, {
    required String recorderName,
  }) => SpreadsheetRow(
    deliveryId: delivery.id,
    supplierId: delivery.supplier.id,
    supplierName: delivery.supplier.name,
    productId: delivery.product.id,
    productName: delivery.product.name,
    date: formatImportDate(delivery.recordedAt),
    weights: delivery.isBulk
        ? bulkWeightsMarker
        : delivery.bagWeights
              .map((weight) => formatImportNumber(weight))
              .join(','),
    recorderName: recorderName,
    status: delivery.status.name,
    recordedByUserId: delivery.recordedByUserId,
    bagRecordedByUserIds: delivery.bagRecordedByUserIds,
    recordType: delivery.recordType,
    bagCount: delivery.numberOfBags,
    bulkTotalWeight: delivery.isBulk ? delivery.totalWeight : null,
    notes: delivery.notes,
  );

  /// Shown in the bag weights column for a bulk row, so a weighing-bridge
  /// record is never mistaken for an individually weighed one.
  static const bulkWeightsMarker = 'Bulk / bridge weight';

  /// A blank row for the "Add row" action.
  factory SpreadsheetRow.draft({DateTime? date}) => SpreadsheetRow(
    date: formatImportDate(date ?? DateTime.now()),
    supplierName: '',
    productName: '',
    weights: '',
    recorderName: '',
    status: DeliveryStatus.received.name,
    state: SpreadsheetRowState.created,
  );

  /// The delivery id, or null for a row that has not been saved yet.
  ///
  /// This is assigned once a new row is saved, so the grid stops treating that
  /// row as new and a later save updates it instead of creating a duplicate.
  String? deliveryId;

  final String? recordedByUserId;
  final List<String?> bagRecordedByUserIds;

  /// The supplier and product the database holds for this row. These are
  /// refreshed when a row is saved so the grid shows what was actually matched.
  String supplierId;
  String? productId;

  /// Editable values. Dates and weights are held as text so the grid can show
  /// exactly what will be stored and let the user fix it.
  String date;
  String supplierName;
  String productName;
  String weights;

  /// Read-only display values.
  final String recorderName;
  String status;

  SpreadsheetRowState state;
  String? error;

  /// True when the source cell was a formula, shown so the user knows the value
  /// may be recalculated by the spreadsheet.
  bool isFormula;

  bool get isNew => deliveryId == null;

  /// Whether this row is a weighing-bridge (bulk) record.
  bool get isBulk => recordType == DeliveryRecordType.bulk;

  /// Individual or bulk. A bulk row never carries bag weights.
  DeliveryRecordType recordType;

  /// The number of bags. For a bulk row this is the authoritative count the
  /// secretary reported; otherwise it is the number of individually weighed bags.
  int? bagCount;

  /// Optional free text, used mainly for weighing-bridge remarks.
  String? notes;

  /// A draft row that the user removed.
  bool get isRemoved => state == SpreadsheetRowState.deleted;

  bool get hasError => error != null;

  /// The parsed weights for this row, or null when the text is not valid.
  ///
  /// A cell may hold either a single weight or several bag weights separated by
  /// a comma, semicolon or pipe. A value written with thousands separators
  /// (`1,200.5` or `50,240`) is a single weight, so it is read whole rather
  /// than being split into separate bags.
  List<double>? get parsedWeights {
    final text = weights.trim();
    if (text.isEmpty) return null;

    // A formula is never a stored weight. Rejecting it here is what stops a
    // spreadsheet formula from ever becoming an official business value.
    if (text.startsWith('=')) return null;

    if (_looksLikeThousands(text)) {
      final single = parseImportNumber(text);
      if (single == null || !single.isFinite || single <= 0) return null;
      return [single];
    }

    // Every part of a bag weight list must be a plain number. Anything else,
    // such as a stray unit or letter, rejects the whole cell rather than being
    // silently stripped into a different number.
    final parts = text.split(RegExp(r'[,;|]'));
    final values = <double>[];
    for (final part in parts) {
      final value = parseImportNumber(part);
      if (value == null || !value.isFinite || value <= 0) return null;
      values.add(value);
    }
    if (values.isEmpty) return null;
    return values;
  }

  /// The total weight in kilograms.
  ///
  /// For an individual row this is still the sum of the bag weights, so nothing
  /// about the existing behaviour changes. For a bulk row it is the stored
  /// weighing-bridge total, which is held separately because the weights cell
  /// only carries a display marker for a weighing-bridge record.
  double? get totalWeight {
    if (isBulk) return bulkTotalWeight;
    final values = parsedWeights;
    if (values == null) return null;
    return values.fold<double>(0, (total, weight) => total + weight);
  }

  /// The number of bags: the stored count for a bulk row, otherwise the count of
  /// the stored bag weights.
  int? get numberOfBags => isBulk ? bagCount : parsedWeights?.length;

  /// The weighing-bridge total, when this row is a bulk record.
  double? bulkTotalWeight;

  /// The recorded date, or null when the text is not a date we understand.
  ///
  /// Reuses the Phase 1 parser so the grid and the Excel importer accept
  /// exactly the same date formats.
  DateTime? get recordedAt => parseImportDate(date, allowSerial: true);

  /// A short label for the row state, shown in the grid.
  String get stateLabel => switch (state) {
    SpreadsheetRowState.unchanged => 'Unchanged',
    SpreadsheetRowState.edited => 'Edited',
    SpreadsheetRowState.created => 'New',
    SpreadsheetRowState.deleted => 'Removed',
  };

  SpreadsheetRow copy() => SpreadsheetRow(
    deliveryId: deliveryId,
    supplierId: supplierId,
    supplierName: supplierName,
    productId: productId,
    productName: productName,
    date: date,
    weights: weights,
    recorderName: recorderName,
    status: status,
    recordedByUserId: recordedByUserId,
    bagRecordedByUserIds: bagRecordedByUserIds,
    state: state,
    error: error,
    isFormula: isFormula,
  );

  /// Records that an editable field changed, moving an unchanged row to
  /// [SpreadsheetRowState.edited]. A brand new row stays new.
  void markEdited() {
    if (state == SpreadsheetRowState.created) return;
    if (state == SpreadsheetRowState.deleted) return;
    state = SpreadsheetRowState.edited;
    error = null;
  }
}

/// True when a cell is a single number written with thousands separators, such
/// as `1,200.5` or `50,240`, rather than a list of bag weights.
///
/// The pattern requires every group after the comma to be exactly three digits,
/// so a real list such as `50,60` or `80,70` is still read as several bags.
bool _looksLikeThousands(String text) =>
    RegExp(r'^\d{1,3}(,\d{3})+(\.\d+)?$').hasMatch(text);
