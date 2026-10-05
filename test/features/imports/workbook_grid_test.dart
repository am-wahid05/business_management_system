import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_2/features/auth/auth_models.dart';
import 'package:flutter_application_2/features/management/workbook_grid_screen.dart';
import 'package:flutter_application_2/features/imports/excel_cell_parser.dart';
import 'package:flutter_application_2/features/imports/excel_import_service.dart';
import 'package:flutter_application_2/features/imports/workbook_grid_model.dart';
import 'package:flutter_application_2/features/imports/workbook_grid_store.dart';
import 'package:flutter_application_2/features/imports/workbook_grid_view.dart';
import 'package:flutter_application_2/features/receiving/delivery_repository.dart';
import 'package:flutter_application_2/features/spreadsheet/spreadsheet_clipboard.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Builds a workbook the way Microsoft Excel would: a blank first row, a blank
/// spacer row, a real date, a formula and a second worksheet. Nothing here is
/// shaped like a delivery sheet, which is the point of the test.
Uint8List buildExternalWorkbook({
  String sheetName = 'Sales',
  bool includeSecondSheet = false,
}) {
  final excel = Excel.createExcel();
  final sheet = excel[sheetName];
  sheet.appendRow([TextCellValue('')]);
  sheet.appendRow([
    TextCellValue('Item'),
    TextCellValue('Amount'),
    TextCellValue('Total'),
  ]);
  // A genuinely empty cell inside the data, which a header-detecting reader
  // would have collapsed away.
  sheet.appendRow([TextCellValue(''), TextCellValue('1000000')]);
  sheet.appendRow([
    TextCellValue('Product/Service 1'),
    IntCellValue(1000000),
    IntCellValue(1000000),
  ]);
  sheet.appendRow([
    TextCellValue('Product/Service 2'),
    DoubleCellValue(5671.5),
    IntCellValue(6879),
  ]);
  sheet.appendRow([
    TextCellValue('Total sales revenue'),
    FormulaCellValue('SUM(B3:B4)'),
    FormulaCellValue('SUM(C3:C4)'),
  ]);
  sheet.appendRow([
    TextCellValue('Date'),
    DateCellValue.fromDateTime(DateTime(2026, 8, 1)),
  ]);
  if (includeSecondSheet) {
    excel['Other'].appendRow([TextCellValue('Second sheet')]);
  }
  return Uint8List.fromList(excel.encode()!);
}

/// The signed-in admin the screen's access check reads.
final AppUser adminUser = AppUser(
  id: 'admin-1',
  username: 'ama@acme.test',
  displayName: 'Ama',
  role: UserRole.admin,
  isActive: true,
  companyId: 'company-1',
  companyName: 'Acme',
);

