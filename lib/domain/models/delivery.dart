import 'product.dart';
import 'supplier.dart';

enum DeliveryStatus { draft, received, corrected, cancelled }

/// How a delivery was weighed.
///
/// [individual] is the original bag-by-bag workflow and is unchanged.
/// [bulk] is a weighing-bridge transaction where the scale produced one total
/// and the bags were never individually weighed inside this application, so
/// there are no bag weight rows at all.
enum DeliveryRecordType {
  individual,
  bulk;

  static DeliveryRecordType parse(Object? value) => values.firstWhere(
    (type) => type.name == value,
    orElse: () => DeliveryRecordType.individual,
  );
}

enum SynchronizationStatus {
  localOnly,
  pendingSync,
  synced,
  syncFailed,
  // Legacy values are retained so existing local records can be upgraded safely.
  pending,
  synchronized,
  failed,
}

class Delivery {
  Delivery({
    required this.id,
    required this.supplier,
    required this.product,
    required this.recordedAt,
    required List<double> bagWeights,
    required this.recordedByUserId,
    List<String?>? bagRecordedByUserIds,
    this.companyId,
    this.status = DeliveryStatus.received,
    this.synchronizationStatus = SynchronizationStatus.pending,
    this.recordType = DeliveryRecordType.individual,
    this.bulkTotalWeight,
    this.bulkBagCount,
    this.notes,
    DateTime? updatedAt,
  }) : bagWeights = List.unmodifiable(bagWeights),
       bagRecordedByUserIds = List.unmodifiable(
         bagRecordedByUserIds ?? const <String?>[],
       ),
       updatedAt = updatedAt ?? recordedAt {
    if (recordType == DeliveryRecordType.bulk) {
      // A bulk record keeps its weight and bag count in dedicated fields and
      // MUST NOT carry invented bag weight rows.
      if (bagWeights.isNotEmpty) {
        throw ArgumentError.value(
          bagWeights,
          'bagWeights',
          'a bulk weighing-bridge record must not have bag weights',
        );
      }
      if (bulkTotalWeight == null ||
          !bulkTotalWeight!.isFinite ||
          bulkTotalWeight! <= 0) {
        throw ArgumentError.value(
          bulkTotalWeight,
          'bulkTotalWeight',
          'a bulk record requires a total weight greater than zero',
        );
      }
      if (bulkBagCount == null || bulkBagCount! <= 0) {
        throw ArgumentError.value(
          bulkBagCount,
          'bulkBagCount',
          'a bulk record requires a bag count greater than zero',
        );
      }
    } else {
      // Individual behaviour is exactly as before.
      if (bagWeights.isEmpty) {
        throw ArgumentError.value(
          bagWeights,
          'bagWeights',
          'must not be empty',
        );
      }

      for (final weight in bagWeights) {
        if (!weight.isFinite || weight <= 0) {
          throw ArgumentError.value(
            weight,
            'bagWeights',
            'must contain finite values greater than zero',
          );
        }
      }
      if (bagRecordedByUserIds != null &&
          bagRecordedByUserIds.isNotEmpty &&
          bagRecordedByUserIds.length != this.bagWeights.length) {
        throw ArgumentError.value(
          bagRecordedByUserIds,
          'bagRecordedByUserIds',
          'must have one recorder entry per bag weight',
        );
      }
    }
  }

  final String id;
  final Supplier supplier;
  final Product product;
  final DateTime recordedAt;

  /// The individual bag weights. This stays authoritative for an individual
  /// record and is ALWAYS empty for a bulk record.
  final List<double> bagWeights;

  /// How this delivery was weighed. Existing records are individual.
  final DeliveryRecordType recordType;

  /// The weighing-bridge total. Authoritative only for a bulk record.
  final double? bulkTotalWeight;

  /// The number of bags reported by the weighing bridge. Authoritative only for
  /// a bulk record.
  final int? bulkBagCount;

