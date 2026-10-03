import 'package:flutter_application_2/domain/models/delivery.dart';
import 'package:flutter_application_2/domain/models/product.dart';
import 'package:flutter_application_2/domain/models/supplier.dart';
import 'package:flutter_application_2/features/receiving/delivery_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database database;
  late DeliveryRepository repository;

  setUp(() async {
    sqfliteFfiInit();
    database = await databaseFactoryFfi.openDatabase(
      ':memory:',
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (database, version) async {
          await database.execute('''
        CREATE TABLE deliveries (
            id TEXT PRIMARY KEY,
            supplier_id TEXT NOT NULL,
            product_id TEXT NOT NULL,
            recorded_at TEXT NOT NULL,
            recorded_by_user_id TEXT,
            company_id TEXT,
            status TEXT NOT NULL,
            synchronization_status TEXT NOT NULL,
            supplier_name TEXT NOT NULL,
            product_name TEXT NOT NULL,
            supplier_type TEXT NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');
          await database.execute('''
          CREATE TABLE delivery_bag_weights (
            delivery_id TEXT NOT NULL,
            company_id TEXT,
            bag_number INTEGER NOT NULL,
            weight REAL NOT NULL,
            recorded_by_user_id TEXT,
            PRIMARY KEY (delivery_id, bag_number)
          )
        ''');
        },
      ),
    );
    repository = DeliveryRepository(database);
  });

  tearDown(() => database.close());

  test('saves a delivery and every individual bag weight in one database operation', () async {
    final supplier = Supplier(
      id: 'ALB-000001',
      name: 'Ibrahim Mensah',
      type: SupplierType.aggregator,
      town: 'Techiman',
      district: 'Techiman Municipal',
      region: 'Bono East',
    );
    final delivery = Delivery(
      id: 'delivery-1',
      supplier: supplier,
      product: Product.cashew,
      recordedAt: DateTime(2026, 9, 21),
      bagWeights: [82.5, 79.8, 81.2],
      recordedByUserId: 'secretary-1',
    );

    await repository.save(delivery);

    expect(await repository.count(), 1);
    final rows = await database.query(
      'delivery_bag_weights',
      orderBy: 'bag_number',
    );
    expect(rows.map((row) => row['weight']), [82.5, 79.8, 81.2]);
  });

  test('attributes each bag to its authenticated secretary and scopes it to company', () async {
    var userId = 'secretary-a';
    var companyId = 'company-a';
    repository = DeliveryRepository(
      database,
      companyIdProvider: () => companyId,
      userIdProvider: () => userId,
    );
    final supplier = Supplier(
      id: 'ALB-tenant-1',
      name: 'Ibrahim Mensah',
      type: SupplierType.farmer,
      town: 'Tamale',
      district: 'Tamale Metro',
      region: 'Northern',
      companyId: companyId,
    );

    Future<void> saveAs(String id) => repository.save(
      Delivery(
        id: id,
        supplier: supplier,
        product: Product.cashew,
        recordedAt: DateTime(2026, 9, 21),
        bagWeights: [80, 75],
        recordedByUserId: null,
        bagRecordedByUserIds: [null, null],
        companyId: companyId,
      ),
    );

    await saveAs('delivery-a');
    userId = 'secretary-b';
    await saveAs('delivery-b');

    final deliveries = await database.query('deliveries', orderBy: 'id');
    expect(deliveries.map((row) => row['recorded_by_user_id']), [
      'secretary-a',
      'secretary-b',
    ]);
    final weights = await database.query(
      'delivery_bag_weights',
      orderBy: 'delivery_id, bag_number',
    );
    expect(weights.map((row) => row['recorded_by_user_id']), [
      'secretary-a',
      'secretary-a',
      'secretary-b',
      'secretary-b',
    ]);

    companyId = 'company-b';
    expect(await repository.forDate(DateTime(2026, 9, 21)), isEmpty);
  });

  test(
    'rejects a caller trying to create a delivery for another user',
    () async {
      repository = DeliveryRepository(
        database,
        companyIdProvider: () => 'company-a',
        userIdProvider: () => 'secretary-a',
      );
      final supplier = Supplier(
        id: 'ALB-tenant-1',
        name: 'Ibrahim Mensah',
        type: SupplierType.farmer,
        town: 'Tamale',
        district: 'Tamale Metro',
        region: 'Northern',
        companyId: 'company-a',
      );
      final forged = Delivery(
        id: 'delivery-forged',
        supplier: supplier,
        product: Product.cashew,
        recordedAt: DateTime(2026, 9, 21),
        bagWeights: [80],
        recordedByUserId: 'secretary-b',
        companyId: 'company-a',
      );

      await expectLater(repository.save(forged), throwsA(isA<StateError>()));
      expect(await database.query('deliveries'), isEmpty);
    },
  );

  test('keeps legacy deliveries and weights unassigned', () async {
    await database.insert('deliveries', {
      'id': 'legacy-delivery',
      'supplier_id': 'supplier-1',
      'product_id': 'cashew',
      'recorded_at': DateTime(2020, 1, 1).toIso8601String(),
      'recorded_by_user_id': null,
      'company_id': 'company-a',
      'status': 'received',
      'synchronization_status': 'synced',
      'supplier_name': 'Legacy supplier',
      'product_name': 'Cashew',
      'supplier_type': 'farmer',
      'created_at': DateTime(2020, 1, 1).toIso8601String(),
      'updated_at': DateTime(2020, 1, 1).toIso8601String(),
    });
    await database.insert('delivery_bag_weights', {
      'delivery_id': 'legacy-delivery',
      'company_id': 'company-a',
      'bag_number': 1,
      'weight': 50,
      'recorded_by_user_id': null,
    });
    repository = DeliveryRepository(
      database,
      companyIdProvider: () => 'company-a',
    );

    final legacy = await repository.findById('legacy-delivery');

    expect(legacy!.recordedByUserId, isNull);
    expect(legacy.bagRecordedByUserIds, [null]);
  });

  test('delivery calculation derives count and total from bag weights', () {
    final supplier = Supplier(
      id: 'ALB-000001',
      name: 'Ibrahim Mensah',
      type: SupplierType.farmer,
      town: 'Techiman',
      district: 'Techiman Municipal',
      region: 'Bono East',
    );
    final delivery = Delivery(
      id: 'delivery-2',
      supplier: supplier,
      product: Product.cocoa,
      recordedAt: DateTime(2026, 9, 21),
      bagWeights: [82.5, 79.8, 81.2],
      recordedByUserId: 'secretary-1',
    );

    expect(delivery.numberOfBags, 3);
    expect(delivery.totalWeight, closeTo(243.5, 0.0001));
  });

  test(
    'returns only the selected date and supports controlled correction',
    () async {
      final supplier = Supplier(
        id: 'ALB-000001',
        name: 'Ibrahim Mensah',
        type: SupplierType.farmer,
        town: 'Techiman',
        district: 'Techiman Municipal',
        region: 'Bono East',
      );
      final today = Delivery(
        id: 'delivery-today',
        supplier: supplier,
        product: Product.cashew,
        recordedAt: DateTime(2026, 9, 21, 10),
        bagWeights: [80, 70],
        recordedByUserId: 'secretary-1',
      );
      final yesterday = Delivery(
        id: 'delivery-yesterday',
        supplier: supplier,
        product: Product.cashew,
        recordedAt: DateTime(2026, 9, 20, 10),
        bagWeights: [100],
        recordedByUserId: 'secretary-1',
      );

      await repository.save(today);
      await repository.save(yesterday);

      final records = await repository.forDate(DateTime(2026, 9, 21));
      expect(records.map((delivery) => delivery.id), ['delivery-today']);
      expect(records.single.numberOfBags, 2);
      expect(records.single.totalWeight, 150);

      final corrected = await repository.updateWeights(today.id, [
        82.5,
        79.8,
        81.2,
      ]);
      expect(corrected.status, DeliveryStatus.corrected);
      expect(corrected.synchronizationStatus, SynchronizationStatus.pending);
      expect(corrected.numberOfBags, 3);
      expect(corrected.totalWeight, closeTo(243.5, 0.0001));
      final savedWeights = await database.query(
        'delivery_bag_weights',
        where: 'delivery_id = ?',
        whereArgs: [today.id],
        orderBy: 'bag_number',
      );
      expect(savedWeights.map((row) => row['recorded_by_user_id']), [
        'secretary-1',
        'secretary-1',
        null,
      ]);
    },
  );
}
