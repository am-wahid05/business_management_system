import 'package:flutter_application_2/domain/models/delivery.dart';
import 'package:flutter_application_2/domain/models/product.dart';
import 'package:flutter_application_2/domain/models/supplier.dart';
import 'package:flutter_application_2/features/receiving/delivery_repository.dart';
import 'package:flutter_application_2/features/sync/sync_coordinator.dart';
import 'package:flutter_application_2/features/sync/sync_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class FakeRemoteStore implements RemoteDeliveryStore {
  final uploadedIds = <String>[];
  final failuresRemaining = <String, int>{};

  @override
  Future<void> upsert(Delivery delivery) async {
    final remaining = failuresRemaining[delivery.id] ?? 0;
    if (remaining > 0) {
      failuresRemaining[delivery.id] = remaining - 1;
      throw StateError('temporary network failure');
    }
    if (!uploadedIds.contains(delivery.id)) uploadedIds.add(delivery.id);
  }
}

/// A store whose delivery row is accepted and only a LATER follow-up write
/// fails. This reproduces the real reported symptom: the admin receives the
/// record, yet the secretary used to be told the upload had failed.
class PartiallyFailingStore implements CompanyCatalogStore {
  final uploadedIds = <String>[];

  @override
  Future<void> upsert(Delivery delivery) async {
    uploadedIds.add(delivery.id);
    // The server has already stored the delivery row at this point.
    throw const SyncPartiallyAppliedException(
      'x',
      'its bag weights could not be saved on the server.',
    );
  }

  @override
  Future<void> synchronizeCatalog() async {}

  @override
  Future<void> downloadCompany() async {
    throw StateError('download blocked');
  }
}

/// Every catalog and download call fails, while delivery uploads succeed.
class DownloadFailingStore implements CompanyCatalogStore {
  final uploadedIds = <String>[];

  @override
  Future<void> upsert(Delivery delivery) async => uploadedIds.add(delivery.id);

  @override
  Future<void> synchronizeCatalog() async =>
      throw StateError('catalog rejected');

  @override
  Future<void> downloadCompany() async =>
      throw StateError('download blocked');
}

