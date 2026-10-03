import 'package:flutter_application_2/features/receiving/delivery_repository.dart';
import 'package:flutter_application_2/features/receiving/receiving_service.dart';
import 'package:flutter_application_2/features/spreadsheet/spreadsheet_clipboard.dart';
import 'package:flutter_application_2/features/spreadsheet/spreadsheet_controller.dart';
import 'package:flutter_application_2/features/spreadsheet/spreadsheet_formatting.dart';
import 'package:flutter_application_2/features/spreadsheet/spreadsheet_grid_adapter.dart';
import 'package:flutter_application_2/features/spreadsheet/spreadsheet_row.dart';
import 'package:flutter_application_2/features/spreadsheet/spreadsheet_service.dart';
import 'package:flutter_application_2/features/spreadsheet/spreadsheet_state_store.dart';
import 'package:flutter_application_2/features/suppliers/supplier_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// A controller over an in-memory sheet.
///
/// The adapter only reads and writes cells, so the real repositories are still
/// used; this simply gives them somewhere to run.
Future<SpreadsheetController> controllerOver() async {
  sqfliteFfiInit();
  final database = await databaseFactoryFfi.openDatabase(
    ':memory:',
    options: OpenDatabaseOptions(
      version: 1,
      onCreate: (db, _) async {
        await db.execute(
          'CREATE TABLE local_metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
        );
      },
    ),
  );
  return SpreadsheetController(
    SpreadsheetService(
      deliveryRepository: DeliveryRepository(database),
      receivingService: ReceivingService(
        database: database,
        supplierRepository: SupplierRepository(database: database),
      ),
    ),
    stateStore: SpreadsheetStateStore(database),
  );
}

SpreadsheetRow delivery({
  String date = '28/09/2026',
  String supplier = 'ABC',
  String product = 'Cocoa',
  String weights = '50,48,52,49',
}) => SpreadsheetRow.draft()
  ..date = date
  ..supplierName = supplier
  ..productName = product
  ..weights = weights;

void main() {
  group('SpreadsheetGridAdapter', () {
    late SpreadsheetController controller;

    setUp(() async {
      controller = await controllerOver();
    });

    SpreadsheetGridAdapter adapterWith(List<SpreadsheetRow> rows) {
      controller.addImportedRows(rows);
      return SpreadsheetGridAdapter(controller);
    }

    test('projects controller rows into grid cells', () {
      final grid = adapterWith([
        delivery(),
        delivery(supplier: 'DEF', product: 'Shea Nuts'),
      ]).build();

      expect(grid.rowCount, 2);
      expect(grid.cellAt(0, 0).text, '28/09/2026');
      expect(grid.cellAt(0, 1).text, 'ABC');
      expect(grid.cellAt(0, 2).text, 'Cocoa');
      expect(grid.cellAt(0, 3).text, '50,48,52,49');
      expect(grid.cellAt(1, 1).text, 'DEF');
      expect(grid.cellAt(1, 2).text, 'Shea Nuts');
    });

    test('the column count comes from the controller, not from here', () {
      final adapter = adapterWith([delivery()]);
      expect(adapter.columnCount, SpreadsheetController.gridColumns.length);
      expect(adapter.build().columnCount, adapter.columnCount);
    });

    // The grid must never invent a header row: row 0 is the first record.
    test('no header row is injected above the first record', () {
      final grid = adapterWith([delivery()]).build();
      expect(grid.cellAt(0, 0).text, '28/09/2026');
      expect(grid.cellAt(0, 0).text, isNot('Date'));
      expect(grid.cellAt(0, 1).text, isNot('Supplier'));
      expect(grid.cellAt(0, 2).text, isNot('Product'));
    });

    test('a cell edit routes back through the controller', () {
      final adapter = adapterWith([delivery()]);
      adapter.setCell(0, 1, 'New Supplier');

      expect(controller.rows.first.supplierName, 'New Supplier');
      // The grid is rebuilt from the controller, so there is no second copy of
      // the data that could drift.
      expect(adapter.build().cellAt(0, 1).text, 'New Supplier');
    });

    test('an edit marks the row changed so Save has something to write', () {
      final adapter = adapterWith([delivery()]);
      expect(controller.hasChanges, isTrue);

      adapter.setCell(0, 2, 'Cashew');

      expect(controller.rows.first.productName, 'Cashew');
      expect(controller.hasChanges, isTrue);
    });

    test('an out-of-range edit is ignored rather than throwing', () {
      final adapter = adapterWith([delivery()]);
      adapter.setCell(99, 0, 'nope');
      adapter.setCell(0, 99, 'nope');
      expect(controller.rows.first.date, '28/09/2026');
    });

    // A bag-weight list is not a single number, so the cell keeps the exact text
    // the user typed rather than being collapsed into the 199 kg total.
    test('a bag weight list keeps its text exactly', () {
      final grid = adapterWith([delivery()]).build();
      expect(grid.cellAt(0, 3).text, '50,48,52,49');
    });

    test('a supplier name is never turned into a number', () {
      final grid = adapterWith([delivery(supplier: 'ABC 12')]).build();
      expect(grid.cellAt(0, 1).text, 'ABC 12');
      expect(grid.cellAt(0, 1).number, isNull);
    });

    test('a formula on a cell is carried through as a formula', () {
      final adapter = adapterWith([delivery()]);
      controller.setFormula(controller.rows.first, 3, '=SUM(A1:A2)');
      expect(adapter.build().cellAt(0, 3).isFormula, isTrue);
    });

    test('a formatted cell reaches the grid as a style', () {
      final adapter = adapterWith([delivery()]);
      controller.formatRange(
        const CellRange.single(0, 0),
        (current) => const CellFormat(bold: true, italic: true),
      );
      final style = adapter.build().styleAt(0, 0);
      expect(style, isNotNull);
      expect(style!.bold, isTrue);
      expect(style.italic, isTrue);
    });

    test('an added draft row appears as a new grid row', () {
      final adapter = adapterWith([delivery()]);
      final before = adapter.build().rowCount;

      controller.addDraft();

      expect(adapter.build().rowCount, greaterThan(before));
    });

    test('a removed row is hidden only when Show removed is off', () {
      adapterWith([delivery(), delivery(supplier: 'DEF')]);
      controller.removeDraft(controller.rows.first);

      // On by default, the removed row is still drawn...
      expect(SpreadsheetGridAdapter(controller).build().rowCount, 2);
      // ...and turning it off hides the row without deleting it.
      expect(
        SpreadsheetGridAdapter(controller, showRemoved: false).build().rowCount,
        1,
      );
      expect(controller.rows.length, 2);
    });

    test('a search narrows the visible rows without deleting any', () {
      final adapter = adapterWith([
        delivery(supplier: 'Cocoa Co'),
        delivery(supplier: 'Shea Grower'),
      ]);
      final total = controller.rows.length;

      controller.searchFor('Shea');

      expect(adapter.build().rowCount, lessThan(total));
      expect(controller.rows.length, total);
      controller.clearFilters();
      expect(adapter.build().rowCount, total);
    });
  });
}
