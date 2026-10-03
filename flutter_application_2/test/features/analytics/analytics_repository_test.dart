import 'package:flutter_application_2/features/analytics/analytics_models.dart';
import 'package:flutter_application_2/features/analytics/analytics_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database database;
  late AnalyticsRepository repository;

  setUp(() async {
    sqfliteFfiInit();
    database = await databaseFactoryFfi.openDatabase(
      ':memory:',
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (database, version) async {
          await database.execute('''
            CREATE TABLE deliveries (
              id TEXT PRIMARY KEY, company_id TEXT, supplier_id TEXT NOT NULL, product_id TEXT NOT NULL,
              recorded_at TEXT NOT NULL, recorded_by_user_id TEXT NOT NULL, status TEXT NOT NULL,
              synchronization_status TEXT NOT NULL, supplier_internal_id TEXT,
              supplier_name TEXT NOT NULL, product_name TEXT NOT NULL, supplier_type TEXT NOT NULL,
              created_at TEXT NOT NULL, updated_at TEXT NOT NULL
            )
          ''');
          await database.execute('''
            CREATE TABLE delivery_bag_weights (
              delivery_id TEXT NOT NULL, company_id TEXT, bag_number INTEGER NOT NULL, weight REAL NOT NULL,
              PRIMARY KEY (delivery_id, bag_number)
            )
          ''');
          await database.execute('''
            CREATE TABLE suppliers (
              internal_id TEXT PRIMARY KEY, company_id TEXT, supplier_id TEXT NOT NULL,
              normalized_name TEXT NOT NULL, name TEXT NOT NULL, type TEXT NOT NULL,
              phone TEXT, town TEXT NOT NULL, district TEXT NOT NULL, region TEXT NOT NULL,
              notes TEXT, is_active INTEGER NOT NULL, created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL, synchronization_status TEXT NOT NULL,
              synchronization_error TEXT
            )
          ''');
        },
      ),
    );
    repository = AnalyticsRepository(database);
    await _insertSupplier(
      database,
      's1',
      'ALB-000001',
      'Ibrahim Mensah',
      'aggregator',
      'Techiman',
      true,
    );
    await _insertSupplier(
      database,
      's2',
      'ALB-000002',
      'Ama Boateng',
      'farmer',
      'Kintampo',
      true,
    );
    await _insertDelivery(
      database,
      'd1',
      'ALB-000001',
      'cashew',
      'Cashew',
      'aggregator',
      '2026-09-01T10:00:00',
      [80, 70],
    );
    await _insertDelivery(
      database,
      'd2',
      'ALB-000001',
      'cocoa',
      'Cocoa',
      'aggregator',
      '2026-09-15T10:00:00',
      [50],
    );
    await _insertDelivery(
      database,
      'd3',
      'ALB-000002',
      'cashew',
      'Cashew',
      'farmer',
      '2026-09-15T11:00:00',
      [60],
    );
    await _insertDelivery(
      database,
      'cancelled',
      'ALB-000002',
      'cashew',
      'Cashew',
      'farmer',
      '2026-09-15T12:00:00',
      [999],
      status: 'cancelled',
    );
  });

  tearDown(() => database.close());

  test(
    'summary uses SQL aggregates and excludes cancelled deliveries',
    () async {
      final summary = await repository.summary(_filters());

      expect(summary.deliveryCount, 3);
      expect(summary.totalBags, 4);
      expect(summary.totalWeight, 260);
      expect(summary.uniqueSuppliers, 2);
      expect(summary.uniqueFarmers, 1);
      expect(summary.uniqueAggregators, 1);
      expect(summary.activeSuppliers, 2);
      expect(summary.productCount, 2);
      expect(summary.averageWeightPerBag, 65);
      expect(summary.averageWeightPerDelivery, closeTo(86.666, 0.001));
    },
  );

  test('breakdowns and filters work together', () async {
    final products = await repository.productBreakdown(
      _filters(supplierType: 'aggregator', town: 'Techiman'),
    );
    expect(products, hasLength(2));
    expect(products.first.productName, 'Cashew');
    expect(products.first.totalWeight, 150);

    final suppliers = await repository.supplierBreakdown(
      _filters(productId: 'cashew'),
    );
    expect(suppliers, hasLength(2));
    expect(suppliers.first.supplierId, 'ALB-000001');
    expect(suppliers.first.totalBags, 2);
  });

  test('monthly trend returns only periods with records', () async {
    final trend = await repository.trend(_filters(), AnalyticsTrend.monthly);

    expect(trend.map((item) => item.period), ['2026-09']);
    expect(trend.single.totalWeight, 260);
    expect(trend.single.totalBags, 4);
  });

  test('empty periods return zero-safe metrics', () async {
    final summary = await repository.summary(
      AnalyticsFilters(from: DateTime(2027, 1, 1), to: DateTime(2027, 1, 31)),
    );

    expect(summary.deliveryCount, 0);
    expect(summary.totalWeight, 0);
    expect(summary.averageWeightPerBag, 0);
    expect(summary.averageWeightPerDelivery, 0);
  });

  test('analytics joins and filters stay within the active company', () async {
    await _insertSupplier(
      database,
      'tenant-a-supplier',
      'shared-id',
      'Tenant A Supplier',
      'farmer',
      'A town',
      true,
      companyId: 'tenant-a',
    );
    await _insertSupplier(
      database,
      'tenant-b-supplier',
      'shared-id',
      'Tenant B Supplier',
      'farmer',
      'B town',
      true,
      companyId: 'tenant-b',
    );
    await _insertDelivery(
      database,
      'tenant-a-delivery',
      'shared-id',
      'cashew',
      'Cashew',
      'farmer',
      '2026-09-20T10:00:00',
      [10],
      companyId: 'tenant-a',
    );
    await _insertDelivery(
      database,
      'tenant-b-delivery',
      'shared-id',
      'cashew',
      'Cashew',
      'farmer',
      '2026-09-20T10:00:00',
      [900],
      companyId: 'tenant-b',
    );

    final tenantA = AnalyticsRepository(
      database,
      companyIdProvider: () => 'tenant-a',
    );
    final summary = await tenantA.summary(_filters());
    final locations = await tenantA.locationBreakdown(_filters());

    expect(summary.deliveryCount, 1);
    expect(summary.totalWeight, 10);
    expect(summary.activeSuppliers, 1);
    expect(locations.map((row) => row.location), ['A town']);
  });
}

