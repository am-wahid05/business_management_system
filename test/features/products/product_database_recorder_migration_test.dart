import 'dart:io';

import 'package:flutter_application_2/features/products/product_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test('v12 to v13 keeps legacy rows and allows NULL recorder IDs', () async {
    sqfliteFfiInit();
    final directory = await Directory.systemTemp.createTemp(
      'recorded-by-migration-',
    );
    final databasePath = '${directory.path}${Platform.pathSeparator}legacy.db';
    Database? database;
    try {
      database = await databaseFactoryFfi.openDatabase(
        databasePath,
        options: OpenDatabaseOptions(
          version: 12,
          onCreate: (database, version) async {
            await database.execute('''
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
                PRIMARY KEY (delivery_id, bag_number),
                FOREIGN KEY (delivery_id) REFERENCES deliveries(id) ON DELETE CASCADE
              )
            ''');
            await database.insert('deliveries', {
              'id': 'legacy-delivery',
              'supplier_id': 'supplier-1',
              'product_id': 'cashew',
              'recorded_at': '2020-01-01T12:00:00.000',
              'recorded_by_user_id': 'local-secretary',
              'company_id': 'company-a',
              'status': 'received',
              'synchronization_status': 'synced',
              'supplier_name': 'Legacy supplier',
              'product_name': 'Cashew',
              'supplier_type': 'farmer',
              'created_at': '2020-01-01T12:00:00.000',
              'updated_at': '2020-01-01T12:00:00.000',
            });
            await database.insert('delivery_bag_weights', {
              'delivery_id': 'legacy-delivery',
              'company_id': 'company-a',
              'bag_number': 1,
              'weight': 50,
            });
          },
        ),
      );
      await database.close();
      database = await ProductDatabase.open(databasePath: databasePath);

      final deliveries = await database.query('deliveries');
      final weights = await database.query('delivery_bag_weights');
      final deliveryColumns = await database.rawQuery(
        'PRAGMA table_info(deliveries)',
      );
      final weightColumns = await database.rawQuery(
        'PRAGMA table_info(delivery_bag_weights)',
      );

      expect(deliveries, hasLength(1));
      expect(deliveries.single['recorded_by_user_id'], 'local-secretary');
      expect(
        deliveryColumns.singleWhere(
          (column) => column['name'] == 'recorded_by_user_id',
        )['notnull'],
        0,
      );
      expect(weights, hasLength(1));
      expect(weights.single['weight'], 50);
      expect(weights.single['recorded_by_user_id'], isNull);
      expect(
        weightColumns.any((column) => column['name'] == 'recorded_by_user_id'),
        isTrue,
      );
      expect(await database.rawQuery('PRAGMA foreign_key_check'), isEmpty);

      await database.update(
        'deliveries',
        {'recorded_by_user_id': null},
        where: 'id = ?',
        whereArgs: ['legacy-delivery'],
      );
      expect(
        (await database.query('deliveries')).single['recorded_by_user_id'],
        isNull,
      );
    } finally {
      await database?.close();
      await directory.delete(recursive: true);
    }
  });
}
