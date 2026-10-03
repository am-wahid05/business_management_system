import 'package:sqflite/sqflite.dart';

import '../receiving/delivery_repository.dart';
import 'sync_models.dart';

class SyncCoordinator {
  SyncCoordinator({
    required this.database,
    required this.deliveryRepository,
    required this.remoteStore,
    this.onDownloaded,
  });

  final Database database;
  final DeliveryRepository deliveryRepository;
  final RemoteDeliveryStore remoteStore;
  final Future<void> Function()? onDownloaded;
  bool _isSynchronizing = false;

  Future<SyncSummary> synchronize() async {
    if (_isSynchronizing) {
      return const SyncSummary(
        attempted: 0,
        synced: 0,
        failed: 0,
        failures: [],
      );
    }
    _isSynchronizing = true;
    try {
    final catalogStore = remoteStore;
    if (catalogStore is CompanyCatalogStore) await catalogStore.synchronizeCatalog();
    final pending = await deliveryRepository.unsynchronized();
    final failures = <SyncFailure>[];
    var synced = 0;
    for (final delivery in pending) {
      final attemptedAt = DateTime.now();
      await deliveryRepository.recordSyncAttempt(delivery.id, attemptedAt);
      try {
        await remoteStore.upsert(delivery);
        await deliveryRepository.markSynced(delivery.id, DateTime.now());
        synced++;
      } on Object catch (error) {
        final message = error.toString();
        await deliveryRepository.markSyncFailed(
          delivery.id,
          message,
          attemptedAt,
        );
        failures.add(
          SyncFailure(
            deliveryId: delivery.id,
            message: message,
            attemptedAt: attemptedAt,
          ),
        );
      }
    }
    if (catalogStore is CompanyCatalogStore) {
      await catalogStore.downloadCompany();
      await onDownloaded?.call();
    }
      return SyncSummary(
        attempted: pending.length,
        synced: synced,
        failed: failures.length,
        failures: failures,
      );
    } finally {
      _isSynchronizing = false;
    }
  }
}