void main() {
  late Database database;
  late DeliveryRepository repository;
  late FakeRemoteStore remote;
  late SyncCoordinator coordinator;

  setUp(() async {
    sqfliteFfiInit();
    database = await databaseFactoryFfi.openDatabase(
      ':memory:',
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (database, version) async {
          await database.execute('''
          CREATE TABLE suppliers (
            supplier_id TEXT NOT NULL,
            company_id TEXT,
            name TEXT NOT NULL,
            is_active INTEGER NOT NULL DEFAULT 1,
            supplier_type TEXT NOT NULL,
            phone TEXT,
            town TEXT NOT NULL DEFAULT '',
            district TEXT NOT NULL DEFAULT '',
            region TEXT NOT NULL DEFAULT '',
            normalized_name TEXT NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            PRIMARY KEY (company_id, supplier_id)
          )
        ''');
          await database.execute('''
        CREATE TABLE deliveries (
          id TEXT PRIMARY KEY, supplier_id TEXT NOT NULL, product_id TEXT NOT NULL,
          recorded_at TEXT NOT NULL, recorded_by_user_id TEXT NOT NULL, status TEXT NOT NULL,
          synchronization_status TEXT NOT NULL, supplier_name TEXT NOT NULL, product_name TEXT NOT NULL,
          supplier_type TEXT NOT NULL, synchronization_error TEXT, sync_attempts INTEGER NOT NULL DEFAULT 0,
          last_sync_attempt_at TEXT, synced_at TEXT, created_at TEXT NOT NULL, updated_at TEXT NOT NULL
        )
      ''');
          await database.execute(
            '''CREATE TABLE delivery_bag_weights (delivery_id TEXT NOT NULL, bag_number INTEGER NOT NULL, weight REAL NOT NULL, PRIMARY KEY (delivery_id, bag_number))''',
          );
        },
      ),
    );
    repository = DeliveryRepository(database);
    remote = FakeRemoteStore();
    coordinator = SyncCoordinator(
      database: database,
      deliveryRepository: repository,
      remoteStore: remote,
    );
  });

  tearDown(() => database.close());

  test(
    'offline creation remains pending and successful sync is idempotent',
    () async {
      await repository.save(_delivery('one'));
      expect((await repository.unsynchronized()).single.id, 'one');

      final first = await coordinator.synchronize();
      final second = await coordinator.synchronize();

      expect(first.synced, 1);
      expect(second.attempted, 0);
      expect(remote.uploadedIds, ['one']);
      final row = (await database.query('deliveries')).single;
      expect(row['synchronization_status'], 'synced');
      expect(row['synced_at'], isNotNull);
    },
  );

  test('failed sync preserves the record and retry succeeds', () async {
    await repository.save(_delivery('retry'));
    remote.failuresRemaining['retry'] = 1;

    final failed = await coordinator.synchronize();
    expect(failed.failed, 1);
    expect((await repository.unsynchronized()).single.id, 'retry');
    expect(
      (await database.query('deliveries')).single['synchronization_error'],
      contains('temporary'),
    );

    final retried = await coordinator.synchronize();
    expect(retried.synced, 1);
    expect((await repository.unsynchronized()), isEmpty);
  });

  test(
    'a delivery accepted by the server is NOT marked failed when only a '
    'later follow-up write fails',
    () async {
      await repository.save(_delivery('partial'));
      final store = PartiallyFailingStore();
      final subject = SyncCoordinator(
        database: database,
        deliveryRepository: repository,
        remoteStore: store,
      );

      final summary = await subject.synchronize();

      // The server has the record.
      expect(store.uploadedIds, ['partial']);
      // ...so the local state must say it was delivered, not failed.
      final row = (await database.query('deliveries')).single;
      expect(row['synchronization_status'], 'synced');
      expect(row['synchronization_error'], isNull);
      expect(summary.failed, 0, reason: 'a confirmed upload is not a failure');
      expect(summary.synced, 1);
      expect(summary.warnings, isNotEmpty);
      // And it must not be re-uploaded on the next run.
      expect(await repository.unsynchronized(), isEmpty);
    },
  );

  test(
    'a failing catalog or download is reported as a warning and never marks an '
    'uploaded delivery as failed',
    () async {
      await repository.save(_delivery('downloaded'));
      final store = DownloadFailingStore();
      final subject = SyncCoordinator(
        database: database,
        deliveryRepository: repository,
        remoteStore: store,
      );

      final summary = await subject.synchronize();

      expect(store.uploadedIds, ['downloaded']);
      final row = (await database.query('deliveries')).single;
      expect(row['synchronization_status'], 'synced');
      expect(summary.failed, 0);
      expect(summary.synced, 1);
      expect(
        summary.warnings.join(' '),
        contains('could not be downloaded'),
      );
      expect(summary.warnings.join(' '), contains('catalog could not be uploaded'));
    },
  );

  test(
    'syncs multiple pending records and prevents duplicate remote uploads',
    () async {
      await repository.save(_delivery('a'));
      await repository.save(_delivery('b'));
      await repository.save(_delivery('c'));

      final summary = await coordinator.synchronize();
      expect(summary.attempted, 3);
      expect(summary.synced, 3);
      expect(remote.uploadedIds, containsAll(['a', 'b', 'c']));
      await coordinator.synchronize();
      expect(remote.uploadedIds.length, 3);
    },
  );
}

Delivery _delivery(String id) {
  final supplier = Supplier(
    id: 'ALB-000001',
    name: 'Ibrahim Mensah',
    type: SupplierType.aggregator,
    town: 'Techiman',
    district: 'Techiman Municipal',
    region: 'Bono East',
  );
  return Delivery(
    id: id,
    supplier: supplier,
    product: Product.cashew,
    recordedAt: DateTime(2026, 9, 21),
    bagWeights: [80, 70],
    recordedByUserId: 'secretary',
  );
}
