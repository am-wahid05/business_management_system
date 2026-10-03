import 'package:flutter_application_2/features/spreadsheet/spreadsheet_formatting.dart';
import 'package:flutter_application_2/features/spreadsheet/spreadsheet_merges.dart';
import 'package:flutter_application_2/features/spreadsheet/spreadsheet_state_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Creates the three presentation tables, mirroring the production schema.
Future<void> _createTables(Database db) async {
  await db.execute('''
    CREATE TABLE spreadsheet_cells (
      company_id TEXT NOT NULL, row_key TEXT NOT NULL,
      column_index INTEGER NOT NULL, background TEXT NOT NULL DEFAULT 'none',
      text_color TEXT, is_bold INTEGER NOT NULL DEFAULT 0,
      is_italic INTEGER NOT NULL DEFAULT 0, alignment TEXT NOT NULL DEFAULT 'left',
      PRIMARY KEY (company_id, row_key, column_index)
    )
  ''');
  await db.execute('''
    CREATE TABLE spreadsheet_formulas (
      company_id TEXT NOT NULL, row_key TEXT NOT NULL,
      column_index INTEGER NOT NULL, expression TEXT NOT NULL,
      PRIMARY KEY (company_id, row_key, column_index)
    )
  ''');
  await db.execute('''
    CREATE TABLE spreadsheet_merges (
      company_id TEXT NOT NULL, anchor_row_key TEXT NOT NULL,
      anchor_column INTEGER NOT NULL, end_row_key TEXT NOT NULL,
      end_column INTEGER NOT NULL,
      PRIMARY KEY (company_id, anchor_row_key, anchor_column)
    )
  ''');
}

