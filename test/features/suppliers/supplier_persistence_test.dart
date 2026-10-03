import 'dart:io';

import 'package:flutter_application_2/domain/models/delivery.dart';
import 'package:flutter_application_2/domain/models/product.dart';
import 'package:flutter_application_2/domain/models/supplier.dart';
import 'package:flutter_application_2/features/products/product_database.dart';
import 'package:flutter_application_2/features/receiving/receiving_service.dart';
import 'package:flutter_application_2/features/suppliers/supplier_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test(
    'supplier create survives repository reload and preserves all fields',
    () async {
      final directory = await Directory.systemTemp.createTemp('supplier-db-');
      var database = await _openDatabase(directory);
      addTearDown(() async {
        await database.close();
        await directory.delete(recursive: true);
      });
      String? companyIdProvider() => 'company-a';
      final repository = SupplierRepository(
        database: database,
        companyIdProvider: companyIdProvider,
        now: () => DateTime(2026, 9, 30, 9),
      );
      await repository.initialize();

      final farmer = await repository.create(
        name: 'Ama Farmer',
        type: SupplierType.farmer,
        phone: '0240000000',
        town: 'Techiman',
        district: 'Techiman Municipal',
        region: 'Bono East',
        notes: 'Cashew grower',
      );
      final aggregator = await repository.create(
        name: 'Bono Aggregators',
        type: SupplierType.aggregator,
        phone: '0201234567',
        town: 'Kumasi',
        district: 'Kumasi Metropolitan',
        region: 'Ashanti',
        notes: 'Warehouse contact',
      );
      await repository.setActive(aggregator.id, false);

      await database.close();
      database = await _openDatabase(directory);
      final reloaded = SupplierRepository(
        database: database,
        companyIdProvider: companyIdProvider,
      );
      await reloaded.initialize();

      expect(reloaded.suppliers, hasLength(2));
      final savedFarmer = reloaded.findById(farmer.id)!;
      expect(savedFarmer.id, farmer.id);
      expect(savedFarmer.companyId, 'company-a');
      expect(savedFarmer.type, SupplierType.farmer);
      expect(savedFarmer.phone, isNotEmpty);
      expect(savedFarmer.town, 'Techiman');
      expect(savedFarmer.district, 'Techiman Municipal');
      expect(savedFarmer.region, 'Bono East');
      expect(savedFarmer.notes, 'Cashew grower');
      expect(savedFarmer.isActive, isTrue);
      expect(savedFarmer.createdAt, DateTime(2026, 9, 30, 9));
      expect(savedFarmer.updatedAt, DateTime(2026, 9, 30, 9));

      final savedAggregator = reloaded.findById(aggregator.id)!;
      expect(savedAggregator.type, SupplierType.aggregator);
      expect(savedAggregator.phone, isNotEmpty);
      expect(savedAggregator.town, 'Kumasi');
      expect(savedAggregator.district, 'Kumasi Metropolitan');
      expect(savedAggregator.region, 'Ashanti');
      expect(savedAggregator.notes, 'Warehouse contact');
      expect(savedAggregator.isActive, isFalse);
    },
  );

  test('duplicate normalized names are rejected inside one company', () async {
    final directory = await Directory.systemTemp.createTemp('supplier-db-');
    final database = await _openDatabase(directory);
    addTearDown(() async {
      await database.close();
      await directory.delete(recursive: true);
    });
    final repository = SupplierRepository(
      database: database,
      companyIdProvider: () => 'company-a',
    );
    await repository.initialize();
    await repository.create(
      name: '  Kofi   Farms ',
      type: SupplierType.farmer,
      phone: '',
      town: '',
      district: '',
      region: '',
      notes: '',
    );

    await expectLater(
      repository.create(
        name: 'kofi farms',
        type: SupplierType.aggregator,
        phone: '',
        town: '',
        district: '',
        region: '',
        notes: '',
      ),
      throwsStateError,
    );
  });

  test(
    'company reads, edits, and deactivation stay inside the active tenant',
    () async {
      final directory = await Directory.systemTemp.createTemp('supplier-db-');
      final database = await _openDatabase(directory);
      addTearDown(() async {
        await database.close();
        await directory.delete(recursive: true);
      });
      final companyA = SupplierRepository(
        database: database,
        companyIdProvider: () => 'company-a',
      );
      final companyB = SupplierRepository(
        database: database,
        companyIdProvider: () => 'company-b',
      );
      await companyA.initialize();
      await companyB.initialize();

      await companyA.create(
        name: 'Company A Seed',
        type: SupplierType.farmer,
        phone: '',
        town: '',
        district: '',
        region: '',
        notes: '',
      );
      final supplierA = await companyA.create(
        name: 'Company A Supplier',
        type: SupplierType.aggregator,
        phone: '',
        town: '',
        district: '',
        region: '',
        notes: '',
      );
      await companyB.create(
        name: 'Company B Supplier',
        type: SupplierType.farmer,
        phone: '',
        town: '',
        district: '',
        region: '',
        notes: '',
      );
      await companyB.initialize();

      expect(companyA.findById(supplierA.id), isNotNull);
      expect(companyB.findById(supplierA.id), isNull);
      await expectLater(
        companyB.update(supplierA.copyWith(name: 'Changed by B')),
        throwsStateError,
      );
      await expectLater(
        companyB.setActive(supplierA.id, false),
        throwsStateError,
      );

      await companyA.initialize();
      expect(companyA.findById(supplierA.id)!.name, 'Company A Supplier');
      expect(companyA.findById(supplierA.id)!.isActive, isTrue);
    },
  );

  test(
    'legacy receiving import creation persists and reuses the scoped supplier',
    () async {
      final directory = await Directory.systemTemp.createTemp('supplier-db-');
      final database = await _openDatabase(directory);
      addTearDown(() async {
        await database.close();
        await directory.delete(recursive: true);
      });
      String? companyIdProvider() => 'company-a';
      final supplierRepository = SupplierRepository(
        database: database,
        companyIdProvider: companyIdProvider,
      );
      await supplierRepository.initialize();
      final receivingService = ReceivingService(
        database: database,
        supplierRepository: supplierRepository,
        companyIdProvider: companyIdProvider,
        userIdProvider: () => 'user-a',
      );

      final first = await _saveHistoricalDelivery(
        receivingService,
        id: 'history-1',
        name: '  Imported   Supplier ',
        type: SupplierType.aggregator,
      );
      final second = await _saveHistoricalDelivery(
        receivingService,
        id: 'history-2',
        name: 'imported supplier',
        type: SupplierType.farmer,
      );

      expect(second.supplier.id, first.supplier.id);
      expect(second.supplier.type, SupplierType.aggregator);
      final rows = await database.query(
        'suppliers',
        where: 'company_id = ?',
        whereArgs: ['company-a'],
      );
      expect(rows, hasLength(1));
      expect(rows.single['normalized_name'], 'imported supplier');
      expect(rows.single['type'], SupplierType.aggregator.name);
      expect(await database.rawQuery('SELECT * FROM deliveries'), hasLength(2));
    },
  );

  test('version 16 migration preserves unassigned records and scopes supplier keys', () async {
    final directory = await Directory.systemTemp.createTemp(
      'supplier-migration-',
    );
    final databasePath = path.join(directory.path, 'legacy.db');
    var database = await databaseFactoryFfi.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: 12,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE suppliers (
              internal_id TEXT PRIMARY KEY,
              supplier_id TEXT NOT NULL UNIQUE,
              company_id TEXT,
              normalized_name TEXT NOT NULL,
              name TEXT NOT NULL,
              type TEXT NOT NULL,
              phone TEXT,
              town TEXT NOT NULL DEFAULT '',
              district TEXT NOT NULL DEFAULT '',
              region TEXT NOT NULL DEFAULT '',
              notes TEXT,
              is_active INTEGER NOT NULL DEFAULT 1,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL,
              synchronization_status TEXT NOT NULL DEFAULT 'pendingSync',
              synchronization_error TEXT
            )
          ''');
          await db.insert('suppliers', {
            'internal_id': 'legacy-1',
            'supplier_id': 'ALB-LEGACY-1',
            'company_id': null,
            'normalized_name': 'legacy supplier',
            'name': 'Legacy Supplier',
            'type': 'farmer',
            'town': 'Techiman',
            'district': 'Techiman Municipal',
            'region': 'Bono East',
            'created_at': '2025-01-01T00:00:00.000',
            'updated_at': '2025-01-01T00:00:00.000',
          });
        },
      ),
    );
    await database.close();

    database = await ProductDatabase.open(
      databasePath: databasePath,
      databaseFactoryOverride: databaseFactoryFfi,
    );
    addTearDown(() async {
      await database.close();
      await directory.delete(recursive: true);
    });

    final legacy = (await database.query('suppliers')).single;
    expect(legacy['supplier_id'], 'ALB-LEGACY-1');
    expect(legacy['name'], 'Legacy Supplier');
    expect(legacy['company_id'], isNull);
    await database.insert('suppliers', {
      ...legacy,
      'internal_id': 'company-a:ALB-LEGACY-1',
      'company_id': 'company-a',
    });
    await database.insert('suppliers', {
      ...legacy,
      'internal_id': 'company-b:ALB-LEGACY-1',
      'company_id': 'company-b',
    });

    expect(
      (await database.rawQuery('PRAGMA user_version')).single['user_version'],
      16,
    );
    expect(
      await database.query(
        'suppliers',
        where: 'supplier_id = ?',
        whereArgs: ['ALB-LEGACY-1'],
      ),
      hasLength(3),
    );
  });

  test('version 15 company keys remain intact on startup upgrade', () async {
    final directory = await Directory.systemTemp.createTemp('supplier-v15-');
    final databasePath = path.join(directory.path, 'scoped.db');
    var database = await databaseFactoryFfi.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: 15,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE suppliers (
              internal_id TEXT PRIMARY KEY,
              supplier_id TEXT NOT NULL,
              company_id TEXT,
              normalized_name TEXT NOT NULL,
              name TEXT NOT NULL,
              type TEXT NOT NULL,
              phone TEXT,
              town TEXT NOT NULL DEFAULT '',
              district TEXT NOT NULL DEFAULT '',
              region TEXT NOT NULL DEFAULT '',
              notes TEXT,
              is_active INTEGER NOT NULL DEFAULT 1,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL,
              synchronization_status TEXT NOT NULL DEFAULT 'pendingSync',
              synchronization_error TEXT,
              UNIQUE (company_id, supplier_id),
              UNIQUE (company_id, normalized_name)
            )
          ''');
          await db.insert('suppliers', {
            'internal_id': 'company-a:ALB-1',
            'supplier_id': 'ALB-1',
            'company_id': 'company-a',
            'normalized_name': 'existing supplier',
            'name': 'Existing Supplier',
            'type': 'farmer',
            'created_at': '2025-01-01T00:00:00.000',
            'updated_at': '2025-01-01T00:00:00.000',
          });
        },
      ),
    );
    await database.close();
    database = await ProductDatabase.open(
      databasePath: databasePath,
      databaseFactoryOverride: databaseFactoryFfi,
    );
    addTearDown(() async {
      await database.close();
      await directory.delete(recursive: true);
    });

    expect(
      (await database.rawQuery('PRAGMA user_version')).single['user_version'],
      16,
    );
    expect(
      (await database.query('suppliers')).single['name'],
      'Existing Supplier',
    );
    await database.insert('suppliers', {
      'internal_id': 'company-b:ALB-1',
      'supplier_id': 'ALB-1',
      'company_id': 'company-b',
      'normalized_name': 'existing supplier',
      'name': 'Existing Supplier',
      'type': 'farmer',
      'created_at': '2025-01-01T00:00:00.000',
      'updated_at': '2025-01-01T00:00:00.000',
    });
    await expectLater(
      database.insert('suppliers', {
        'internal_id': 'company-a:duplicate-name',
        'supplier_id': 'ALB-2',
        'company_id': 'company-a',
        'normalized_name': 'existing supplier',
        'name': 'Existing Supplier',
        'type': 'aggregator',
        'created_at': '2025-01-01T00:00:00.000',
        'updated_at': '2025-01-01T00:00:00.000',
      }),
      throwsA(anything),
    );
  });
}

Future<Database> _openDatabase(Directory directory) => ProductDatabase.open(
  databasePath: path.join(directory.path, 'suppliers.db'),
  databaseFactoryOverride: databaseFactoryFfi,
);

Future<Delivery> _saveHistoricalDelivery(
  ReceivingService service, {
  required String id,
  required String name,
  required SupplierType type,
}) async {
  final incomingSupplier = Supplier(
    id: 'excel-supplier-id',
    name: name,
    type: type,
    town: 'Techiman',
    district: 'Techiman Municipal',
    region: 'Bono East',
    companyId: 'company-a',
  );
  final delivery = Delivery(
    id: id,
    supplier: incomingSupplier,
    product: Product.cashew,
    recordedAt: DateTime(2026, 9, 20),
    bagWeights: const [50],
    recordedByUserId: 'user-a',
    companyId: 'company-a',
  );
  return service.saveDelivery(
    supplierId: incomingSupplier.id,
    supplierName: incomingSupplier.name,
    supplierType: incomingSupplier.type,
    town: incomingSupplier.town,
    district: incomingSupplier.district,
    region: incomingSupplier.region,
    delivery: delivery,
  );
}
