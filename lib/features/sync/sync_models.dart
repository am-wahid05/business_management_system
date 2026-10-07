import '../../domain/models/delivery.dart';

/// Company identity captured once for a complete synchronization run.
class SyncScope {
  const SyncScope({required this.companyId, required this.isCompanyScoped});

  final String? companyId;
  final bool isCompanyScoped;
}

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
    this.warnings = const [],
  });

  final int attempted;
  final int synced;
  final int failed;
  final List<SyncFailure> failures;

  /// Non-fatal problems that did not stop any delivery from being stored
  /// safely. A warning never marks a delivery as failed; it only means the
  /// download side of the round trip needs another attempt.
  final List<String> warnings;

  /// Every delivery the server accepted.
  bool get uploadedEverything => failed == 0 && attempted > 0;

  /// Uploads worked but the catalog/download pass did not.
  bool get isPartial => failed == 0 && warnings.isNotEmpty;
}

/// Raised when a delivery row was confirmed on the server but a follow-up
/// write for the same delivery then failed.
///
/// This is deliberately distinct from an ordinary failure. The delivery itself
/// reached Supabase, so marking it "sync failed" would be untrue and would make
/// the user retry an upload that has already succeeded.
class SyncPartiallyAppliedException implements Exception {
  const SyncPartiallyAppliedException(this.deliveryId, this.message);

  final String deliveryId;
  final String message;

  @override
  String toString() => 'Sync partially applied for $deliveryId: $message';
}

abstract interface class RemoteDeliveryStore {
  Future<void> upsert(Delivery delivery, {required SyncScope scope});
}

abstract interface class CompanyCatalogStore implements RemoteDeliveryStore {
  Future<void> synchronizeCatalog({required SyncScope scope});
  Future<void> downloadCompany({required SyncScope scope});
}
