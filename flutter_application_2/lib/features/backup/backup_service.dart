import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class BackupService {
  BackupService(
    this.database, {
    this.companyIdProvider,
    Future<Directory> Function()? directoryProvider,
    DateTime Function()? now,
  }) : _directoryProvider = directoryProvider ?? _defaultDirectory,
       _now = now ?? DateTime.now;

  final Database database;
  final String? Function()? companyIdProvider;
  final Future<Directory> Function() _directoryProvider;
  final DateTime Function() _now;

  static const _businessTables = [
    'products',
    'suppliers',
    'deliveries',
    'delivery_bag_weights',
    'import_logs',
    'receipt_sends',
  ];
  static const _optionalBusinessTables = {'suppliers', 'receipt_sends'};

  Future<File> createBackup({String? filename}) async {
    if (companyIdProvider != null && companyIdProvider!() == null) {
      throw StateError('Select an active company before creating a backup.');
    }
    final tables = <String, List<Map<String, Object?>>>{};
    for (final table in _businessTables) {
      if (!await _tableExists(database, table)) {
        if (_optionalBusinessTables.contains(table)) {
          tables[table] = const [];
          continue;
        }
        throw StateError('Required local table $table is missing.');
      }
      tables[table] = await database.query(
        table,
        where: companyIdProvider == null ? null : 'company_id IS ?',
        whereArgs: companyIdProvider == null ? null : [companyIdProvider!()],
      );
    }
    final archive = <String, Object?>{
      'format': 'albnc-business-backup',
      'version': 1,
      'created_at': _now().toUtc().toIso8601String(),
      'tables': tables,
    };
    final directory = await _directoryProvider();
    await directory.create(recursive: true);
    final file = File(
      path.join(
        directory.path,
        filename ?? 'ALBNC_Backup_${_fileDate(_now())}.json',
      ),
    );
    return file.writeAsString(jsonEncode(archive), flush: true);
  }

  Future<File> restoreBackup(File backupFile) async {
    final activeCompanyId = companyIdProvider?.call();
    if (companyIdProvider != null && activeCompanyId == null) {
      throw StateError('Select an active company before restoring a backup.');
    }
    final contents = await backupFile.readAsString();
    final decoded = jsonDecode(contents);
    if (decoded is! Map<String, dynamic> ||
        decoded['format'] != 'albnc-business-backup' ||
        decoded['version'] != 1) {
      throw const FormatException(
        'This is not a supported ALBNC business backup',
      );
    }
    final rawTables = decoded['tables'];
    if (rawTables is! Map<String, dynamic>) {
      throw const FormatException('Backup tables are missing');
    }
    final tables = <String, List<Map<String, Object?>>>{};
    for (final table in _businessTables) {
      final rawRows = rawTables[table];
      if (rawRows is! List &&
          table != 'suppliers' &&
          table != 'receipt_sends') {
        throw FormatException('Backup table is missing: $table');
      }
      tables[table] = (rawRows as List? ?? const [])
          .map((row) => Map<String, Object?>.from(row as Map))
          .toList();
      if (!await _tableExists(database, table) && tables[table]!.isNotEmpty) {
        throw FormatException(
          'This database is missing the $table table required by the backup.',
        );
      }
    }
    if (companyIdProvider != null &&
        tables.values
            .expand((rows) => rows)
            .any((row) => row['company_id'] != activeCompanyId)) {
      throw const FormatException(
        'This backup contains unassigned records or records from a different company. Review and assign them explicitly before restoring.',
      );
    }

    final safetyBackup = await createBackup(
      filename: 'ALBNC_PreRestore_${_fileDate(_now())}.json',
    );
    await database.transaction((transaction) async {
      for (final table in [
        'receipt_sends',
        'delivery_bag_weights',
        'deliveries',
        'import_logs',
        'suppliers',
        'products',
      ]) {
        if (!await _tableExists(transaction, table)) continue;
        if ((table == 'suppliers' || table == 'receipt_sends') &&
            rawTables[table] is! List)
          continue;
        await transaction.delete(
          table,
          where: companyIdProvider == null ? null : 'company_id IS ?',
          whereArgs: companyIdProvider == null ? null : [activeCompanyId],
        );
      }
      for (final table in [
        'suppliers',
        'products',
        'deliveries',
        'delivery_bag_weights',
        'receipt_sends',
        'import_logs',
      ]) {
        if (!await _tableExists(transaction, table)) continue;
        if ((table == 'suppliers' || table == 'receipt_sends') &&
            rawTables[table] is! List)
          continue;
        for (final row in tables[table]!) {
          await transaction.insert(table, row);
        }
      }
    });
    return safetyBackup;
  }

  static String _fileDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}_${date.hour.toString().padLeft(2, '0')}${date.minute.toString().padLeft(2, '0')}${date.second.toString().padLeft(2, '0')}${date.millisecond.toString().padLeft(3, '0')}';

  static Future<Directory> _defaultDirectory() async =>
      await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();

  static Future<bool> _tableExists(
    DatabaseExecutor executor,
    String table,
  ) async {
    final rows = await executor.rawQuery(
      "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1",
      [table],
    );
    return rows.isNotEmpty;
  }
}
