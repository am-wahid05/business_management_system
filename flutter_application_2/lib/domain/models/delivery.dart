import 'product.dart';
import 'supplier.dart';

enum DeliveryStatus { draft, received, corrected, cancelled }

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
    DateTime? updatedAt,
  }) : bagWeights = List.unmodifiable(bagWeights),
       bagRecordedByUserIds = List.unmodifiable(
         bagRecordedByUserIds ?? const <String?>[],
       ),
       updatedAt = updatedAt ?? recordedAt {
    if (this.bagWeights.isEmpty) {
      throw ArgumentError.value(bagWeights, 'bagWeights', 'must not be empty');
    }

    for (final weight in this.bagWeights) {
      if (!weight.isFinite || weight <= 0) {
        throw ArgumentError.value(
          weight,
          'bagWeights',
          'must contain finite values greater than zero',
        );
      }
    }
    if (this.bagRecordedByUserIds.isNotEmpty &&
        this.bagRecordedByUserIds.length != this.bagWeights.length) {
      throw ArgumentError.value(
        bagRecordedByUserIds,
        'bagRecordedByUserIds',
        'must have one recorder entry per bag weight',
      );
    }
  }

  final String id;
  final Supplier supplier;
  final Product product;
  final DateTime recordedAt;
  final List<double> bagWeights;

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

  int get numberOfBags => bagWeights.length;

  String? recorderForBag(int index) => bagRecordedByUserIds.isEmpty
      ? recordedByUserId
      : bagRecordedByUserIds[index];

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
    updatedAt: updatedAt ?? this.updatedAt,
  );

  double get totalWeight => calculateTotalWeight(bagWeights);

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
