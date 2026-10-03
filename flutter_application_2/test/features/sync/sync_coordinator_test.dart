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