  /// Optional free text, used mainly for weighing-bridge remarks.
  final String? notes;

  /// Authenticated account that recorded the delivery, or null for legacy data.
  final String? recordedByUserId;

  /// Per-bag recorder IDs. An empty list means older callers supplied only the
  /// delivery recorder; a null item explicitly means that bag is unassigned.
  final List<String?> bagRecordedByUserIds;
  final String? companyId;
  final DeliveryStatus status;
  final SynchronizationStatus synchronizationStatus;
  final DateTime updatedAt;

  bool get needsSynchronization =>
      synchronizationStatus != SynchronizationStatus.synced &&
      synchronizationStatus != SynchronizationStatus.synchronized;

  bool get isBulk => recordType == DeliveryRecordType.bulk;

  bool get isIndividual => recordType == DeliveryRecordType.individual;

  /// The number of bags: the stored count for a bulk record, otherwise the
  /// number of individually weighed bags.
  int get numberOfBags => isBulk ? (bulkBagCount ?? 0) : bagWeights.length;

  String? recorderForBag(int index) => bagRecordedByUserIds.isEmpty
      ? recordedByUserId
      : bagRecordedByUserIds[index];

  /// Sentinel meaning "leave this field exactly as it is".
  ///
  /// The bulk fields are nullable, so a plain nullable parameter could not tell
  /// "not supplied" from "set to null". Without this, an unrelated copyWith
  /// call would silently clear a weighing-bridge total.
  static const Object _keep = Object();

  Delivery copyWith({
    Supplier? supplier,
    Product? product,
    DateTime? recordedAt,
    List<double>? bagWeights,
    String? recordedByUserId,
    List<String?>? bagRecordedByUserIds,
    String? companyId,
    DeliveryStatus? status,
    SynchronizationStatus? synchronizationStatus,
    DeliveryRecordType? recordType,
    Object? bulkTotalWeight = _keep,
    Object? bulkBagCount = _keep,
    Object? notes = _keep,
    DateTime? updatedAt,
  }) => Delivery(
    id: id,
    supplier: supplier ?? this.supplier,
    product: product ?? this.product,
    recordedAt: recordedAt ?? this.recordedAt,
    bagWeights: bagWeights ?? this.bagWeights,
    recordedByUserId: recordedByUserId ?? this.recordedByUserId,
    bagRecordedByUserIds: bagRecordedByUserIds ?? this.bagRecordedByUserIds,
    companyId: companyId ?? this.companyId,
    status: status ?? this.status,
    synchronizationStatus: synchronizationStatus ?? this.synchronizationStatus,
    recordType: recordType ?? this.recordType,
    bulkTotalWeight: identical(bulkTotalWeight, _keep)
        ? this.bulkTotalWeight
        // A whole-number total such as 60000 is a perfectly natural call, so an
        // int is accepted and converted rather than failing the cast.
        : (bulkTotalWeight as num?)?.toDouble(),
    bulkBagCount: identical(bulkBagCount, _keep)
        ? this.bulkBagCount
        : (bulkBagCount as num?)?.toInt(),
    notes: identical(notes, _keep) ? this.notes : notes as String?,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  /// The total weight in kilograms.
  ///
  /// For an individual record this is still derived from the bag weights, so
  /// existing totals cannot change. For a bulk record the stored weighing
  /// bridge total is authoritative.
  double get totalWeight =>
      isBulk ? (bulkTotalWeight ?? 0) : calculateTotalWeight(bagWeights);

  static double calculateTotalWeight(Iterable<double> weights) {
    return weights.fold<double>(0, (total, weight) => total + weight);
  }
}

String recorderDisplayName(String? userId, Map<String, String> namesByUserId) {
  if (userId == null || userId.trim().isEmpty || userId == 'local-secretary') {
    return 'Not recorded';
  }
  return namesByUserId[userId] ?? 'Unknown user';
}
