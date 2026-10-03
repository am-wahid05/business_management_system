import 'package:flutter_application_2/features/imports/excel_cell_parser.dart';
import 'package:flutter_application_2/features/imports/supplier_name_detector.dart';
import 'package:flutter_application_2/features/imports/workbook_grid_model.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds a grid from plain rows, so the detector can be tested on its own.
WorkbookGrid gridOf(List<List<String>> rows) => WorkbookGrid(
  name: 'S',
  cells: [
    for (final row in rows)
      row.map((value) => ParsedCell(text: value)).toList(),
  ],
);

/// The accounting sheet from the brief, including a blank and a total row.
WorkbookGrid accountSheet() => gridOf([
  ['Supplier', 'Product', 'Weight'],
  ['Kofi Farms', 'Shea Nuts', '120'],
  ['Ama Trading', 'Shea Nuts', '95'],
  ['Kofi Farms', 'Shea Nuts', '80'],
  ['', '', ''],
  ['Total', '', '295'],
]);

void main() {
  const detector = SupplierNameDetector();

  group('reading a supplier column', () {
    test('finds the distinct names in the example sheet', () {
      final detection = detector.detect(grid: accountSheet(), column: 0);
      expect(detection.toCreate.map((e) => e.name), [
        'Kofi Farms',
        'Ama Trading',
      ]);
    });

    test('suggests the supplier column from its heading', () {
      expect(detector.suggestColumn(accountSheet()), 0);
    });

    test('does not suggest a numeric column', () {
      final weights = gridOf([
        ['Product', 'Weight'],
        ['Shea Nuts', '120'],
        ['Shea Nuts', '95'],
      ]);
      expect(detector.suggestColumn(weights), isNull);
    });

    test('trims surrounding and repeated whitespace', () {
      final grid = gridOf([
        ['Supplier'],
        ['  Kofi   Farms  '],
      ]);
      final detection = detector.detect(grid: grid, column: 0);
      expect(detection.toCreate.single.name, 'Kofi Farms');
    });

    test('ignores the column heading itself', () {
      final detection = detector.detect(grid: accountSheet(), column: 0);
      expect(
        detection.ignored.firstWhere((e) => e.name == 'Supplier').reason,
        'Column heading',
      );
    });

    test('ignores a blank cell', () {
      final detection = detector.detect(grid: accountSheet(), column: 0);
      expect(detection.ignored.any((e) => e.reason == 'Blank'), isTrue);
    });

    test('ignores a total row', () {
      final detection = detector.detect(grid: accountSheet(), column: 0);
      expect(detection.ignored.any((e) => e.reason == 'Total row'), isTrue);
    });

    test('ignores a formula whose result is blank', () {
      final grid = WorkbookGrid(
        name: 'S',
        cells: [
          [const ParsedCell(text: 'Supplier')],
          [
            const ParsedCell(
              text: '=IF(1=1,"","x")',
              isFormula: true,
              cachedText: '',
            ),
          ],
        ],
      );
      final detection = detector.detect(grid: grid, column: 0);
      expect(detection.toCreate, isEmpty);
    });

    test('deduplicates a repeated name', () {
      final detection = detector.detect(grid: accountSheet(), column: 0);
      expect(
        detection.ignored.any((e) => e.reason == 'Repeated in this file'),
        isTrue,
      );
    });
  });

  group('case and whitespace insensitive matching', () {
    test('treats different casings and spacing as one supplier', () {
      final grid = gridOf([
        ['Supplier'],
        ['Kofi Farms'],
        ['kofi farms'],
        ['  KOFI   FARMS '],
      ]);
      final detection = detector.detect(grid: grid, column: 0);
      expect(detection.toCreate.length, 1);
    });

    test('matches an existing supplier regardless of case or spacing', () {
      final grid = gridOf([
        ['Supplier'],
        ['  kofi   farms '],
      ]);
      final detection = detector.detect(
        grid: grid,
        column: 0,
        existingNames: const ['Kofi Farms'],
      );
      expect(detection.toCreate, isEmpty);
      // The preview uses the same cleaned name form that creation stores.
      expect(detection.existing.single.name, 'kofi farms');
    });
  });

  group('preview and confirmation', () {
    test('reading a column never changes anything by itself', () {
      // Detection is a pure read: it returns a plan and creates nothing, so the
      // caller must confirm before any repository call.
      final detection = detector.detect(grid: accountSheet(), column: 0);
      expect(detection.toCreate.length, 2);
      expect(detection.existing, isEmpty);
    });

    test('an empty column yields nothing to create', () {
      final grid = gridOf([
        ['Weight'],
        ['120'],
      ]);
      final detection = detector.detect(grid: grid, column: 0);
      expect(detection.toCreate, isEmpty);
    });
  });

  group('automatic column suggestion', () {
    test('suggests nothing when no heading is recognisable', () {
      final grid = gridOf([
        ['Alpha', 'Beta'],
        ['one', 'two'],
      ]);
      expect(detector.suggestColumn(grid), isNull);
    });

    test('a manual column can be used when nothing is suggested', () {
      final grid = gridOf([
        ['Alpha', 'Beta'],
        ['Kofi Farms', 'Ama Trading'],
      ]);
      // The caller picks column 1 by hand; detection stays in that column.
      final detection = detector.detect(grid: grid, column: 1);
      expect(detection.toCreate.map((e) => e.name), ['Ama Trading']);
    });
  });
}
