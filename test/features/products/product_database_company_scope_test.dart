import 'dart:convert';
import 'dart:io';

import 'package:flutter_application_2/domain/models/delivery.dart';
import 'package:flutter_application_2/domain/models/product.dart';
import 'package:flutter_application_2/domain/models/supplier.dart';
import 'package:flutter_application_2/features/products/product_database.dart';
import 'package:flutter_application_2/features/receiving/delivery_repository.dart';
import 'package:flutter_application_2/features/sync/supabase_delivery_store.dart';
import 'package:flutter_application_2/features/sync/sync_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  late Directory directory;
  late Database database;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('company-delivery-keys-');
    database = await ProductDatabase.open(
      databasePath: '${directory.path}${Platform.pathSeparator}app.db',
      databaseFactoryOverride: databaseFactoryFfi,
    );
  });

  tearDown(() async {
    await database.close();
    await directory.delete(recursive: true);
  });

  DeliveryRepository repositoryFor(String companyId) => DeliveryRepository(
    database,
    companyIdProvider: () => companyId,
    userIdProvider: () => 'user-$companyId',
  );

  test('same delivery ID and bag numbers coexist per company', () async {
    await repositoryFor('company-a').save(
      _delivery('DUPLICATE-001', 'company-a', [11]),
    );
    await repositoryFor('company-b').save(
      _delivery('DUPLICATE-001', 'company-b', [22]),
    );

    final rows = await database.query(
      'deliveries',
      where: 'id = ?',
      whereArgs: ['DUPLICATE-001'],
      orderBy: 'company_id',
    );
    final weights = await database.query(
      'delivery_bag_weights',
      where: 'delivery_id = ? AND bag_number = ?',
      whereArgs: ['DUPLICATE-001', 1],
      orderBy: 'company_id',
    );

    expect(rows.map((row) => row['company_id']), ['company-a', 'company-b']);
    expect(weights.map((row) => row['weight']), [11.0, 22.0]);
    expect(weights.map((row) => row['company_id']), ['company-a', 'company-b']);
    expect(
      (await repositoryFor('company-a').findById('DUPLICATE-001'))?.totalWeight,
      11,
    );
    expect(
      (await repositoryFor('company-b').findById('DUPLICATE-001'))?.totalWeight,
      22,
    );
  });

  test('company-scoped update, bag delete, and delivery delete stay isolated',
      () async {
    await repositoryFor('company-a').save(
      _delivery('DUPLICATE-001', 'company-a', [11]),
    );
    await repositoryFor('company-b').save(
      _delivery('DUPLICATE-001', 'company-b', [22]),
    );

    await repositoryFor('company-a').updateWeights('DUPLICATE-001', [33]);
    expect(
      (await repositoryFor('company-a').findById('DUPLICATE-001'))?.totalWeight,
      33,
    );
    expect(
      (await repositoryFor('company-b').findById('DUPLICATE-001'))?.totalWeight,
      22,
    );

    await database.delete(
      'delivery_bag_weights',
      where: 'company_id = ? AND delivery_id = ? AND bag_number = ?',
      whereArgs: ['company-a', 'DUPLICATE-001', 1],
    );
    expect(
      await database.query(
        'delivery_bag_weights',
        where: 'company_id = ? AND delivery_id = ?',
        whereArgs: ['company-a', 'DUPLICATE-001'],
      ),
      isEmpty,
    );
    expect(
      (await repositoryFor('company-b').findById('DUPLICATE-001'))?.totalWeight,
      22,
    );

    await database.delete(
      'deliveries',
      where: 'company_id = ? AND id = ?',
      whereArgs: ['company-a', 'DUPLICATE-001'],
    );
    expect(await repositoryFor('company-a').findById('DUPLICATE-001'), isNull);
    expect(
      (await repositoryFor('company-b').findById('DUPLICATE-001'))?.totalWeight,
      22,
    );
    expect(
      await database.query(
        'delivery_bag_weights',
        where: 'company_id = ? AND delivery_id = ?',
        whereArgs: ['company-b', 'DUPLICATE-001'],
      ),
      hasLength(1),
    );
  });

  test('composite foreign key rejects A bag weight under B delivery scope',
      () async {
    await repositoryFor('company-a').save(
      _delivery('DUPLICATE-001', 'company-a', [11]),
    );

    await expectLater(
      database.insert('delivery_bag_weights', {
        'company_id': 'company-b',
        'delivery_id': 'DUPLICATE-001',
        'bag_number': 2,
        'weight': 99,
      }),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('sync download does not replace another company duplicate ID', () async {
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-publishable-key',
      httpClient: MockClient((request) async {
        final table = request.url.pathSegments.last;
        final companyId = request.url.queryParameters['company_id']
            ?.replaceFirst('eq.', '');
        final records = _remoteRows[table]?[companyId] ?? const [];
        return http.Response(
          jsonEncode(records),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    final store = SupabaseDeliveryStore(
      client,
      localDatabase: database,
      userId: () => 'user-company-a',
      isAdmin: () => true,
    );

    await store.downloadCompany(
      scope: const SyncScope(companyId: 'company-a', isCompanyScoped: true),
    );
    await store.downloadCompany(
      scope: const SyncScope(companyId: 'company-b', isCompanyScoped: true),
    );

    final deliveries = await database.query(
      'deliveries',
      where: 'id = ?',
      whereArgs: ['DUPLICATE-001'],
      orderBy: 'company_id',
    );
    final weights = await database.query(
      'delivery_bag_weights',
      where: 'delivery_id = ? AND bag_number = ?',
      whereArgs: ['DUPLICATE-001', 1],
      orderBy: 'company_id',
    );
    expect(deliveries.map((row) => row['company_id']), [
      'company-a',
      'company-b',
    ]);
    expect(weights.map((row) => row['weight']), [11.0, 22.0]);
    expect(weights.map((row) => row['company_id']), ['company-a', 'company-b']);

    await client.dispose();
  });

  test('v20 migration preserves tenant keys and archives mismatched legacy weights',
      () async {
    final legacyPath =
        '${directory.path}${Platform.pathSeparator}legacy-v20.db';
    final legacy = await databaseFactoryFfi.openDatabase(
      legacyPath,
      options: OpenDatabaseOptions(
        version: 20,
        onCreate: (database, version) async {
          await database.execute(_legacyDeliveriesTable);
          await database.execute(_legacyBagWeightsTable);
          await database.insert('deliveries', _legacyDeliveryRow);
          await database.insert('delivery_bag_weights', {
            'delivery_id': 'DUPLICATE-001',
            'company_id': 'company-a',
            'bag_number': 1,
            'weight': 11,
          });
          await database.insert('delivery_bag_weights', {
            'delivery_id': 'DUPLICATE-001',
            'company_id': 'company-b',
            'bag_number': 2,
            'weight': 99,
          });
        },
      ),
    );
    await legacy.close();

    final upgraded = await ProductDatabase.open(
      databasePath: legacyPath,
      databaseFactoryOverride: databaseFactoryFfi,
    );
    addTearDown(upgraded.close);

    final delivery = (await upgraded.query('deliveries')).single;
    final activeWeight = (await upgraded.query('delivery_bag_weights')).single;
    final orphanWeight =
        (await upgraded.query('delivery_bag_weights_legacy_orphans')).single;
    final deliveryColumns = await upgraded.rawQuery(
      'PRAGMA table_info(deliveries)',
    );
    final weightColumns = await upgraded.rawQuery(
      'PRAGMA table_info(delivery_bag_weights)',
    );
    final foreignKeys = await upgraded.rawQuery(
      'PRAGMA foreign_key_list(delivery_bag_weights)',
    );

    expect(delivery['company_id'], 'company-a');
    expect(activeWeight['company_id'], 'company-a');
    expect(activeWeight['weight'], 11);
    expect(orphanWeight['company_id'], 'company-b');
    expect(orphanWeight['weight'], 99);
    expect(
      deliveryColumns.singleWhere((row) => row['name'] == 'company_id')['pk'],
      1,
    );
    expect(
      deliveryColumns.singleWhere((row) => row['name'] == 'id')['pk'],
      2,
    );
    expect(
      weightColumns.singleWhere((row) => row['name'] == 'company_id')['pk'],
      1,
    );
    expect(
      weightColumns.singleWhere((row) => row['name'] == 'delivery_id')['pk'],
      2,
    );
    expect(
      weightColumns.singleWhere((row) => row['name'] == 'bag_number')['pk'],
      3,
    );
    expect(
      foreignKeys.map((row) => '${row['from']}:${row['to']}').toSet(),
      {'company_id:company_id', 'delivery_id:id'},
    );
    expect(await upgraded.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });
}

Delivery _delivery(String id, String companyId, List<double> weights) {
  return Delivery(
    id: id,
    supplier: Supplier(
      id: 'supplier-$companyId',
      companyId: companyId,
      name: 'Supplier $companyId',
      type: SupplierType.farmer,
      town: 'Town $companyId',
      district: 'District $companyId',
      region: 'Region',
    ),
    product: Product(
      id: 'product-$companyId',
      name: 'Product $companyId',
      companyId: companyId,
    ),
    recordedAt: DateTime(2026, 10, 7),
    bagWeights: weights,
    recordedByUserId: 'user-$companyId',
    companyId: companyId,
  );
}

const Map<String, Map<String, List<Map<String, dynamic>>>> _remoteRows = {
  'suppliers': {
    'company-a': [
      {
        'supplier_id': 'supplier-company-a',
        'normalized_name': 'supplier company a',
        'name': 'Supplier A',
        'type': 'farmer',
        'is_active': true,
        'town': 'Town A',
        'district': 'District A',
        'region': 'Region',
        'created_at': '2026-10-01T00:00:00Z',
        'updated_at': '2026-10-01T00:00:00Z',
      },
    ],
    'company-b': [
      {
        'supplier_id': 'supplier-company-b',
        'normalized_name': 'supplier company b',
        'name': 'Supplier B',
        'type': 'farmer',
        'is_active': true,
        'town': 'Town B',
        'district': 'District B',
        'region': 'Region',
        'created_at': '2026-10-01T00:00:00Z',
        'updated_at': '2026-10-01T00:00:00Z',
      },
    ],
  },
  'products': {
    'company-a': [
      {
        'id': 'cashew',
        'name': 'Cashew',
        'is_active': true,
        'created_at': '2026-10-01T00:00:00Z',
        'updated_at': '2026-10-01T00:00:00Z',
      },
    ],
    'company-b': [
      {
        'id': 'cocoa',
        'name': 'Cocoa',
        'is_active': true,
        'created_at': '2026-10-01T00:00:00Z',
        'updated_at': '2026-10-01T00:00:00Z',
      },
    ],
  },
  'deliveries': {
    'company-a': [
      {
        'id': 'DUPLICATE-001',
        'supplier_id': 'supplier-company-a',
        'product_id': 'cashew',
        'recorded_at': '2026-10-01T00:00:00Z',
        'recorded_by_user_id': 'user-company-a',
        'status': 'received',
        'supplier_name': 'Supplier A',
        'supplier_type': 'farmer',
        'product_name': 'Cashew',
        'record_type': 'individual',
        'created_at': '2026-10-01T00:00:00Z',
        'updated_at': '2026-10-01T00:00:00Z',
      },
    ],
    'company-b': [
      {
        'id': 'DUPLICATE-001',
        'supplier_id': 'supplier-company-b',
        'product_id': 'cocoa',
        'recorded_at': '2026-10-02T00:00:00Z',
        'recorded_by_user_id': 'user-company-b',
        'status': 'received',
        'supplier_name': 'Supplier B',
        'supplier_type': 'farmer',
        'product_name': 'Cocoa',
        'record_type': 'individual',
        'created_at': '2026-10-02T00:00:00Z',
        'updated_at': '2026-10-02T00:00:00Z',
      },
    ],
  },
  'delivery_bag_weights': {
    'company-a': [
      {
        'delivery_id': 'DUPLICATE-001',
        'bag_number': 1,
        'weight': 11,
        'recorded_by_user_id': 'user-company-a',
      },
    ],
    'company-b': [
      {
        'delivery_id': 'DUPLICATE-001',
        'bag_number': 1,
        'weight': 22,
        'recorded_by_user_id': 'user-company-b',
      },
    ],
  },
};

const _legacyDeliveriesTable = '''
  CREATE TABLE deliveries (
    id TEXT PRIMARY KEY,
    supplier_id TEXT NOT NULL,
    product_id TEXT NOT NULL,
    recorded_at TEXT NOT NULL,
    recorded_by_user_id TEXT NOT NULL,
    company_id TEXT,
    status TEXT NOT NULL,
    synchronization_status TEXT NOT NULL,
    supplier_internal_id TEXT,
    supplier_name TEXT NOT NULL,
    product_name TEXT NOT NULL,
    supplier_type TEXT NOT NULL,
    synchronization_error TEXT,
    sync_attempts INTEGER NOT NULL DEFAULT 0,
    last_sync_attempt_at TEXT,
    synced_at TEXT,
    record_type TEXT NOT NULL DEFAULT 'individual',
    total_weight REAL,
    bag_count INTEGER,
    notes TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
  )
''';

const _legacyBagWeightsTable = '''
  CREATE TABLE delivery_bag_weights (
    delivery_id TEXT NOT NULL,
    company_id TEXT,
    bag_number INTEGER NOT NULL,
    weight REAL NOT NULL,
    PRIMARY KEY (delivery_id, bag_number),
    FOREIGN KEY (delivery_id) REFERENCES deliveries(id) ON DELETE CASCADE
  )
''';

const _legacyDeliveryRow = {
  'id': 'DUPLICATE-001',
  'supplier_id': 'supplier-legacy',
  'product_id': 'cashew',
  'recorded_at': '2020-01-01T12:00:00.000',
  'recorded_by_user_id': 'legacy-user',
  'company_id': 'company-a',
  'status': 'received',
  'synchronization_status': 'synced',
  'supplier_internal_id': 'legacy-internal',
  'supplier_name': 'Legacy supplier',
  'product_name': 'Cashew',
  'supplier_type': 'farmer',
  'synchronization_error': null,
  'sync_attempts': 0,
  'last_sync_attempt_at': null,
  'synced_at': '2020-01-01T12:00:00.000',
  'record_type': 'individual',
  'total_weight': 11,
  'bag_count': 1,
  'notes': null,
  'created_at': '2020-01-01T12:00:00.000',
  'updated_at': '2020-01-01T12:00:00.000',
};
