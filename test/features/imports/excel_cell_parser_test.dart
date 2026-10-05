import 'package:excel/excel.dart';
import 'package:flutter_application_2/features/imports/excel_cell_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseCellValue keeps the cell type', () {
    test('reads a text cell as text', () {
      final cell = parseCellValue(TextCellValue('Ibrahim Mensah'));
      expect(cell.text, 'Ibrahim Mensah');
      expect(cell.number, isNull);
      expect(cell.date, isNull);
    });

    test('reads an int cell as a number', () {
      final cell = parseCellValue(IntCellValue(50240));
      expect(cell.number, 50240);
      expect(cell.asNumber(), 50240);
      expect(cell.text, '50240');
    });

    test('reads a double cell as a number', () {
      final cell = parseCellValue(DoubleCellValue(1234.5));
      expect(cell.number, 1234.5);
      expect(cell.text, '1234.5');
    });

    test('reads a bool cell as text', () {
      expect(parseCellValue(BoolCellValue(true)).text, 'true');
      expect(parseCellValue(BoolCellValue(false)).text, 'false');
    });

    test('reads a formula cell cached value and flags it', () {
      final cell = parseCellValue(FormulaCellValue('250'));
      expect(cell.text, '250');
      expect(cell.isFormula, isTrue);
    });

    test('reads a null cell as blank', () {
      final cell = parseCellValue(null);
      expect(cell.isBlank, isTrue);
      expect(cell.number, isNull);
      expect(cell.date, isNull);
    });

    test('a whole-valued double does not show a trailing .0', () {
      expect(parseCellValue(DoubleCellValue(50240)).text, '50240');
    });
  });

  group('a native date cell keeps its exact calendar day', () {
    test('26/09/2026 stays 26 September, with no UTC shift', () {
      final cell = parseCellValue(
        DateCellValue.fromDateTime(DateTime(2026, 9, 26)),
      );
      expect(cell.date, isNotNull);
      expect(cell.date!.year, 2026);
      expect(cell.date!.month, 9);
      expect(cell.date!.day, 26);
      // The old toString() path produced 2026-09-26T00:00:00.000Z.
      expect(cell.date!.isUtc, isFalse);
      expect(cell.text, '26/09/2026');
    });

    test('a date-time cell keeps both the day and the time', () {
      final cell = parseCellValue(
        DateTimeCellValue.fromDateTime(DateTime(2026, 9, 26, 14, 30)),
      );
      expect(cell.date!.day, 26);
      expect(cell.date!.hour, 14);
      expect(cell.text, '26/09/2026 14:30');
    });

    test('a round trip through encode and decode keeps the day', () {
      final excel = Excel.createExcel();
      excel['Data'].appendRow([
        DateCellValue.fromDateTime(DateTime(2026, 9, 26)),
      ]);
      final decoded = Excel.decodeBytes(excel.encode()!);
      final cell = parseCellValue(decoded['Data'].rows.first.first?.value);
      expect(cell.date!.year, 2026);
      expect(cell.date!.month, 9);
      expect(cell.date!.day, 26);
    });
  });

  group('parseImportDate', () {
    test('parses dd/MM/yyyy', () {
      final date = parseImportDate('26/09/2026');
      expect(date!.year, 2026);
      expect(date.month, 9);
      expect(date.day, 26);
    });

    test('parses dd-MM-yyyy', () {
      final date = parseImportDate('26-09-2026');
      expect(date!.month, 9);
      expect(date.day, 26);
    });

    test('parses a single digit day and month', () {
      final date = parseImportDate('3/9/26');
      expect(date!.year, 2026);
      expect(date.month, 9);
      expect(date.day, 3);
    });

    test('parses ISO dates', () {
      final date = parseImportDate('2026-09-26');
      expect(date!.month, 9);
      expect(date.day, 26);
    });

    test('an ISO value ending in Z does not shift the day', () {
      // This is exactly what the old toString() based reader produced for a
      // native date cell, and it used to be able to move the date.
      final date = parseImportDate('2026-09-26T00:00:00.000Z');
      expect(date!.year, 2026);
      expect(date.month, 9);
      expect(date.day, 26);
    });

    test('parses MM/dd/yyyy when the day cannot be a month', () {
      final date = parseImportDate('09/26/2026');
      expect(date!.month, 9);
      expect(date.day, 26);
    });

    test('reads an ambiguous day/month value as dd/MM', () {
      final date = parseImportDate('03/04/2026');
      expect(date!.month, 4);
      expect(date.day, 3);
    });

    test('parses an Excel serial number when allowed', () {
      final date = parseImportDate('46000', allowSerial: true);
      expect(date, isNotNull);
      expect(date!.year, greaterThanOrEqualTo(2025));
    });

    test('ignores a bare number unless serials are allowed', () {
      // 50240 is a plausible weight, so a number is not a date by default.
      expect(parseImportDate('50240'), isNull);
    });

    test('rejects impossible dates instead of rolling them over', () {
      expect(parseImportDate('31/02/2026'), isNull);
    });

    test('rejects text that is not a date', () {
      expect(parseImportDate('not a date'), isNull);
      expect(parseImportDate(''), isNull);
    });

    test('expands a two digit year', () {
      expect(parseImportDate('26/09/26')!.year, 2026);
      expect(parseImportDate('26/09/99')!.year, 1999);
    });
  });

  group('parseImportNumber', () {
    test('parses a plain number', () {
      expect(parseImportNumber('50240'), 50240);
    });

    test('parses a thousands separated integer', () {
      expect(parseImportNumber('50,240'), 50240);
    });

    test('parses a thousands separated decimal', () {
      expect(parseImportNumber('50,240.5'), 50240.5);
    });

    test('tolerates surrounding whitespace and currency symbols', () {
      expect(parseImportNumber('  1,200.75  '), 1200.75);
      expect(parseImportNumber('GHÂ¢ 900'), 900);
    });

    test('rejects text that is not a number', () {
      expect(parseImportNumber('abc'), isNull);
      expect(parseImportNumber(''), isNull);
    });
  });

  test('excelSerialToDate uses the 1899-12-30 epoch', () {
    // Day 1 is 31 December 1899, the day Excel's day counter starts.
    final first = excelSerialToDate(1);
    expect(first!.year, 1899);
    expect(first.month, 12);
    expect(first.day, 31);
  });
}
