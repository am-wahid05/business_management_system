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

  /// Runs one full synchronization round trip.
  ///
  /// The two directions are deliberately independent. Previously any error in
  /// the catalog or download pass propagated out of this method, and because
  /// the uploads had already been committed the user saw "Sync failed" even
  /// though their record was safely on the server. Now the upload phase marks
  /// each delivery according to what actually happened to it, and the download
  /// phase reports its own problems as warnings that never rewrite a
  /// delivery state.
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
    final warnings = <String>[];
    try {
      final catalogStore = remoteStore is CompanyCatalogStore
          ? remoteStore as CompanyCatalogStore
          : null;

      // Pushing the local supplier and product catalog. A failure here is
      // worth reporting, but it must not stop deliveries being uploaded.
      if (catalogStore != null) {
        try {
          await catalogStore.synchronizeCatalog();
        } on Object catch (error) {
          warnings.add('Supplier catalog could not be uploaded: $error');
        }
      }

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
        } on SyncPartiallyAppliedException catch (error) {
          // The delivery row was accepted by the server before a later write
          // for that same delivery failed. The record really is on Supabase, so
          // it is marked synced rather than failed, and the user is simply told
          // the follow-up needs another attempt.
          await deliveryRepository.markSynced(delivery.id, DateTime.now());
          synced++;
          warnings.add('${error.deliveryId}: uploaded, but ${error.message}');
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

      // Pulling the company back down. This runs only after every delivery has
      // been dealt with and can no longer retroactively mark any of them as
      // failed.
      if (catalogStore != null) {
        try {
          await catalogStore.downloadCompany();
          await onDownloaded?.call();
        } on Object catch (error) {
          warnings.add(
            'Records were uploaded, but the latest company data could not be '
            'downloaded: $error',
          );
        }
      }

      return SyncSummary(
        attempted: pending.length,
        synced: synced,
        failed: failures.length,
        failures: failures,
        warnings: List.unmodifiable(warnings),
      );
    } finally {
      _isSynchronizing = false;
    }
  }
}