/// Merged cells must be saved permanently, must reject ambiguous overlaps, and
/// must stay with their rows rather than their visual position.
void main() {
  late Database database;
  late SpreadsheetStateStore store;

  const keys = ['r1', 'r2', 'r3'];

  setUp(() async {
    sqfliteFfiInit();
    database = await databaseFactoryFfi.openDatabase(
      ':memory:',
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) => _createTables(db),
      ),
    );
    store = SpreadsheetStateStore(database);
  });

  tearDown(() => database.close());

  Future<void> saveMerges(
    String company,
    MergeManager manager,
  ) => store.save(
    companyId: company,
    state: SpreadsheetState(merges: manager.merges),
  );

  group('merge rules', () {
    test('a single cell is not a merge', () {
      final manager = MergeManager(const []);
      final result = manager.merge(
        rowKeys: keys,
        startRow: 0,
        startColumn: 0,
        endRow: 0,
        endColumn: 0,
      );
      expect(result.isSuccess, isFalse);
      expect(result.failure, MergeFailure.singleCell);
      expect(manager.merges, isEmpty);
    });

    test('two horizontal cells merge', () {
      final manager = MergeManager(const []);
      final result = manager.merge(
        rowKeys: keys,
        startRow: 0,
        startColumn: 0,
        endRow: 0,
        endColumn: 1,
      );
      expect(result.isSuccess, isTrue);
      expect(manager.merges.single.anchorRowKey, 'r1');
      expect(manager.merges.single.anchorColumn, 0);
      expect(manager.merges.single.endColumn, 1);
    });

    test('two vertical cells merge', () {
      final manager = MergeManager(const []);
      final result = manager.merge(
        rowKeys: keys,
        startRow: 0,
        startColumn: 0,
        endRow: 1,
        endColumn: 0,
      );
      expect(result.isSuccess, isTrue);
      expect(manager.merges.single.endRowKey, 'r2');
    });

    test('a rectangular range merges', () {
      final manager = MergeManager(const []);
      final result = manager.merge(
        rowKeys: keys,
        startRow: 0,
        startColumn: 0,
        endRow: 2,
        endColumn: 2,
      );
      expect(result.isSuccess, isTrue);
      expect(manager.merges.single.endRowKey, 'r3');
      expect(manager.merges.single.endColumn, 2);
    });

    test('a selection made backwards merges the same range', () {
      final manager = MergeManager(const []);
      final result = manager.merge(
        rowKeys: keys,
        startRow: 2,
        startColumn: 2,
        endRow: 0,
        endColumn: 0,
      );
      expect(result.isSuccess, isTrue);
      expect(manager.merges.single.anchorRowKey, 'r1');
      expect(manager.merges.single.endRowKey, 'r3');
    });

    test('a partially overlapping merge is rejected', () {
      final manager = MergeManager(const []);
      manager.merge(
        rowKeys: keys,
        startRow: 0,
        startColumn: 0,
        endRow: 1,
        endColumn: 1,
      );
      final result = manager.merge(
        rowKeys: keys,
        startRow: 1,
        startColumn: 1,
        endRow: 2,
        endColumn: 2,
      );
      expect(result.isSuccess, isFalse);
      expect(result.failure, MergeFailure.overlapsExisting);
      // The original merge is untouched.
      expect(manager.merges.length, 1);
    });

    test('a merge that would contain another is rejected', () {
      final manager = MergeManager(const []);
      // An existing two-column merge on the middle row.
      manager.merge(
        rowKeys: keys,
        startRow: 1,
        startColumn: 0,
        endRow: 1,
        endColumn: 1,
      );
      // A larger rectangle that would swallow it entirely.
      final result = manager.merge(
        rowKeys: keys,
        startRow: 0,
        startColumn: 0,
        endRow: 2,
        endColumn: 2,
      );
      expect(result.isSuccess, isFalse);
      expect(result.failure, MergeFailure.overlapsExisting);
      // The original merge is kept as it was.
      expect(manager.merges.length, 1);
      expect(manager.merges.single.anchorRowKey, 'r2');
    });

    test('re-merging the same range is rejected', () {
      final manager = MergeManager(const []);
      manager.merge(
        rowKeys: keys,
        startRow: 0,
        startColumn: 0,
        endRow: 0,
        endColumn: 1,
      );
      final again = manager.merge(
        rowKeys: keys,
        startRow: 0,
        startColumn: 0,
        endRow: 0,
        endColumn: 1,
      );
      expect(again.failure, MergeFailure.overlapsExisting);
      expect(manager.merges.length, 1);
    });

    test('disjoint merges are both allowed', () {
      final manager = MergeManager(const []);
      manager.merge(
        rowKeys: keys,
        startRow: 0,
        startColumn: 0,
        endRow: 0,
        endColumn: 1,
      );
      manager.merge(
        rowKeys: keys,
        startRow: 2,
        startColumn: 0,
        endRow: 2,
        endColumn: 1,
      );
      expect(manager.merges.length, 2);
    });

    test('unmerge removes only the range it anchors', () {
      final manager = MergeManager(const []);
      manager.merge(
        rowKeys: keys,
        startRow: 0,
        startColumn: 0,
        endRow: 0,
        endColumn: 1,
      );
      manager.merge(
        rowKeys: keys,
        startRow: 2,
        startColumn: 0,
        endRow: 2,
        endColumn: 1,
      );
      final result = manager.unmerge(rowKeys: keys, row: 0, column: 0);
      expect(result.isSuccess, isTrue);
      expect(manager.merges.length, 1);
      expect(manager.merges.single.anchorRowKey, 'r3');
    });

    test('unmerging cells that are not merged is refused', () {
      final manager = MergeManager(const []);
      final result = manager.unmerge(rowKeys: keys, row: 0, column: 0);
      expect(result.isSuccess, isFalse);
      expect(result.failure, MergeFailure.notMerged);
    });

    test('a covered cell is reported as not editable', () {
      final manager = MergeManager(const []);
      manager.merge(
        rowKeys: keys,
        startRow: 0,
        startColumn: 0,
        endRow: 0,
        endColumn: 2,
      );
      // The anchor is editable.
      expect(manager.isCoveredByMerge(keys, 0, 0), isFalse);
      // The cells it spans are covered.
      expect(manager.isCoveredByMerge(keys, 0, 1), isTrue);
      expect(manager.isCoveredByMerge(keys, 0, 2), isTrue);
      // A cell outside is untouched.
      expect(manager.isCoveredByMerge(keys, 1, 1), isFalse);
    });
  });

  group('merges persist', () {
    test('a horizontal merge survives saving and reloading', () async {
      final manager = MergeManager(const []);
      manager.merge(
        rowKeys: keys,
        startRow: 0,
        startColumn: 0,
        endRow: 0,
        endColumn: 1,
      );
      await saveMerges('company-a', manager);

      final restored = await store.load(companyId: 'company-a');
      expect(restored.merges.length, 1);
      expect(restored.merges.single.anchorRowKey, 'r1');
      expect(restored.merges.single.endColumn, 1);
    });

    test('a vertical merge survives saving and reloading', () async {
      final manager = MergeManager(const []);
      manager.merge(
        rowKeys: keys,
        startRow: 0,
        startColumn: 2,
        endRow: 1,
        endColumn: 2,
      );
      await saveMerges('company-a', manager);

      final restored = await store.load(companyId: 'company-a');
      expect(restored.merges.single.endRowKey, 'r2');
    });

    test('a rectangular merge survives saving and reloading', () async {
      final manager = MergeManager(const []);
      manager.merge(
        rowKeys: keys,
        startRow: 0,
        startColumn: 0,
        endRow: 2,
        endColumn: 3,
      );
      await saveMerges('company-a', manager);

      final restored = await store.load(companyId: 'company-a');
      expect(restored.merges.single.endRowKey, 'r3');
      expect(restored.merges.single.endColumn, 3);
    });

    test('an unmerge survives saving and reloading', () async {
      final manager = MergeManager(const []);
      manager.merge(
        rowKeys: keys,
        startRow: 0,
        startColumn: 0,
        endRow: 0,
        endColumn: 1,
      );
      await saveMerges('company-a', manager);

      // Reopen, unmerge, save again.
      final reopened = MergeManager(
        (await store.load(companyId: 'company-a')).merges,
      );
      expect(reopened.unmerge(rowKeys: keys, row: 0, column: 0).isSuccess, isTrue);
      await saveMerges('company-a', reopened);

      final restored = await store.load(companyId: 'company-a');
      expect(restored.merges, isEmpty);
    });

    test('a merge stays with its rows when the visual order changes', () async {
      final manager = MergeManager(const []);
      manager.merge(
        rowKeys: keys,
        startRow: 0,
        startColumn: 0,
        endRow: 1,
        endColumn: 0,
      );
      await saveMerges('company-a', manager);

      final restored = await store.load(companyId: 'company-a');
      // The grid is re-sorted so 'r2' is now shown first.
      final bounds = MergeManager.bounds(
        restored.merges.single,
        const ['r2', 'r1', 'r3'],
      );
      // Still the same two rows, now occupying visual rows 0 and 1.
      expect(bounds, (0, 0, 1, 0));
      expect(restored.merges.single.anchorRowKey, 'r1');
      expect(restored.merges.single.endRowKey, 'r2');
    });

    test('merges are company isolated', () async {
      final a = MergeManager(const []);
      a.merge(
        rowKeys: keys,
        startRow: 0,
        startColumn: 0,
        endRow: 0,
        endColumn: 1,
      );
      await saveMerges('company-a', a);

      // Company B sees none of it.
      expect((await store.load(companyId: 'company-b')).merges, isEmpty);

      // And Company B saving does not remove Company A's merge.
      await store.save(
        companyId: 'company-b',
        state: const SpreadsheetState(),
      );
      expect((await store.load(companyId: 'company-a')).merges.length, 1);
    });

    test('deleting a row removes its merges so none are orphaned', () async {
      final manager = MergeManager(const []);
      manager.merge(
        rowKeys: keys,
        startRow: 0,
        startColumn: 0,
        endRow: 1,
        endColumn: 0,
      );
      await saveMerges('company-a', manager);

      await store.deleteRow(companyId: 'company-a', rowKey: 'r2');
      expect((await store.load(companyId: 'company-a')).merges, isEmpty);
    });

    test('formatting inside a merged range persists with it', () async {
      final manager = MergeManager(const []);
      manager.merge(
        rowKeys: keys,
        startRow: 0,
        startColumn: 0,
        endRow: 0,
        endColumn: 2,
      );
      await store.save(
        companyId: 'company-a',
        state: SpreadsheetState(
          formats: {
            SpreadsheetState.cellKey(
              'r1',
              0,
            ): const CellFormat(background: CellColor.yellow),
          },
          merges: manager.merges,
        ),
      );

      final restored = await store.load(companyId: 'company-a');
      expect(restored.merges.length, 1);
      expect(
        restored.formats[SpreadsheetState.cellKey('r1', 0)]?.background,
        CellColor.yellow,
      );
    });

    test('a formula alongside a merge is unaffected by it', () async {
      final manager = MergeManager(const []);
      manager.merge(
        rowKeys: keys,
        startRow: 0,
        startColumn: 0,
        endRow: 0,
        endColumn: 1,
      );
      await store.save(
        companyId: 'company-a',
        state: SpreadsheetState(
          formulas: {
            SpreadsheetState.cellKey('r3', 3): '=SUM(D1:D3)',
          },
          merges: manager.merges,
        ),
      );

      final restored = await store.load(companyId: 'company-a');
      // The merge and the formula are independent, so neither corrupts the other.
      expect(restored.merges.length, 1);
      expect(
        restored.formulas[SpreadsheetState.cellKey('r3', 3)],
        '=SUM(D1:D3)',
      );
    });
  });
}
