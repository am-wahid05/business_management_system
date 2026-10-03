import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter_application_2/domain/models/product.dart';
import 'package:flutter_application_2/features/imports/excel_cell_parser.dart';
import 'package:flutter_application_2/features/imports/import_header_detector.dart';
import 'package:flutter_application_2/features/imports/import_models.dart';
import 'package:flutter_application_2/features/imports/import_sheet_builder.dart';

int pass = 0;
int fail = 0;

void check(String name, bool ok, [String detail = '']) {
  if (ok) {
    pass++;
    print('PASS  $name');
  } else {
    fail++;
    print('FAIL  $name  $detail');
  }
}

void sameDate(String label, String input, int y, int m, int d) {
  final parsed = parseImportDate(input);
  check(
    label,
    parsed != null && parsed.year == y && parsed.month == m && parsed.day == d,
    '$input -> $parsed',
  );
}

/// Reads a sheet the same way ExcelImportService does for .xlsx input.
ImportSheet readSheet(Excel excel, String sheetName) {
  final grid = excel[sheetName].rows
      .map((row) => row.map((cell) => parseCellValue(cell?.value)).toList())
      .toList();
  return buildImportSheet(sheetName, grid)!;
}


void main() {
  // ---- 1. Type aware cell parsing -------------------------------------
  final textCell = parseCellValue(TextCellValue('Ibrahim Mensah'));
  check('text cell -> text', textCell.text == 'Ibrahim Mensah' && textCell.number == null);

  final intCell = parseCellValue(IntCellValue(50240));
  check('int cell -> number', intCell.number == 50240, '${intCell.number}');

  final dbl = parseCellValue(DoubleCellValue(1234.5));
  check('double cell -> number', dbl.number == 1234.5);

  check(
    'whole double has no trailing .0',
    parseCellValue(DoubleCellValue(50240)).text == '50240',
  );
  check('bool cell -> text', parseCellValue(BoolCellValue(true)).text == 'true');

  final formula = parseCellValue(FormulaCellValue('250'));
  check(
    'formula cell -> cached value and is flagged',
    formula.text == '250' && formula.isFormula,
  );
  check('null cell -> blank', parseCellValue(null).isBlank);

  // ---- 2. Native date cells do not shift the day ----------------------
  final nativeDate = parseCellValue(
    DateCellValue.fromDateTime(DateTime(2026, 9, 26)),
  );
  check(
    'native DateCellValue keeps 26/09/2026 and stays local',
    nativeDate.date != null &&
        nativeDate.date!.year == 2026 &&
        nativeDate.date!.month == 9 &&
        nativeDate.date!.day == 26 &&
        !nativeDate.date!.isUtc,
    '${nativeDate.date}',
  );
  final nativeDateTime = parseCellValue(
    DateTimeCellValue.fromDateTime(DateTime(2026, 9, 26, 14, 30)),
  );
  check(
    'native DateTimeCellValue keeps day and time',
    nativeDateTime.date!.day == 26 && nativeDateTime.date!.hour == 14,
  );

  // ---- 3. Date formats -------------------------------------------------
  sameDate('dd/MM/yyyy', '26/09/2026', 2026, 9, 26);
  sameDate('dd-MM-yyyy', '26-09-2026', 2026, 9, 26);
  sameDate('d/M/yy', '3/9/26', 2026, 9, 3);
  sameDate('ISO', '2026-09-26', 2026, 9, 26);
  sameDate('ISO with Z does not shift', '2026-09-26T00:00:00.000Z', 2026, 9, 26);
  sameDate('MM/dd/yyyy unambiguous', '09/26/2026', 2026, 9, 26);
  sameDate('ambiguous reads dd/MM', '03/04/2026', 2026, 4, 3);
  sameDate('dot separated', '26.09.2026', 2026, 9, 26);
  check('impossible date rejected', parseImportDate('31/02/2026') == null);
  check('non date rejected', parseImportDate('not a date') == null);
  check(
    'bare number is not a date unless serials are allowed',
    parseImportDate('50240') == null &&
        parseImportDate('46000', allowSerial: true) != null,
  );

  // ---- 4. Numbers ------------------------------------------------------
  check('plain number', parseImportNumber('50240') == 50240);
  check('thousands separated integer', parseImportNumber('50,240') == 50240);
  check('thousands separated decimal', parseImportNumber('50,240.5') == 50240.5);

  // ---- 5. Header detection --------------------------------------------
  check(
    'substring matching no longer steals Total Weight',
    detectFieldForHeader('Total Weight') != ImportField.supplierName,
  );
  check('date detected', detectFieldForHeader('Date') == ImportField.date);
  check(
    'supplier name detected',
    detectFieldForHeader('Supplier Name') == ImportField.supplierName,
  );
  final reordered = guessMapping([
    'Total Weight',
    'Product',
    'Supplier Name',
    'Date',
  ]);
  check(
    'reordered columns map correctly',
    reordered.column(ImportField.totalWeight) == 'Total Weight' &&
        reordered.column(ImportField.date) == 'Date' &&
        reordered.column(ImportField.supplierName) == 'Supplier Name',
  );
  check('product ID unmapped when absent', reordered.column(ImportField.productId) == null);
  check(
    'product id inferred from name',
    inferProductId('Cashew', Product.initialProducts) == 'cashew' &&
        inferProductId('Unknown Nut', Product.initialProducts) == 'unknown_nut',
  );

  // ---- 6. External workbook with title rows and native cells ----------
  final external = Excel.createExcel();
  final sheet = external['External'];
  sheet.appendRow([TextCellValue('AL_BNC WEIGHBRIDGE SUMMARY')]);
  // A note row that is not empty, so the file format keeps it.
  sheet.appendRow([TextCellValue('Exported by: weighing bridge PC')]);
  // Reordered columns and no Product ID column at all.
  sheet.appendRow([
    TextCellValue('Total Weight'),
    TextCellValue('Date'),
    TextCellValue('Product'),
    TextCellValue('Supplier Name'),
  ]);
  // Row 4: a real numeric cell, a native date cell, messy supplier spacing.
  sheet.appendRow([
    DoubleCellValue(50240),
    DateCellValue.fromDateTime(DateTime(2026, 9, 26)),
    TextCellValue('Cashew'),
    TextCellValue('  John   Mensah  '),
  ]);
  // Row 5: a dd/MM/yyyy text date and a thousands separated weight.
  sheet.appendRow([
    TextCellValue('1,200.5'),
    TextCellValue('05/09/2026'),
    TextCellValue('Cocoa'),
    TextCellValue('AMA SERWA'),
  ]);
  // Row 6: an impossible date, so the row must carry a clear error.
  sheet.appendRow([
    TextCellValue('500'),
    TextCellValue('31/02/2026'),
    TextCellValue('Cashew'),
    TextCellValue('Broken Row'),
  ]);
  // A blank spacer row inside the data must be ignored, not reported.
  sheet.appendRow([]);

  final encoded = Uint8List.fromList(external.encode()!);
  final reread = Excel.decodeBytes(encoded);
  final parsed = readSheet(reread, 'External');

  check(
    'header found below the title row',
    parsed.headerRowIndex == 2,
    '${parsed.headerRowIndex}',
  );
  check('three data rows read', parsed.rows.length == 3, '${parsed.rows.length}');

  final mapping = guessMapping(parsed.headers);
  final weightIndex = parsed.headers.indexOf('Total Weight');
  final dateIndex = parsed.headers.indexOf('Date');
  final productIndex = parsed.headers.indexOf('Product');

  final row4 = parsed.rows[0];
  check(
    'row 4 keeps the spreadsheet day, with no timezone shift',
    row4[dateIndex].asDate()!.day == 26 &&
        row4[dateIndex].asDate()!.month == 9 &&
        row4[dateIndex].asDate()!.year == 2026 &&
        !row4[dateIndex].date!.isUtc,
    '${row4[dateIndex].date}',
  );
  check('row 4 numeric weight read', row4[weightIndex].asNumber() == 50240);
  check('row 4 product read', row4[productIndex].text == 'Cashew');
  check(
    'row 4 supplier spacing preserved for matching',
    row4[3].text.trim() == 'John   Mensah',
  );

  final row5 = parsed.rows[1];
  check(
    'row 5 dd/MM/yyyy text date parsed',
    row5[dateIndex].asDate()!.month == 9 && row5[dateIndex].asDate()!.day == 5,
    '${row5[dateIndex].asDate()}',
  );
  check(
    'row 5 thousands separated weight read',
    row5[weightIndex].asNumber() == 1200.5,
    '${row5[weightIndex].asNumber()}',
  );

  final row6 = parsed.rows[2];
  check(
    'row 6 impossible date yields no date',
    row6[dateIndex].asDate() == null,
    '${row6[dateIndex].asDate()}',
  );

  // ---- 7. Round trip of the application's own exported format ---------
  final roundTrip = Excel.createExcel();
  final rt = roundTrip['Receiving'];
  rt.appendRow([
    'Date', 'Supplier ID', 'Supplier Name', 'Supplier Type', 'Town', 'District',
    'Region', 'Product ID', 'Product', 'Number of Bags', 'Total Weight',
    'Recorded By',
  ].map(TextCellValue.new).toList());
  rt.appendRow([
    DateCellValue.fromDateTime(DateTime(2026, 9, 26)),
    TextCellValue('ALB-ABC-000001'),
    TextCellValue('Ibrahim Mensah'),
    TextCellValue('farmer'),
    TextCellValue('Techiman'),
    TextCellValue('Techiman Municipal'),
    TextCellValue('Bono East'),
    TextCellValue('cashew'),
    TextCellValue('Cashew'),
    IntCellValue(2),
    DoubleCellValue(150),
    TextCellValue('Not recorded'),
  ]);
  final rtSheet = readSheet(Excel.decodeBytes(Uint8List.fromList(roundTrip.encode()!)), 'Receiving');
  final rtMapping = guessMapping(rtSheet.headers);
  check(
    'Product ID column is detected on re-import',
    rtMapping.column(ImportField.productId) == 'Product ID',
  );
  check(
    'exported date column maps to date',
    rtMapping.column(ImportField.date) == 'Date',
  );
  final rtDate = rtSheet.rows[0][rtSheet.headers.indexOf('Date')].asDate()!;
  check(
    'exported file re-imports the same calendar day',
    rtDate.year == 2026 && rtDate.month == 9 && rtDate.day == 26,
    '$rtDate',
  );
  check(
    'exported file re-imports the same weight',
    rtSheet.rows[0][rtSheet.headers.indexOf('Total Weight')].asNumber() == 150,
  );

  // ---- 8. CSV needs no extra package ----------------------------------
  final csvSheet = buildImportSheetFromCsv(
    'Date,Supplier Name,Product,Total Weight\r\n'
    '26/09/2026,John Mensah,Cashew,"50,240"\r\n',
  )!;
  check('csv header detected', csvSheet.headers.length == 4, '${csvSheet.headers}');
  check('csv row read', csvSheet.rows.length == 1);
  final csvDate = csvSheet.rows[0][csvSheet.headers.indexOf('Date')].asDate()!;
  check(
    'csv dd/MM/yyyy date parsed',
    csvDate.month == 9 && csvDate.day == 26,
    '$csvDate',
  );
  check(
    'csv quoted thousands separated weight read',
    csvSheet.rows[0][csvSheet.headers.indexOf('Total Weight')].asNumber() == 50240,
  );

  print('');
  print('passed=$pass failed=$fail');
}
