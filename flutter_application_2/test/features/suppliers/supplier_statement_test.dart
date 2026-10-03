import 'package:flutter_application_2/domain/models/delivery.dart';
import 'package:flutter_application_2/domain/models/product.dart';
import 'package:flutter_application_2/domain/models/supplier.dart';
import 'package:flutter_application_2/features/receiving/delivery_repository.dart';
import 'package:flutter_application_2/features/suppliers/supplier_statement.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database database;
  late DeliveryRepository repository;
  late SupplierStatementService service;

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
          await database.execute('''
            CREATE TABLE delivery_bag_weights (
              delivery_id TEXT NOT NULL, bag_number INTEGER NOT NULL, weight REAL NOT NULL,
              PRIMARY KEY (delivery_id, bag_number)
            )
          ''');
        },
      ),
    );
    repository = DeliveryRepository(database);
    service = SupplierStatementService(repository);
  });

  tearDown(() => database.close());

  test('includes the end date and excludes other suppliers', () async {
    final supplier = _supplier('supplier-a', 'Ibrahim Mensah');
    final otherSupplier = _supplier('supplier-b', 'Other Supplier');
    await repository.save(_delivery('before', supplier, DateTime(2026, 1, 1), [50]));
    await repository.save(_delivery('on-end', supplier, DateTime(2026, 9, 20), [80, 70]));
    await repository.save(_delivery('other', otherSupplier, DateTime(2026, 9, 20), [100]));
    await repository.save(_delivery('after', supplier, DateTime(2026, 9, 21), [90]));

    final statement = await service.build(
      supplier: supplier,
      from: DateTime(2026, 1, 1),
      to: DateTime(2026, 9, 20),
    );

    expect(statement.deliveries.map((delivery) => delivery.id), ['on-end', 'before']);
    expect(statement.totalBags, 3);
    expect(statement.totalWeight, 200);
  });

  test('rejects a range whose end precedes its start', () async {
    expect(
      () => service.build(
        supplier: _supplier('supplier-a', 'Ibrahim Mensah'),
        from: DateTime(2026, 9, 20),
        to: DateTime(2026, 9, 1),
      ),
      throwsArgumentError,
    );
  });
}

Supplier _supplier(String id, String name) => Supplier(
      id: id,
      name: name,
      type: SupplierType.farmer,
      town: 'Techiman',
      district: 'Techiman Municipal',
      region: 'Bono East',
    );

Delivery _delivery(String id, Supplier supplier, DateTime recordedAt, List<double> weights) => Delivery(
      id: id,
      supplier: supplier,
      product: Product.cashew,
      recordedAt: recordedAt,
      bagWeights: weights,
      recordedByUserId: 'admin',
    );
