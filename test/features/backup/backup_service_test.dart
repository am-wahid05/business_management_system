import 'dart:convert';
import 'dart:io';

import 'package:flutter_application_2/features/backup/backup_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database database;
  late Directory directory;
  late Database companyDatabase; // company-scoped composite-key DB
  late Directory companyDirectory;

  setUp(() async {
    sqfliteFfiInit();
    directory = await Directory.systemTemp.createTemp('albnc-backup-test-');
    database = await databaseFactoryFfi.openDatabase(
      '${directory.path}${Platform.pathSeparator}business.sqlite',
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (database, version) async {
          await database.execute(
            'CREATE TABLE products (id TEXT PRIMARY KEY, name TEXT NOT NULL, is_active INTEGER NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL)',
          );
          await database.execute(
            'CREATE TABLE deliveries (id TEXT PRIMARY KEY, supplier_id TEXT NOT NULL, product_id TEXT NOT NULL, recorded_at TEXT NOT NULL, recorded_by_user_id TEXT NOT NULL, status TEXT NOT NULL, synchronization_status TEXT NOT NULL, supplier_name TEXT NOT NULL, product_name TEXT NOT NULL, supplier_type TEXT NOT NULL, synchronization_error TEXT, sync_attempts INTEGER NOT NULL DEFAULT 0, last_sync_attempt_at TEXT, synced_at TEXT, created_at TEXT NOT NULL, updated_at TEXT NOT NULL)',
          );
          await database.execute(
            'CREATE TABLE delivery_bag_weights (delivery_id TEXT NOT NULL, bag_number INTEGER NOT NULL, weight REAL NOT NULL, PRIMARY KEY (delivery_id, bag_number))',
          );
          await database.execute(
            'CREATE TABLE import_logs (id TEXT PRIMARY KEY, filename TEXT NOT NULL, imported_at TEXT NOT NULL, imported_by_user_id TEXT NOT NULL, rows_total INTEGER NOT NULL, rows_imported INTEGER NOT NULL, rows_skipped INTEGER NOT NULL, rows_failed INTEGER NOT NULL)',
          );
          await database.execute(
            'CREATE TABLE users (id TEXT PRIMARY KEY, username TEXT NOT NULL, password_hash TEXT NOT NULL, password_salt TEXT NOT NULL)',
          );
        },
      ),
    );
    await database.insert('products', {
      'id': 'p1',
      'name': 'Cashew',
      'is_active': 1,
      'created_at': '2026-01-01',
      'updated_at': '2026-01-01',
    });
    await database.insert('users', {
      'id': 'u1',
      'username': 'admin',
      'password_hash': 'secret-hash',
      'password_salt': 'secret-salt',
    });
  });

  tearDown(() async {
    await database.close();
    await directory.delete(recursive: true);
  });

  test(
    'backs up business data without password secrets and restores safely',
    () async {
      final service = BackupService(
        database,
        directoryProvider: () async => directory,
      );
      final backup = await service.createBackup(filename: 'business.json');
      final text = await backup.readAsString();
      expect(text, contains('Cashew'));
      expect(text, isNot(contains('secret-hash')));
      expect(text, isNot(contains('secret-salt')));
      expect(jsonDecode(text)['tables'], isNot(contains('users')));

      await database.delete('products');
      final safetyBackup = await service.restoreBackup(backup);

      expect(await database.query('products'), hasLength(1));
      expect(await database.query('users'), hasLength(1));
      expect(await safetyBackup.exists(), isTrue);
      expect(safetyBackup.path, isNot(backup.path));
    },
  );

  test('rejects an invalid backup before changing data', () async {
    final invalid = File(
      '${directory.path}${Platform.pathSeparator}invalid.json',
    )..writeAsStringSync('{"format":"unknown"}');
    final service = BackupService(
      database,
      directoryProvider: () async => directory,
    );

    await expectLater(service.restoreBackup(invalid), throwsFormatException);
    expect(await database.query('products'), hasLength(1));
  });

  group('company-scoped backup restores', () {
    setUp(() async {
      sqfliteFfiInit();
      companyDirectory = Directory(directory.path + '/company-escoped');
      if (await companyDirectory.exists()) {
        await companyDirectory.delete(recursive: true);
      }
      await companyDirectory.create(recursive: true);
      companyDatabase = await databaseFactoryFfi.openDatabase(
        '${companyDirectory.path}${Platform.pathSeparator}company.sqlite',
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (database, version) async {
            await database.execute(
              'CREATE TABLE products (company_id TEXT NOT NULL, id TEXT NOT NULL, name TEXT NOT NULL, is_active INTEGER NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL, PRIMARY KEY (company_id, id))',
            );
            await database.execute(
              'CREATE TABLE deliveries (company_id TEXT NOT NULL, id TEXT NOT NULL, supplier_id TEXT NOT NULL, product_id TEXT NOT NULL, recorded_at TEXT NOT NULL, recorded_by_user_id TEXT NOT NULL, status TEXT NOT NULL, synchronization_status TEXT NOT NULL, supplier_name TEXT NOT NULL, product_name TEXT NOT NULL, supplier_type TEXT NOT NULL, synchronization_error TEXT, sync_attempts INTEGER NOT NULL DEFAULT 0, last_sync_attempt_at TEXT, synced_at TEXT, created_at TEXT NOT NULL, updated_at TEXT NOT NULL, PRIMARY KEY (company_id, id))',
            );
            await database.execute(
              'CREATE TABLE delivery_bag_weights (company_id TEXT NOT NULL, delivery_id TEXT NOT NULL, bag_number INTEGER NOT NULL, weight REAL NOT NULL, PRIMARY KEY (company_id, delivery_id, bag_number))',
            );
            await database.execute(
              'CREATE TABLE import_logs (company_id TEXT NOT NULL, id TEXT NOT NULL, filename TEXT NOT NULL, imported_at TEXT NOT NULL, imported_by_user_id TEXT NOT NULL, rows_total INTEGER NOT NULL, rows_imported INTEGER NOT NULL, rows_skipped INTEGER NOT NULL, rows_failed INTEGER NOT NULL, PRIMARY KEY (company_id, id))',
            );
          },
        ),
      );
      await companyDatabase.insert(
        'products',
        {
          'company_id': 'company-A',
          'id': 'p1',
          'name': 'Cashew',
          'is_active': 1,
          'created_at': '2026-01-01T00:00:00Z',
          'updated_at': '2026-01-01T00:00:00Z',
        },
      );
      await companyDatabase.insert(
        'deliveries',
        {
          'company_id': 'company-A',
          'id': 'd1',
          'supplier_id': 'supplier-a',
          'product_id': 'p1',
          'recorded_at': '2026-01-01T00:00:00Z',
          'recorded_by_user_id': 'user-a',
          'status': 'completed',
          'synchronization_status': 'synced',
          'supplier_name': 'A - Kofi Mensah',
          'product_name': 'Cashew',
          'supplier_type': 'local',
          'sync_attempts': 0,
          'created_at': '2026-01-01T00:00:00Z',
          'updated_at': '2026-01-01T00:00:00Z',
        },
      );
      await companyDatabase.insert(
        'products',
        {
          'company_id': 'company-B',
          'id': 'p1',
          'name': 'Cocoa',
          'is_active': 1,
          'created_at': '2026-01-01T00:00:00Z',
          'updated_at': '2026-01-01T00:00:00Z',
        },
      );
      await companyDatabase.insert(
        'deliveries',
        {
          'company_id': 'company-B',
          'id': 'd1',
          'supplier_id': 'supplier-b',
          'product_id': 'p1',
          'recorded_at': '2026-01-01T00:00:00Z',
          'recorded_by_user_id': 'user-b',
          'status': 'completed',
          'synchronization_status': 'synced',
          'supplier_name': 'B - Kwame Boateng',
          'product_name': 'Cocoa',
          'supplier_type': 'local',
          'sync_attempts': 0,
          'created_at': '2026-01-01T00:00:00Z',
          'updated_at': '2026-01-01T00:00:00Z',
        },
      );
    });

    tearDown(() async {
      await companyDatabase.close();
      if (await companyDirectory.exists()) {
        await companyDirectory.delete(recursive: true);
      }
    });

    test(
      'rejects restoring a backup that contains Company B records when Company A is active',
      () async {
        final service = BackupService(
          companyDatabase,
          directoryProvider: () async => companyDirectory,
          companyIdProvider: () => 'company-A',
        );
        final crossCompanyBackup = {
          'format': 'albnc-business-backup',
          'version': 1,
          'created_at': '2026-01-01T00:00:00Z',
          'tables': {
            'products': [
              {
                'company_id': 'company-A',
                'id': 'p1',
                'name': 'Cashew',
                'is_active': 1,
              },
              {
                'company_id': 'company-B',
                'id': 'p1',
                'name': 'Cocoa',
                'is_active': 1,
              },
            ],
            'deliveries': [
              {
                'company_id': 'company-A',
                'id': 'd1',
                'supplier_name': 'A - Kofi Mensah',
                'product_name': 'Cashew',
                'status': 'completed',
                'synchronization_status': 'synced',
              },
              {
                'company_id': 'company-B',
                'id': 'd1',
                'supplier_name': 'B - Kwame Boateng',
                'product_name': 'Cocoa',
                'status': 'completed',
                'synchronization_status': 'synced',
              },
            ],
            'delivery_bag_weights': [
              {
                'company_id': 'company-A',
                'delivery_id': 'd1',
                'bag_number': 1,
                'weight': 100.0,
              },
            ],
            'import_logs': [],
            'receipt_sends': [],
          },
        };
        final backupFile = File(
          companyDirectory.path + '/cross-company.json',
        )..writeAsStringSync(jsonEncode(crossCompanyBackup));
        final productsBefore = await companyDatabase.query('products');
        final deliveriesBefore = await companyDatabase.query('deliveries');
        await expectLater(
          service.restoreBackup(backupFile),
          throwsFormatException,
        );
        expect(await companyDatabase.query('products'), productsBefore);
        expect(await companyDatabase.query('deliveries'), deliveriesBefore);
      },
    );

    test('restores a Company A-only backup when Company A is active', () async {
      final service = BackupService(
        companyDatabase,
        directoryProvider: () async => companyDirectory,
        companyIdProvider: () => 'company-A',
      );

      final backup = await service.createBackup(filename: 'company-a.json');
      await companyDatabase.delete(
        'products',
        where: 'company_id = ?',
        whereArgs: ['company-A'],
      );
      await companyDatabase.delete(
        'deliveries',
        where: 'company_id = ?',
        whereArgs: ['company-A'],
      );

      final restored = await service.restoreBackup(backup);
      expect(await companyDatabase.query(
        'products',
        where: 'company_id = ?',
        whereArgs: ['company-A'],
      ), hasLength(1));
      expect(await companyDatabase.query(
        'deliveries',
        where: 'company_id = ?',
        whereArgs: ['company-A'],
      ), hasLength(1));
      expect(await companyDatabase.query(
        'products',
        where: 'company_id = ?',
        whereArgs: ['company-B'],
      ), hasLength(1));
      expect(await restored.exists(), isTrue);
    });
  });
}