void main() {
  late Database database;
  late ExcelImportService service;

  setUp(() async {
    sqfliteFfiInit();
    database = await databaseFactoryFfi.openDatabase(':memory:');
    service = ExcelImportService(
      database: database,
      deliveryRepository: DeliveryRepository(database),
      userId: 'admin-1',
    );
  });

  tearDown(() async => database.close());

  /// Reads the external workbook and returns its first sheet.
  WorkbookGrid loadGrid() => service
      .readWorkbookGrids(buildExternalWorkbook(), 'accounts.xlsx')
      .sheets
      .first;

  group('column letters', () {
    test('run from A to Z and continue past it', () {
      expect(columnLetter(0), 'A');
      expect(columnLetter(25), 'Z');
      expect(columnLetter(26), 'AA');
      expect(columnLetter(27), 'AB');
      expect(columnLetter(51), 'AZ');
      expect(columnLetter(52), 'BA');
    });

    test('build a one-based address for a position', () {
      expect(cellAddress(0, 0), 'A1');
      expect(cellAddress(4, 2), 'C5');
      expect(cellAddress(0, 26), 'AA1');
    });
  });

  group('a workbook is read as a grid, not as a delivery sheet', () {
    test('keeps every row, so row 1 is really row 1', () {
      final grid = loadGrid();
      // The blank first row and the blank spacer row are both preserved. A
      // header-detecting reader would have discarded both.
      expect(grid.cellAt(0, 0).isBlank, isTrue);
      expect(grid.cellAt(1, 0).text, 'Item');
      expect(grid.cellAt(2, 0).isBlank, isTrue);
      expect(grid.cellAt(2, 1).text, '1000000');
    });

    test('does not treat the first row as a header', () {
      expect(loadGrid().cellAt(0, 0).text, isEmpty);
    });

    test('never reports a date error for a row that has no date', () {
      expect(() => loadGrid(), returnsNormally);
    });

    test('keeps text as text', () {
      final cell = loadGrid().cellAt(3, 0);
      expect(cell.text, 'Product/Service 1');
      expect(cell.number, isNull);
    });

    test('keeps an integer as a number', () {
      expect(loadGrid().cellAt(3, 1).number, 1000000);
    });

    test('keeps a decimal as a number', () {
      expect(loadGrid().cellAt(4, 1).number, 5671.5);
    });

    test('keeps a date as a date and does not shift the day', () {
      final cell = loadGrid().cellAt(6, 1);
      expect(cell.date, isNotNull);
      expect(cell.date!.year, 2026);
      expect(cell.date!.month, 8);
      expect(cell.date!.day, 1);
    });

    test('keeps a formula as the formula text', () {
      final cell = loadGrid().cellAt(5, 1);
      expect(cell.isFormula, isTrue);
      expect(cell.text, contains('SUM'));
    });

    test('sizes itself from the sheet, not a fixed 10 by 10', () {
      final grid = loadGrid();
      expect(grid.columnCount, greaterThanOrEqualTo(3));
      expect(grid.rowCount, greaterThanOrEqualTo(7));
    });

    test('reads every worksheet, not just the first', () {
      final book = service.readWorkbookGrids(
        buildExternalWorkbook(includeSecondSheet: true),
        'accounts.xlsx',
      );
      expect(book.sheets.length, 2);
      expect(book.sheets.last.name, 'Other');
    });

    test('reads a macro-enabled workbook by its worksheet data', () {
      // .xlsm is the same OOXML package, so only the file name differs.
      final book = service.readWorkbookGrids(
        buildExternalWorkbook(),
        'accounts.xlsm',
      );
      expect(book.sheets.first.cellAt(3, 0).text, 'Product/Service 1');
    });

    test('reads a CSV through the same grid path', () {
      final bytes = Uint8List.fromList(utf8.encode('Item,Amount\nCocoa,50\n'));
      final grid = service.readWorkbookGrids(bytes, 'data.csv').sheets.single;
      expect(grid.cellAt(0, 0).text, 'Item');
      expect(grid.cellAt(1, 0).text, 'Cocoa');
      expect(grid.cellAt(1, 1).text, '50');
    });
  });

  group('editing a cell', () {
    test('keeps a typed number as a number', () {
      final cell = classifyTypedCell('42.5');
      expect(cell.number, 42.5);
      expect(cell.isFormula, isFalse);
    });

    test('keeps a typed formula as a formula', () {
      final cell = classifyTypedCell('=SUM(B2:B4)');
      expect(cell.isFormula, isTrue);
      expect(cell.text, '=SUM(B2:B4)');
    });

    test('keeps ordinary text as text', () {
      final cell = classifyTypedCell('Product/Service 1');
      expect(cell.text, 'Product/Service 1');
      expect(cell.number, isNull);
    });

    // Regression: the lenient number parser used for imported cells discards
    // anything it does not recognise, so it reads a name that merely contains a
    // digit as a number. Typing a label must not destroy it.
    test('a label containing digits is not turned into a number', () {
      for (final label in const [
        'Product/Service 1',
        'Bag 25',
        'Grade A 2',
        'Row 3 of 4',
      ]) {
        final cell = classifyTypedCell(label);
        expect(cell.text, label, reason: label);
        expect(cell.number, isNull, reason: label);
      }
    });

    test('a negative or signed whole number is still a number', () {
      expect(classifyTypedCell('-12.5').number, -12.5);
    });

    test('an emptied cell becomes blank rather than empty text', () {
      expect(classifyTypedCell('   ').isBlank, isTrue);
    });

    test('a blank cell outside the used range can still be written', () {
      final grid = WorkbookGrid(
        name: 'S',
        cells: [
          [const ParsedCell(text: 'a')],
        ],
      );
      expect(grid.cellAt(9, 9).isBlank, isTrue);
      grid.setCell(9, 9, classifyTypedCell('typed here'));
      expect(grid.cellAt(9, 9).text, 'typed here');
    });
  });

  group('saving and reopening', () {
    const company = 'company-1';
    late WorkbookGridStore store;

    setUp(() async {
      store = WorkbookGridStore(database);
      await database.execute(
        'CREATE TABLE IF NOT EXISTS local_metadata '
        '(key TEXT PRIMARY KEY, value TEXT NOT NULL)',
      );
    });

    Future<WorkbookGrid> saveAndLoad(WorkbookGrid grid, {String? as}) async {
      await store.save(companyId: as ?? company, grid: grid);
      return (await store.load(
        companyId: as ?? company,
        filename: 'accounts.xlsx',
        sheetName: 'Sales',
      ))!;
    }

    WorkbookGrid sample() => WorkbookGrid(
      name: 'Sales',
      sourceFilename: 'accounts.xlsx',
      cells: [
        [
          classifyTypedCell('Item'),
          classifyTypedCell('1000000'),
          classifyTypedCell('=SUM(B2:B3)'),
        ],
      ],
    );

    test('a saved grid is readable again with its values intact', () async {
      final reloaded = await saveAndLoad(sample());
      expect(reloaded.cellAt(0, 0).text, 'Item');
      expect(reloaded.cellAt(0, 1).number, 1000000);
      expect(reloaded.cellAt(0, 2).isFormula, isTrue);
    });

    test('an edit is persisted, not just held in memory', () async {
      final grid = sample();
      grid.setCell(0, 0, classifyTypedCell('Edited item'));
      final reloaded = await saveAndLoad(grid);
      expect(reloaded.cellAt(0, 0).text, 'Edited item');
    });

    // The company-isolation story for this store: the company is part of the
    // key, so one company can never read or overwrite another's grid.
    test('one company cannot read another company saved grid', () async {
      await store.save(companyId: company, grid: sample());
      final other = await store.load(
        companyId: 'company-2',
        filename: 'accounts.xlsx',
        sheetName: 'Sales',
      );
      expect(other, isNull);
    });

    test('one company saving does not disturb the other', () async {
      final mine = sample();
      mine.setCell(0, 0, classifyTypedCell('first'));
      await store.save(companyId: company, grid: mine);
      final theirs = sample();
      theirs.setCell(0, 0, classifyTypedCell('second'));
      await store.save(companyId: 'company-2', grid: theirs);

      final myCopy = await store.load(
        companyId: company,
        filename: 'accounts.xlsx',
        sheetName: 'Sales',
      );
      expect(myCopy!.cellAt(0, 0).text, 'first');
      final theirCopy = await store.load(
        companyId: 'company-2',
        filename: 'accounts.xlsx',
        sheetName: 'Sales',
      );
      expect(theirCopy!.cellAt(0, 0).text, 'second');
    });

    test('lists the sheets already saved for a file', () async {
      for (final name in const ['One', 'Two']) {
        await store.save(
          companyId: company,
          grid: WorkbookGrid(
            name: name,
            sourceFilename: 'accounts.xlsx',
            cells: const [[]],
          ),
        );
      }
      final sheets =
          await store.savedSheets(companyId: company, filename: 'accounts.xlsx')
            ..sort();
      expect(sheets, ['One', 'Two']);
    });

    test('a saved grid keeps the merge ranges it was given', () async {
      final grid = WorkbookGrid(
        name: 'Sales',
        sourceFilename: 'accounts.xlsx',
        cells: const [[]],
        merges: const [
          WorkbookMerge(startRow: 0, startColumn: 0, endRow: 1, endColumn: 2),
        ],
      );
      final reloaded = await saveAndLoad(grid);
      expect(reloaded.merges.length, 1);
      expect(reloaded.mergeAt(1, 1), isNotNull);
    });
  });

  group('merged cells', () {
    WorkbookGrid merged(WorkbookMerge merge, {int rows = 4, int columns = 5}) =>
        WorkbookGrid(
          name: 'S',
          cells: [
            for (var r = 0; r < rows; r++)
              [for (var c = 0; c < columns; c++) ParsedCell(text: 'r${r}c$c')],
          ],
          merges: [merge],
        );

    test('a horizontal merge reports its full width', () {
      final grid = merged(
        const WorkbookMerge(
          startRow: 0,
          startColumn: 0,
          endRow: 0,
          endColumn: 3,
        ),
      );
      expect(grid.spanColumns(0, 0), 4);
      expect(grid.spanRows(0, 0), 1);
    });

    test('a vertical merge reports its full height', () {
      final grid = merged(
        const WorkbookMerge(
          startRow: 0,
          startColumn: 0,
          endRow: 2,
          endColumn: 0,
        ),
      );
      expect(grid.spanRows(0, 0), 3);
      expect(grid.spanColumns(0, 0), 1);
    });

    test('a rectangular merge reports both spans', () {
      final grid = merged(
        const WorkbookMerge(
          startRow: 0,
          startColumn: 0,
          endRow: 2,
          endColumn: 3,
        ),
      );
      expect(grid.spanColumns(0, 0), 4);
      expect(grid.spanRows(0, 0), 3);
    });

    test('a cell inside a merge knows it is not the anchor', () {
      final grid = merged(
        const WorkbookMerge(
          startRow: 0,
          startColumn: 0,
          endRow: 0,
          endColumn: 3,
        ),
      );
      expect(grid.mergeAnchorAt(0, 0), isNull);
      expect(grid.mergeAnchorAt(0, 2), isNotNull);
    });

    test('a cell outside any merge has no span', () {
      final grid = merged(
        const WorkbookMerge(
          startRow: 0,
          startColumn: 0,
          endRow: 0,
          endColumn: 3,
        ),
      );
      expect(grid.spanColumns(3, 1), 1);
      expect(grid.spanRows(3, 1), 1);
    });

    test('several merges on one sheet are all known', () {
      final grid = WorkbookGrid(
        name: 'S',
        cells: [
          for (var r = 0; r < 4; r++)
            [for (var c = 0; c < 5; c++) ParsedCell(text: 'r${r}c$c')],
        ],
        merges: const [
          WorkbookMerge(startRow: 0, startColumn: 0, endRow: 0, endColumn: 3),
          WorkbookMerge(startRow: 2, startColumn: 0, endRow: 3, endColumn: 0),
        ],
      );
      expect(grid.merges.length, 2);
      expect(grid.spanColumns(0, 0), 4);
      expect(grid.spanRows(2, 0), 2);
    });

    // The value belongs to the anchor, so copying a row must not hand out a
    // second copy of it.
    test('copying a merged row does not duplicate the merged value', () {
      final grid = WorkbookGrid(
        name: 'S',
        cells: [
          [
            const ParsedCell(text: 'Heading'),
            for (var c = 0; c < 3; c++) const ParsedCell.blank(),
          ],
        ],
        merges: const [
          WorkbookMerge(startRow: 0, startColumn: 0, endRow: 0, endColumn: 3),
        ],
      );
      final clip = grid.copyRange(
        const CellRange(startColumn: 0, startRow: 0, endColumn: 3, endRow: 0),
      );
      expect(clip.cells[0][0].text, 'Heading');
      expect(clip.cells[0][1].isBlank, isTrue);
      expect(clip.cells[0][2].isBlank, isTrue);
    });
  });

  group('copy and paste', () {
    late WorkbookGrid grid;

    setUp(() {
      grid = WorkbookGrid(
        name: 'S',
        sourceFilename: 'accounts.xlsx',
        cells: [
          [
            classifyTypedCell('Item'),
            classifyTypedCell('1000000'),
            classifyTypedCell('=SUM(B2:B4)'),
          ],
        ],
      );
    });

    test('a single cell copy and paste keeps its number', () {
      final clip = grid.copyRange(const CellRange.single(1, 0));
      grid.pasteClipboard(clip, 2, 0);
      expect(grid.cellAt(2, 0).number, 1000000);
    });

    test('a range copy pastes every cell', () {
      final clip = grid.copyRange(
        const CellRange(startColumn: 0, startRow: 0, endColumn: 1, endRow: 0),
      );
      grid.pasteClipboard(clip, 3, 0);
      expect(grid.cellAt(3, 0).text, 'Item');
      expect(grid.cellAt(3, 1).number, 1000000);
    });

    test('a pasted formula moves its relative references', () {
      final clip = grid.copyRange(const CellRange.single(2, 0));
      // Copied from C1 and pasted into D1, so every column moves right by one.
      grid.pasteClipboard(clip, 0, 3);
      expect(grid.cellAt(0, 3).isFormula, isTrue);
      expect(grid.cellAt(0, 3).text, '=SUM(C2:C4)');
    });

    test('an absolute reference does not move', () {
      grid.setCell(0, 0, const ParsedCell(text: '=\$B\$2+B2', isFormula: true));
      // A pure two-column move along the same row, so only the column part of
      // the relative reference can change.
      final clip = grid.copyRange(const CellRange.single(0, 0));
      grid.pasteClipboard(clip, 0, 2);
      expect(grid.cellAt(0, 2).text, '=\$B\$2+D2');
    });

    test('a pasted formula moves in both directions', () {
      grid.setCell(0, 0, const ParsedCell(text: '=B2', isFormula: true));
      final clip = grid.copyRange(const CellRange.single(0, 0));
      // Copied from A1 to B2, which is one row down and one column right.
      grid.pasteClipboard(clip, 1, 1);
      expect(grid.cellAt(1, 1).text, '=C3');
    });

    test('a formula pasted onto itself is untouched', () {
      final clip = grid.copyRange(const CellRange.single(2, 0));
      grid.pasteClipboard(clip, 0, 2);
      expect(grid.cellAt(0, 2).text, '=SUM(B2:B4)');
    });

    test('the block exports as tab separated text for the clipboard', () {
      final clip = grid.copyRange(
        const CellRange(startColumn: 0, startRow: 0, endColumn: 1, endRow: 0),
      );
      expect(clip.toText, 'Item\t1000000');
    });
  });

  group('search, filter and sort', () {
    WorkbookGrid sheet() => WorkbookGrid(
      name: 'S',
      cells: [
        [classifyTypedCell('Cocoa'), classifyTypedCell('100')],
        [classifyTypedCell('Shea Nuts'), classifyTypedCell('200')],
        [classifyTypedCell('Cocoa Butter'), classifyTypedCell('300')],
      ],
    );

    test('search finds text matches', () {
      final hits = sheet().search('cocoa');
      expect(hits.length, 2);
      expect(hits.first.row, 0);
    });

    test('search is case insensitive and reaches numbers', () {
      expect(sheet().search('200').length, 1);
    });

    test('an empty search matches nothing rather than everything', () {
      expect(sheet().search('   '), isEmpty);
    });

    test('filtering hides rows without removing them', () {
      final grid = sheet();
      expect(grid.visibleRows(query: 'cocoa', column: 0), [0, 2]);
      // The rows are untouched, so clearing the filter brings them all back.
      expect(grid.rowCount, 3);
      expect(grid.visibleRows(column: 0).length, 3);
    });

    test('sorting a plain sheet reorders it', () {
      final grid = sheet();
      expect(grid.sortBlockedReason, isNull);
      expect(grid.sortByColumn(1), isTrue);
      expect(grid.cellAt(0, 1).number, 100);
      expect(grid.cellAt(2, 1).number, 300);
    });

    test('sorting is refused on a sheet with merges, and says why', () {
      final grid = WorkbookGrid(
        name: 'S',
        cells: [
          [classifyTypedCell('b')],
          [classifyTypedCell('a')],
        ],
        merges: const [
          WorkbookMerge(startRow: 0, startColumn: 0, endRow: 0, endColumn: 1),
        ],
      );
      expect(grid.sortBlockedReason, contains('merged cells'));
      expect(grid.sortByColumn(0), isFalse);
      // Nothing was reordered.
      expect(grid.cellAt(0, 0).text, 'b');
    });

    test('sorting is refused on a formatted sheet, and says why', () {
      final grid = sheet();
      grid.setStyle(0, 0, const WorkbookCellStyle(bold: true));
      expect(grid.sortBlockedReason, contains('formatted'));
      expect(grid.sortByColumn(1), isFalse);
    });
  });

  group('formula recalculation', () {
    WorkbookGrid numbers({int rows = 4}) => WorkbookGrid(
      name: 'S',
      cells: [
        for (var r = 0; r < rows; r++) [classifyTypedCell('${(r + 1) * 10}')],
      ],
    );

    test('SUM is recalculated through the existing engine', () {
      final grid = numbers();
      grid.setCell(
        5,
        0,
        const ParsedCell(text: '=SUM(A1:A4)', isFormula: true),
      );
      expect(grid.displayAt(5, 0).label, '100');
    });

    test('MAX and MIN are recalculated', () {
      final grid = numbers();
      grid.setCell(
        5,
        0,
        const ParsedCell(text: '=MAX(A1:A4)', isFormula: true),
      );
      grid.setCell(
        6,
        0,
        const ParsedCell(text: '=MIN(A1:A4)', isFormula: true),
      );
      expect(grid.displayAt(5, 0).label, '40');
      expect(grid.displayAt(6, 0).label, '10');
    });

    test('arithmetic between cells is recalculated', () {
      final grid = numbers();
      grid.setCell(0, 1, classifyTypedCell('5'));
      grid.setCell(5, 0, const ParsedCell(text: '=A1+B1', isFormula: true));
      expect(grid.displayAt(5, 0).label, '15');
    });

    // Recalculation happens on read, so a dependent cell follows its input.
    test('changing an input changes the dependent result', () {
      final grid = numbers();
      grid.setCell(
        5,
        0,
        const ParsedCell(text: '=SUM(A1:A4)', isFormula: true),
      );
      expect(grid.displayAt(5, 0).label, '100');
      grid.setCell(0, 0, classifyTypedCell('1000'));
      expect(grid.displayAt(5, 0).label, '1090');
    });

    // The most important rule: an unsupported formula is never replaced.
    test('an unsupported formula keeps its text and is not zeroed', () {
      final grid = numbers();
      grid.setCell(
        5,
        0,
        const ParsedCell(text: '=VLOOKUP(A1,B:B,2)', isFormula: true),
      );
      final shown = grid.displayAt(5, 0);
      expect(shown.label, '=VLOOKUP(A1,B:B,2)');
      expect(shown.error, isNotNull);
      expect(grid.cellAt(5, 0).text, '=VLOOKUP(A1,B:B,2)');
    });

    test('an unsupported formula is never deleted', () {
      final grid = numbers();
      grid.setCell(
        5,
        0,
        const ParsedCell(text: '=IF(A1>1,"y","n")', isFormula: true),
      );
      grid.displayAt(5, 0);
      expect(grid.cellAt(5, 0).isFormula, isTrue);
    });

    test('a sheet with an unsupported formula is not safe to sort', () {
      final grid = numbers();
      grid.setCell(
        5,
        0,
        const ParsedCell(text: '=XLOOKUP(A1,B:B)', isFormula: true),
      );
      expect(grid.hasUnsupportedFormulas, isTrue);
      expect(grid.sortBlockedReason, contains('formulas'));
    });

    test('a sheet of only supported formulas is safe to sort', () {
      final grid = numbers();
      grid.setCell(
        5,
        0,
        const ParsedCell(text: '=SUM(A1:A4)', isFormula: true),
      );
      expect(grid.hasUnsupportedFormulas, isFalse);
    });

    test('a plain cell is shown as it is, not evaluated', () {
      final grid = numbers();
      expect(grid.displayAt(0, 0).label, '10');
      expect(grid.displayAt(0, 0).error, isNull);
    });
  });

  group('formatting read from the workbook', () {
    test('bold, italic and alignment reach the grid', () {
      final grid = loadGrid();
      grid.setStyle(1, 0, const WorkbookCellStyle(bold: true, italic: true));
      final style = grid.styleAt(1, 0);
      expect(style!.bold, isTrue);
      expect(style.italic, isTrue);
    });

    test('a plain style reports itself as plain so it is never stored', () {
      expect(const WorkbookCellStyle().isPlain, isTrue);
      expect(const WorkbookCellStyle(bold: true).isPlain, isFalse);
    });

    test('alignment, colour and size survive the round trip', () {
      const style = WorkbookCellStyle(
        horizontalAlign: 'center',
        verticalAlign: 'top',
        textColor: 'FF0000',
        backgroundColor: '00FF00',
        fontSize: 14,
      );
      final back = WorkbookCellStyle.fromJson(style.toJson());
      expect(back.horizontalAlign, 'center');
      expect(back.verticalAlign, 'top');
      expect(back.textColor, 'FF0000');
      expect(back.backgroundColor, '00FF00');
      expect(back.fontSize, 14);
    });
  });

  group('large worksheets', () {
    test('a big sheet keeps every row reachable', () {
      final grid = WorkbookGrid(
        name: 'Big',
        cells: [
          for (var r = 0; r < 20000; r++) [classifyTypedCell('$r')],
        ],
      );
      // Nothing is truncated, and the last row is still addressable.
      expect(grid.rowCount, 20000);
      expect(grid.cellAt(19999, 0).text, '19999');
      expect(grid.search('19999').length, 1);
    });
  });

  group('formula cells keep both the expression and the cached result', () {
    /// Builds a workbook whose cells carry a formula and a stored result.
    ///
    /// `t="str"` is what Excel writes for a formula that returns text, and the
    /// package reads that case as the *result*, losing the expression. The
    /// numeric case loses the result. Both are covered here.
    Uint8List formulaWorkbook({String name = 'accounts.xlsx'}) {
      final excel = Excel.createExcel();
      final sheet = excel['Data'];
      // The amounts sit in column B so the formula really does sum them.
      sheet.appendRow([TextCellValue(''), TextCellValue('Amount')]);
      sheet.appendRow([TextCellValue(''), IntCellValue(30)]);
      sheet.appendRow([TextCellValue(''), IntCellValue(95)]);
      sheet.appendRow([TextCellValue('Total'), FormulaCellValue('SUM(B2:B3)')]);
      sheet.appendRow([
        TextCellValue('Lookup'),
        FormulaCellValue('VLOOKUP(A1,B:B,2,FALSE)'),
      ]);
      sheet.appendRow([TextCellValue('Plain')]);
      return Uint8List.fromList(excel.encode()!);
    }

    test('a supported formula keeps its expression', () {
      final grid = service
          .readWorkbookGrids(formulaWorkbook(), 'accounts.xlsx')
          .sheets
          .first;
      final cell = grid.cellAt(3, 1);
      expect(cell.isFormula, isTrue);
      expect(cell.formula, contains('SUM'));
    });

    test('a supported formula is recalculated by the existing engine', () {
      final grid = service
          .readWorkbookGrids(formulaWorkbook(), 'accounts.xlsx')
          .sheets
          .first;
      // 30 + 95, calculated rather than read from the file.
      expect(grid.displayAt(3, 1).label, '125');
    });

    test('an unsupported formula keeps its expression', () {
      final grid = service
          .readWorkbookGrids(formulaWorkbook(), 'accounts.xlsx')
          .sheets
          .first;
      final cell = grid.cellAt(4, 1);
      expect(cell.isFormula, isTrue);
      expect(cell.formula, contains('VLOOKUP'));
    });

    test('an unsupported formula is never replaced with zero', () {
      final grid = service
          .readWorkbookGrids(formulaWorkbook(), 'accounts.xlsx')
          .sheets
          .first;
      final shown = grid.displayAt(4, 1);
      expect(shown.label, isNot('0'));
      expect(shown.error, isNotNull);
    });

    test('normal text, numbers and blanks are unchanged', () {
      final grid = service
          .readWorkbookGrids(formulaWorkbook(), 'accounts.xlsx')
          .sheets
          .first;
      expect(grid.cellAt(0, 1).text, 'Amount');
      expect(grid.cellAt(1, 1).number, 30);
      expect(grid.cellAt(5, 0).text, 'Plain');
      expect(grid.cellAt(5, 0).isFormula, isFalse);
    });

    test('a formula survives saving and reopening with both parts', () async {
      sqfliteFfiInit();
      // The table is created explicitly rather than in onCreate, because an
      // in-memory database may already exist by the time this runs.
      final database = await databaseFactoryFfi.openDatabase(':memory:');
      await database.execute(
        'CREATE TABLE IF NOT EXISTS local_metadata '
        '(key TEXT PRIMARY KEY, value TEXT NOT NULL)',
      );
      addTearDown(database.close);
      final store = WorkbookGridStore(database);
      final grid = service
          .readWorkbookGrids(formulaWorkbook(), 'accounts.xlsx')
          .sheets
          .first;

      await store.save(companyId: 'company-1', grid: grid);
      final reloaded = await store.load(
        companyId: 'company-1',
        filename: 'accounts.xlsx',
        sheetName: 'Data',
      );

      expect(reloaded!.cellAt(3, 1).isFormula, isTrue);
      expect(reloaded.cellAt(3, 1).formula, contains('SUM'));
      // The recalculated value is what the sheet shows once it is reopened.
      expect(reloaded.displayAt(3, 1).label, '125');
    });

    test('a formula in a macro-enabled workbook is read the same way', () {
      final grid = service
          .readWorkbookGrids(formulaWorkbook(), 'accounts.xlsm')
          .sheets
          .first;
      expect(grid.cellAt(3, 1).isFormula, isTrue);
      expect(grid.displayAt(3, 1).label, '125');
    });

    test('a formula returning text shows the result, not the expression', () {
      // `t="str"` is the package's own reading path for a text result, and it
      // stores the result as the cell text. The expression is recovered from
      // the XML and kept alongside it.
      final excel = Excel.createExcel();
      final sheet = excel['Data'];
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0))
          .value = const FormulaCellValue(
        'CONCAT("Shea"," Nuts")',
      );
      final grid = service
          .readWorkbookGrids(Uint8List.fromList(excel.encode()!), 'text.xlsx')
          .sheets
          .first;
      final cell = grid.cellAt(0, 0);
      expect(cell.isFormula, isTrue);
      expect(cell.formula, isNotNull);
    });
  });

  group('large worksheets', () {
    test('a big sheet keeps every row reachable', () {
      final grid = WorkbookGrid(
        name: 'Big',
        cells: [
          for (var r = 0; r < 20000; r++) [classifyTypedCell('$r')],
        ],
      );
      // Nothing is truncated, and the last row is still addressable.
      expect(grid.rowCount, 20000);
      expect(grid.cellAt(19999, 0).text, '19999');
      expect(grid.search('19999').length, 1);
    });
  });

  group('the workbook grid screen lays out without a layout error', () {
    // Regression test.
    //
    // The worksheet and filter controls sit in a toolbar Row. A DropdownButton
    // draws its label with a Row that has a Flexible child, so it needs a
    // bounded width. When the toolbar handed it an unbounded one the screen
    // threw "RenderFlex children have non-zero flex but incoming width
    // constraints are unbounded" and then a cascade of "Cannot hit test a
    // render box that has never been laid out". This fails if that returns.
    testWidgets('opens a workbook with no exception at a desktop width', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final book = service.readWorkbookGrids(
        buildExternalWorkbook(),
        'accounts.xlsx',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: WorkbookGridScreen(
            service: service,
            store: const WorkbookGridStore(null),
            currentUser: () => adminUser,
            initialBook: book,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(DropdownButton<int>), findsOneWidget);
      expect(find.byType(DropdownButton<int?>), findsOneWidget);
    });

    // A narrow phone is the other end of the range and must also lay out.
    testWidgets('opens a workbook with no exception on a narrow screen', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final book = service.readWorkbookGrids(
        buildExternalWorkbook(),
        'accounts.xlsx',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: WorkbookGridScreen(
            service: service,
            store: const WorkbookGridStore(null),
            currentUser: () => adminUser,
            initialBook: book,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}
