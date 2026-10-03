import 'package:sqflite/sqflite.dart';

class SyncStatusSnapshot {
  const SyncStatusSnapshot({
    required this.pendingCount,
    required this.failedCount,
    this.lastSuccessfulSync,
  });

  final int pendingCount;
  final int failedCount;
  final DateTime? lastSuccessfulSync;

  bool get hasFailures => failedCount > 0;
  bool get hasPending => pendingCount > 0;
}

class SyncStatusRepository {
  const SyncStatusRepository(this.database, {this.companyIdProvider});

  final Database database;
  final String? Function()? companyIdProvider;

  Future<SyncStatusSnapshot> load() async {
    if (companyIdProvider != null && companyIdProvider!() == null) {
      return const SyncStatusSnapshot(pendingCount: 0, failedCount: 0);
    }
    final pending = await database.rawQuery(
      '''
      SELECT COUNT(*) AS count FROM deliveries
      WHERE synchronization_status IN (?, ?, ?, ?) ${companyIdProvider == null ? '' : 'AND company_id IS ?'}
    ''',
      [
        'localOnly',
        'pendingSync',
        'pending',
        'syncFailed',
        if (companyIdProvider != null) companyIdProvider!(),
      ],
    );
    final failed = await database.rawQuery(
      '''
      SELECT COUNT(*) AS count FROM deliveries
      WHERE synchronization_status IN (?, ?) ${companyIdProvider == null ? '' : 'AND company_id IS ?'}
    ''',
      [
        'syncFailed',
        'failed',
        if (companyIdProvider != null) companyIdProvider!(),
      ],
    );
    final latest = await database.rawQuery(
      '''
      SELECT MAX(synced_at) AS synced_at FROM deliveries
      WHERE synchronization_status IN (?, ?) AND synced_at IS NOT NULL ${companyIdProvider == null ? '' : 'AND company_id IS ?'}
    ''',
      [
        'synced',
        'synchronized',
        if (companyIdProvider != null) companyIdProvider!(),
      ],
    );
    final rawLatest = latest.single['synced_at'];
    return SyncStatusSnapshot(
      pendingCount: pending.single['count']! as int,
      failedCount: failed.single['count']! as int,
      lastSuccessfulSync: rawLatest == null
          ? null
          : DateTime.tryParse(rawLatest as String),
    );
  }
}