AnalyticsFilters _filters({
  String? productId,
  String? supplierType,
  String? town,
}) => AnalyticsFilters(
  from: DateTime(2026, 9, 1),
  to: DateTime(2026, 9, 30),
  productId: productId,
  supplierType: supplierType,
  town: town,
);

Future<void> _insertSupplier(
  Database database,
  String internalId,
  String id,
  String name,
  String type,
  String town,
  bool active, {
  String? companyId,
}) async {
  await database.insert('suppliers', {
    'internal_id': internalId,
    'company_id': companyId,
    'supplier_id': id,
    'normalized_name': name.toLowerCase(),
    'name': name,
    'type': type,
    'town': town,
    'district': 'District',
    'region': 'Region',
    'is_active': active ? 1 : 0,
    'created_at': '2026-01-01T00:00:00',
    'updated_at': '2026-01-01T00:00:00',
    'synchronization_status': 'synced',
  });
}

Future<void> _insertDelivery(
  Database database,
  String id,
  String supplierId,
  String productId,
  String productName,
  String supplierType,
  String recordedAt,
  List<double> weights, {
  String status = 'received',
  String? companyId,
}) async {
  await database.insert('deliveries', {
    'id': id,
    'company_id': companyId,
    'supplier_id': supplierId,
    'product_id': productId,
    'recorded_at': recordedAt,
    'recorded_by_user_id': 'user',
    'status': status,
    'synchronization_status': 'synced',
    'supplier_name': supplierId == 'ALB-000001'
        ? 'Ibrahim Mensah'
        : 'Ama Boateng',
    'product_name': productName,
    'supplier_type': supplierType,
    'created_at': recordedAt,
    'updated_at': recordedAt,
  });
  for (var index = 0; index < weights.length; index++) {
    await database.insert('delivery_bag_weights', {
      'delivery_id': id,
      'company_id': companyId,
      'bag_number': index + 1,
      'weight': weights[index],
    });
  }
}
