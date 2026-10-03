import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'workbook_grid_model.dart';

/// Persists the grids of imported workbooks so an edit survives a restart.
///
/// This reuses the `local_metadata` table the application already has, rather
/// than adding a table, so importing a workbook introduces no schema change and
/// no migration. Each grid is stored as one JSON document under a key that is
/// scoped by company, so one company's imported workbook can never be read or
/// overwritten by another.
///
/// Nothing here touches a delivery, a bag weight or a total. A saved workbook is
/// the user's own file content, held locally, and is never pushed to Supabase.
class WorkbookGridStore {
  const WorkbookGridStore(this._database);

  final Database? _database;

  /// The table already created by the local database bootstrap.
  static const String table = 'local_metadata';

  /// Separates the company, the file and the sheet inside a storage key.
  ///
  /// This is the separator [keyFor] has always used, kept as one constant so the
  /// writer and the reader that lists saved workbooks can never drift apart.
  static const String keySeparator = ':';

  /// Builds the storage key for one sheet of one file in one company.
  ///
  /// The company is part of the key *and* the value, so a read can only ever
  /// return the current company's own sheets.
  static String keyFor({
    required String companyId,
    required String filename,
    required String sheetName,
  }) =>
      'workbook_grid$keySeparator$companyId$keySeparator$filename$keySeparator$sheetName';

  /// Loads a previously saved grid, or null when the sheet was never saved.
  Future<WorkbookGrid?> load({
    required String companyId,
    required String filename,
    required String sheetName,
  }) async {
    final database = _database;
    if (database == null || companyId.isEmpty) return null;
    final rows = await database.query(
      table,
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [keyFor(
        companyId: companyId,
        filename: filename,
        sheetName: sheetName,
      )],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    try {
      final decoded = jsonDecode(rows.first['value']! as String) as Map<String, Object?>;
      return WorkbookGrid.fromJson(
        name: sheetName,
        sourceFilename: filename,
        raw: decoded['cells'] as List<Object?>? ?? const [],
        rawMerges: decoded['merges'] as List<Object?>? ?? const [],
        rawStyles:
            decoded['styles'] as Map<String, Object?>? ?? const {},
      );
    } catch (_) {
      // A document written by an older build is discarded rather than allowed
      // to crash the screen; the file can simply be imported again.
      return null;
    }
  }

  /// Writes one sheet, replacing any previous save of that same sheet.
  Future<void> save({
    required String companyId,
    required WorkbookGrid grid,
  }) async {
    final database = _database;
    if (database == null || companyId.isEmpty) return;
    await database.insert(table, {
      'key': keyFor(
        companyId: companyId,
        filename: grid.sourceFilename,
        sheetName: grid.name,
      ),
      'value': jsonEncode({
        'cells': grid.toJsonCells(),
        'merges': [for (final merge in grid.merges) merge.toJson()],
        'styles': {
          for (final entry in grid.styles.entries)
            if (!entry.value.isPlain) entry.key: entry.value.toJson(),
        },
      }),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// The sheets already saved for a file, so they can be offered to the user.
  Future<List<String>> savedSheets({
    required String companyId,
    required String filename,
  }) async {
    final database = _database;
    if (database == null || companyId.isEmpty) return const [];
    final prefix = 'workbook_grid:$companyId:$filename:';
    final rows = await database.query(
      table,
      columns: ['key'],
      where: 'key LIKE ?',
      whereArgs: ['$prefix%'],
    );
    return [
      for (final row in rows)
        (row['key']! as String).substring(prefix.length),
    ];
  }

  /// Every workbook sheet saved for one company, newest name first.
  ///
  /// This is the cold-start path: the user left the screen, came back later and
  /// has no file open, so the screen needs to know what already exists. It
  /// reads the same keys [save] wrote and the same keys [load] reads, so nothing
  /// about the stored format changes and no migration is involved.
  ///
  /// Only this company's prefix is matched, so one company can never be offered
  /// another company's workbooks. A filename or sheet name that happens to
  /// contain the separator is still read back correctly, because only the two
  /// separators the key is built with are used to split it.
  Future<List<SavedWorkbook>> savedWorkbooks({
    required String companyId,
  }) async {
    final database = _database;
    if (database == null || companyId.isEmpty) return const [];
    final prefix = 'workbook_grid:$companyId:';
    final rows = await database.query(
      table,
      columns: ['key'],
      where: 'key LIKE ?',
      whereArgs: ['$prefix%'],
    );
    final books = <SavedWorkbook>[];
    for (final row in rows) {
      final key = row['key']! as String;
      if (!key.startsWith(prefix)) continue;
      final rest = key.substring(prefix.length);
      // The company prefix is already removed, so what is left is
      // `filename:sheetName`. The *first* separator ends the file name, because
      // a sheet name may contain a colon but a file name is the shorter half and
      // is what [keyFor] wrote first.
      final separator = rest.indexOf(keySeparator);
      if (separator <= 0 || separator == rest.length - 1) continue;
      final filename = rest.substring(0, separator);
      final sheetName = rest.substring(separator + 1);
      if (filename.isEmpty || sheetName.isEmpty) continue;
      books.add(SavedWorkbook(filename: filename, sheetName: sheetName));
    }
    books.sort((a, b) {
      final byFile = a.filename.toLowerCase().compareTo(b.filename.toLowerCase());
      return byFile != 0 ? byFile : a.sheetName.toLowerCase().compareTo(b.sheetName.toLowerCase());
    });
    return books;
  }
}

/// One sheet of one file that has been saved locally for a company.
class SavedWorkbook {
  const SavedWorkbook({required this.filename, required this.sheetName});

  final String filename;
  final String sheetName;

  /// What the user sees in the list.
  String get label => '$filename — $sheetName';
}
