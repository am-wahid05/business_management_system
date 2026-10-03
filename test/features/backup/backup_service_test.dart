import 'dart:convert';
import 'dart:io';

import 'package:flutter_application_2/features/backup/backup_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database database;
  late Directory directory;

  setUp(() async {
    sqfliteFfiInit();
    directory = await Directory.systemTemp.createTemp('albnc-backup-test-');
    database = await databaseFactoryFfi.openDatabase(':memory:', options: OpenDatabaseOptions(
      version: 1,
      onCreate: (database, version) async {
        await database.execute('CREATE TABLE products (id TEXT PRIMARY KEY, name TEXT NOT NULL, is_active INTEGER NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL)');
        await database.execute('CREATE TABLE deliveries (id TEXT PRIMARY KEY, supplier_id TEXT NOT NULL, product_id TEXT NOT NULL, recorded_at TEXT NOT NULL, recorded_by_user_id TEXT NOT NULL, status TEXT NOT NULL, synchronization_status TEXT NOT NULL, supplier_name TEXT NOT NULL, product_name TEXT NOT NULL, supplier_type TEXT NOT NULL, synchronization_error TEXT, sync_attempts INTEGER NOT NULL DEFAULT 0, last_sync_attempt_at TEXT, synced_at TEXT, created_at TEXT NOT NULL, updated_at TEXT NOT NULL)');
        await database.execute('CREATE TABLE delivery_bag_weights (delivery_id TEXT NOT NULL, bag_number INTEGER NOT NULL, weight REAL NOT NULL, PRIMARY KEY (delivery_id, bag_number))');
        await database.execute('CREATE TABLE import_logs (id TEXT PRIMARY KEY, filename TEXT NOT NULL, imported_at TEXT NOT NULL, imported_by_user_id TEXT NOT NULL, rows_total INTEGER NOT NULL, rows_imported INTEGER NOT NULL, rows_skipped INTEGER NOT NULL, rows_failed INTEGER NOT NULL)');
        await database.execute('CREATE TABLE users (id TEXT PRIMARY KEY, username TEXT NOT NULL, password_hash TEXT NOT NULL, password_salt TEXT NOT NULL)');
      },
    ));
    await database.insert('products', {'id': 'p1', 'name': 'Cashew', 'is_active': 1, 'created_at': '2026-01-01', 'updated_at': '2026-01-01'});
    await database.insert('users', {'id': 'u1', 'username': 'admin', 'password_hash': 'secret-hash', 'password_salt': 'secret-salt'});
  });

  tearDown(() async {
    await database.close();
    await directory.delete(recursive: true);
  });

  test('backs up business data without password secrets and restores safely', () async {
    final service = BackupService(database, directoryProvider: () async => directory);
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
  });

  test('rejects an invalid backup before changing data', () async {
    final invalid = File('${directory.path}${Platform.pathSeparator}invalid.json')..writeAsStringSync('{"format":"unknown"}');
    final service = BackupService(database, directoryProvider: () async => directory);

    await expectLater(service.restoreBackup(invalid), throwsFormatException);
    expect(await database.query('products'), hasLength(1));
  });
}