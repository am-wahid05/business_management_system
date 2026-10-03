import 'package:sqflite/sqflite.dart';

import 'spreadsheet_formatting.dart';

/// A merged rectangle of cells, identified by the stable keys of its corners.
///
/// Storing keys rather than grid positions is what keeps a merge attached to
/// the same rows when the grid is sorted or filtered.
class CellMerge {
  const CellMerge({
    required this.anchorRowKey,
    required this.anchorColumn,
    required this.endRowKey,
    required this.endColumn,
  });

  final String anchorRowKey;
  final int anchorColumn;
  final String endRowKey;
  final int endColumn;

  bool get isSingleCell =>
      anchorRowKey == endRowKey && anchorColumn == endColumn;

  @override
  bool operator ==(Object other) =>
      other is CellMerge &&
      other.anchorRowKey == anchorRowKey &&
      other.anchorColumn == anchorColumn &&
      other.endRowKey == endRowKey &&
      other.endColumn == endColumn;

  @override
  int get hashCode =>
      Object.hash(anchorRowKey, anchorColumn, endRowKey, endColumn);
}

/// All presentation state for one company's spreadsheet.
class SpreadsheetState {
  const SpreadsheetState({
    this.formats = const {},
    this.formulas = const {},
    this.merges = const [],
  });

  /// Keyed by `'$rowKey#$column'`, the same key the controller uses.
  final Map<String, CellFormat> formats;

  /// The formula expression for a cell, keyed the same way.
  final Map<String, String> formulas;

  final List<CellMerge> merges;

  static String cellKey(String rowKey, int column) => '$rowKey#$column';

  static const empty = SpreadsheetState();
}

/// Reads and writes the spreadsheet's presentation state.
///
/// This is a local, company-scoped store. It holds formatting, formula
/// expressions and merged ranges, and nothing else: it can never write a
/// delivery, a bag weight or a total, so a formula result can never become
/// official business data.
///
/// Every query is filtered by [companyId]. That is the whole company isolation
/// story here: company_id is part of the key of every table and always part of
/// the WHERE clause, so no query can return or change another company's sheet.
class SpreadsheetStateStore {
  const SpreadsheetStateStore(this._database);

  final Database? _database;

  /// Loads every stored cell, formula and merge for one company.
  Future<SpreadsheetState> load({required String companyId}) async {
    final database = _database;
    if (database == null || companyId.isEmpty) return SpreadsheetState.empty;

    final formats = <String, CellFormat>{};
    for (final row in await database.query(
      'spreadsheet_cells',
      where: 'company_id = ?',
      whereArgs: [companyId],
    )) {
      final key = SpreadsheetState.cellKey(
        row['row_key']! as String,
        (row['column_index']! as num).toInt(),
      );
      formats[key] = CellFormat.fromMap({
        'background': row['background'],
        'text': row['text_color'],
        'bold': (row['is_bold']! as num).toInt() == 1,
        'italic': (row['is_italic']! as num).toInt() == 1,
        'alignment': row['alignment'],
      });
    }

    final formulas = <String, String>{};
    for (final row in await database.query(
      'spreadsheet_formulas',
      where: 'company_id = ?',
      whereArgs: [companyId],
    )) {
      final key = SpreadsheetState.cellKey(
        row['row_key']! as String,
        (row['column_index']! as num).toInt(),
      );
      formulas[key] = row['expression']! as String;
    }

    final merges = <CellMerge>[];
    for (final row in await database.query(
      'spreadsheet_merges',
      where: 'company_id = ?',
      whereArgs: [companyId],
    )) {
      merges.add(
        CellMerge(
          anchorRowKey: row['anchor_row_key']! as String,
          anchorColumn: (row['anchor_column']! as num).toInt(),
          endRowKey: row['end_row_key']! as String,
          endColumn: (row['end_column']! as num).toInt(),
        ),
      );
    }

    return SpreadsheetState(
      formats: Map.unmodifiable(formats),
      formulas: Map.unmodifiable(formulas),
      merges: List.unmodifiable(merges),
    );
  }

  /// Replaces the stored state for one company, in one transaction.
  ///
  /// Only cells that actually carry state are written. A plain cell is absent
  /// from [state] and so is never stored, and the deletes are scoped to this
  /// company, so saving never touches another company's sheet.
  Future<void> save({
    required String companyId,
    required SpreadsheetState state,
  }) async {
    final database = _database;
    if (database == null || companyId.isEmpty) return;

    await database.transaction((transaction) async {
      for (final table in const [
        'spreadsheet_cells',
        'spreadsheet_formulas',
        'spreadsheet_merges',
      ]) {
        await transaction.delete(
          table,
          where: 'company_id = ?',
          whereArgs: [companyId],
        );
      }

      final batch = transaction.batch();
      for (final entry in state.formats.entries) {
        // A plain format is not state, so it is never written.
        if (entry.value.isPlain) continue;
        final parts = _splitKey(entry.key);
        final format = entry.value;
        batch.insert('spreadsheet_cells', {
          'company_id': companyId,
          'row_key': parts.$1,
          'column_index': parts.$2,
          'background': format.background.name,
          'text_color': format.text?.name,
          'is_bold': format.bold ? 1 : 0,
          'is_italic': format.italic ? 1 : 0,
          'alignment': format.alignment.name,
        });
      }
      for (final entry in state.formulas.entries) {
        final parts = _splitKey(entry.key);
        batch.insert('spreadsheet_formulas', {
          'company_id': companyId,
          'row_key': parts.$1,
          'column_index': parts.$2,
          'expression': entry.value,
        });
      }
      for (final merge in state.merges) {
        batch.insert('spreadsheet_merges', {
          'company_id': companyId,
          'anchor_row_key': merge.anchorRowKey,
          'anchor_column': merge.anchorColumn,
          'end_row_key': merge.endRowKey,
          'end_column': merge.endColumn,
        });
      }
      await batch.commit(noResult: true);
    });
  }

  /// Removes presentation state belonging to a row that no longer exists.
  ///
  /// Without this, a deleted row's formatting, formula and merges would linger
  /// as orphans and could reappear on an unrelated row that later reused the key.
  Future<void> deleteRow({
    required String companyId,
    required String rowKey,
  }) async {
    final database = _database;
    if (database == null || companyId.isEmpty) return;
    await database.transaction((transaction) async {
      await transaction.delete(
        'spreadsheet_cells',
        where: 'company_id = ? AND row_key = ?',
        whereArgs: [companyId, rowKey],
      );
      await transaction.delete(
        'spreadsheet_formulas',
        where: 'company_id = ? AND row_key = ?',
        whereArgs: [companyId, rowKey],
      );
      // A merge is dropped when either of its end rows disappears.
      await transaction.delete(
        'spreadsheet_merges',
        where: 'company_id = ? AND (anchor_row_key = ? OR end_row_key = ?)',
        whereArgs: [companyId, rowKey, rowKey],
      );
    });
  }

  /// Splits a `'$rowKey#$column'` key back into its parts.
  static (String, int) _splitKey(String key) {
    final hash = key.lastIndexOf('#');
    if (hash < 0) return (key, 0);
    return (key.substring(0, hash), int.tryParse(key.substring(hash + 1)) ?? 0);
  }
}