import 'package:flutter_application_2/features/spreadsheet/spreadsheet_clipboard.dart';
import 'package:flutter_application_2/features/spreadsheet/spreadsheet_formatting.dart';
import 'package:flutter_application_2/features/spreadsheet/spreadsheet_formula.dart';
import 'package:flutter_test/flutter_test.dart';

/// A simple in-memory grid used to exercise the formula engine.
class _TestGrid implements FormulaGrid {
  _TestGrid(this.values);

  /// Row-major values, where a cell is a number or a string.
  final List<List<Object?>> values;

  @override
  int get rowCount => values.length;

  @override
  int get columnCount => values.isEmpty ? 0 : values.first.length;

  @override
  double? numberAt(int row, int column) {
    final value = _at(row, column);
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  @override
  String textAt(int row, int column) => '${_at(row, column) ?? ''}';

  Object? _at(int row, int column) {
    if (row < 0 || row >= values.length) return null;
    final line = values[row];
    if (column < 0 || column >= line.length) return null;
    return line[column];
  }
}

void main() {
  group('column references', () {
    test('letters map to indexes', () {
      expect(FormulaGrid.columnLetter(0), 'A');
      expect(FormulaGrid.columnLetter(3), 'D');
      expect(FormulaGrid.columnLetter(25), 'Z');
      expect(FormulaGrid.columnLetter(26), 'AA');
    });

    test('indexes map back to letters', () {
      expect(FormulaGrid.columnFromLetter('A'), 0);
      expect(FormulaGrid.columnFromLetter('D'), 3);
      expect(FormulaGrid.columnFromLetter('AA'), 26);
      expect(FormulaGrid.columnFromLetter('1'), isNull);
    });
  });

  group('formulas', () {
    // Column D holds the weights, so D1 is the first data row.
    final grid = _TestGrid([
      [10.0, 'A', 'Cashew', 10.0],
      [11.0, 'B', 'Cocoa', 20.0],
      [12.0, 'C', 'Cashew', 30.0],
    ]);
    final evaluator = FormulaEvaluator(grid);

    double? value(String formula) => evaluator.evaluate(formula).value;
    FormulaError? errorOf(String formula) => evaluator.evaluate(formula).error;

    test('SUM adds a range', () {
      expect(value('=SUM(D1:D3)'), 60);
    });

    test('AVERAGE averages a range', () {
      expect(value('=AVERAGE(D1:D3)'), 20);
    });

    test('COUNT counts the numbers in a range', () {
      expect(value('=COUNT(D1:D3)'), 3);
    });

    test('MIN finds the smallest value', () {
      expect(value('=MIN(D1:D3)'), 10);
    });

    test('MAX finds the largest value', () {
      expect(value('=MAX(D1:D3)'), 30);
    });

    test('addition between cells', () {
      expect(value('=D1+D2'), 30);
    });

    test('subtraction between cells', () {
      expect(value('=D3-D1'), 20);
    });

    test('multiplication between cells', () {
      expect(value('=D1*D2'), 200);
    });

    test('division between cells', () {
      expect(value('=D3/D1'), 3);
    });

    test('arithmetic with a literal number', () {
      expect(value('=D1+5'), 15);
      expect(value('=D1*2'), 20);
    });

    test('a bare cell reference reads that cell', () {
      expect(value('=D2'), 20);
    });

    test('a sum of separate cells', () {
      expect(value('=SUM(D1,D2,D3)'), 60);
    });

    test('a range that leaves the grid is empty, not an error', () {
      expect(value('=SUM(D1:D50)'), 60);
    });

    test('a minus sign inside a cell name is not an operator', () {
      // A1-B1 must subtract, and because B1 holds text the result is
      // reported rather than quietly treated as zero.
      expect(value('=D3-D1'), 20);
      expect(errorOf('=A1-B1'), FormulaError.notANumber);
    });
  });

  group('invalid formulas', () {
    final evaluator = FormulaEvaluator(
      _TestGrid([
        [1.0, 0.0, 2.0],
      ]),
    );

    test('division by zero is reported', () {
      final result = evaluator.evaluate('=A1/B1');
      expect(result.error, FormulaError.divideByZero);
      expect(result.isFailure, isTrue);
    });

    test('an unknown function is reported, not thrown', () {
      expect(
        evaluator.evaluate('=VLOOKUP(A1,B1:B2,2)').error,
        FormulaError.unknownFunction,
      );
    });

    test('a malformed formula is reported', () {
      expect(evaluator.evaluate('=').error, FormulaError.malformed);
      expect(evaluator.evaluate('=++').error, isNotNull);
    });

    test('AVERAGE with no numbers is reported', () {
      final textGrid = _TestGrid([
        ['John Mensah', 'Cashew'],
      ]);
      expect(
        FormulaEvaluator(textGrid).evaluate('=AVERAGE(A1:B1)').error,
        FormulaError.notANumber,
      );
    });

    test('a non formula is returned as a literal', () {
      final result = evaluator.evaluate('John Mensah');
      expect(result.isFailure, isFalse);
      expect(result.text, 'John Mensah');
    });

    test('every failure has a readable message', () {
      expect(evaluator.evaluate('=NOPE(A1)').errorLabel, 'Unknown function');
      expect(evaluator.evaluate('=').errorLabel, isNotEmpty);
    });
  });

  group('recalculation', () {
    test('a formula result changes when a referenced value changes', () {
      final grid = _TestGrid([
        [10.0],
        [20.0],
      ]);
      final evaluator = FormulaEvaluator(grid);
      expect(evaluator.evaluate('=SUM(A1:A2)').value, 30);

      // The grid is re-read on every evaluation, so the result recalculates.
      grid.values[1][0] = 50.0;
      expect(evaluator.evaluate('=SUM(A1:A2)').value, 60);
    });
  });

  group('copy and paste ranges', () {
    test('a range is labelled like a spreadsheet', () {
      expect(const CellRange.single(0, 0).label, 'A1');
      expect(
        const CellRange(
          startColumn: 0,
          startRow: 0,
          endColumn: 2,
          endRow: 1,
        ).label,
        'A1:C2',
      );
    });

    test('a range between two cells handles either order', () {
      final range = CellRange.between(
        const CellPosition(3, 1),
        const CellPosition(1, 0),
      );
      expect(range.startColumn, 0);
      expect(range.endColumn, 1);
      expect(range.startRow, 1);
      expect(range.endRow, 3);
    });

    test('a single cell range reports itself', () {
      const range = CellRange.single(2, 4);
      expect(range.isSingleCell, isTrue);
      expect(range.columnCount, 1);
      expect(range.rowCount, 1);
    });

    test('a copied block only keeps the copied rectangle', () {
      final block = ClipboardBlock.of(
        const CellRange(startColumn: 1, startRow: 1, endColumn: 2, endRow: 1),
        [
          ['row0a', 'row0b'],
          ['a', 'b', 'c', 'd'],
        ],
      );
      expect(block.rowCount, 1);
      expect(block.columnCount, 2);
      expect(block.values.single, ['b', 'c']);
    });
  });

  group('session formatting', () {
    test('formatting is applied across a range', () {
      final clipboard = SpreadsheetClipboard();
      clipboard.format(
        const CellRange(startColumn: 0, startRow: 0, endColumn: 1, endRow: 1),
        (current) => current.copyWith(background: CellColor.yellow),
      );
      expect(
        clipboard.formatAt(const CellPosition(0, 0)).background,
        CellColor.yellow,
      );
      expect(
        clipboard.formatAt(const CellPosition(1, 1)).background,
        CellColor.yellow,
      );
    });

    test('formatting does not leak outside the range', () {
      final clipboard = SpreadsheetClipboard();
      clipboard.format(
        const CellRange(startColumn: 0, startRow: 0, endColumn: 0, endRow: 0),
        (current) => current.copyWith(bold: true),
      );
      expect(clipboard.formatAt(const CellPosition(0, 0)).bold, isTrue);
      expect(clipboard.formatAt(const CellPosition(0, 1)).bold, isFalse);
    });

    test('a plain format is not stored', () {
      final clipboard = SpreadsheetClipboard();
      clipboard.format(
        const CellRange.single(0, 0),
        (current) => current.copyWith(background: CellColor.red),
      );
      expect(clipboard.formats, isNotEmpty);
      clipboard.format(const CellRange.single(0, 0), (_) => const CellFormat());
      expect(clipboard.formats, isEmpty);
    });

    test('the colour palette is controlled', () {
      expect(CellColor.values, hasLength(7));
      expect(CellColor.none.argb, isNull);
      for (final color in CellColor.values.where((c) => c != CellColor.none)) {
        expect(color.argb, isNotNull);
        expect(color.label, isNotEmpty);
      }
    });

    test('a format survives a map round trip', () {
      const format = CellFormat(
        background: CellColor.green,
        bold: true,
        italic: true,
        alignment: CellAlignment.right,
      );
      final restored = CellFormat.fromMap(format.toMap());
      expect(restored.background, CellColor.green);
      expect(restored.bold, isTrue);
      expect(restored.italic, isTrue);
      expect(restored.alignment, CellAlignment.right);
    });
  });
}
