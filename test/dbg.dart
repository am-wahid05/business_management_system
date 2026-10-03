import 'package:excel/excel.dart';
import 'package:flutter_application_2/features/imports/excel_cell_parser.dart';
import 'package:flutter_application_2/features/imports/import_header_detector.dart';

void main() {
  final external = Excel.createExcel();
  final sheet = external['External'];
  sheet.appendRow([TextCellValue('AL_BNC WEIGHBRIDGE SUMMARY')]);
  sheet.appendRow([]);
  sheet.appendRow([
    TextCellValue('Total Weight'),
    TextCellValue('Date'),
    TextCellValue('Product'),
    TextCellValue('Supplier Name'),
  ]);
  sheet.appendRow([
    DoubleCellValue(50240),
    DateCellValue.fromDateTime(DateTime(2026, 9, 26)),
    TextCellValue('Cashew'),
    TextCellValue('  John   Mensah  '),
  ]);

  final decoded = Excel.decodeBytes(external.encode()!);
  final rows = decoded['External'].rows;
  for (var i = 0; i < rows.length; i++) {
    final texts = rows[i]
        .map((c) => parseCellValue(c?.value).text)
        .toList();
    final recognised = texts
        .where((t) => t.trim().isNotEmpty && detectFieldForHeader(t) != null)
        .length;
    final fields = texts
        .where((t) => t.trim().isNotEmpty)
        .map((t) => '${t.trim()} -> ${detectFieldForHeader(t)}')
        .toList();
    print('row $i: cells=${texts.length} recognised=$recognised');
    for (final f in fields) {
      print('    $f');
    }
  }
  print('detected header row = ${detectHeaderRow(rows.map((r) => r.map((c) => parseCellValue(c?.value).text).toList()).toList())}');
}
