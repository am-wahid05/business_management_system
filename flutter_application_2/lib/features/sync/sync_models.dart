import '../../domain/models/delivery.dart';

class SyncFailure {
  const SyncFailure({
    required this.deliveryId,
    required this.message,
    required this.attemptedAt,
  });

  final String deliveryId;
  final String message;
  final DateTime attemptedAt;
}

class SyncSummary {
  const SyncSummary({
    required this.attempted,
    required this.synced,
    required this.failed,
    required this.failures,
  });

  final int attempted;
  final int synced;
  final int failed;
  final List<SyncFailure> failures;
}

abstract interface class RemoteDeliveryStore {
  Future<void> upsert(Delivery delivery);
}

abstract interface class CompanyCatalogStore implements RemoteDeliveryStore {
  Future<void> synchronizeCatalog();
  Future<void> downloadCompany();
}
