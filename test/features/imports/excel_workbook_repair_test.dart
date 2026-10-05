import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_2/features/imports/excel_workbook_repair.dart';

/// Builds a minimal but genuinely valid OOXML package.
///
/// This is written by hand rather than produced with the `excel` package
/// because the defect under test is something that package cannot *write*: a
/// `<numFmt>` element whose id sits in the spec-reserved built-in range. Real
/// Microsoft Excel produces exactly this in accounting workbooks.
Uint8List buildWorkbook({
  required String stylesXml,
  String sheetName = 'Sheet1',
  String? cellXml,
  String contentType = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml',
}) {
  final archive = Archive();
  void add(String name, String xml) =>
      archive.addFile(ArchiveFile(name, xml.length, utf8.encode(xml)));

  add('[Content_Types].xml', '''
<?xml version="1.0" encoding="UTF-8"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/xl/workbook.xml" ContentType="$contentType"/>
  <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
  <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
</Types>''');

  add('_rels/.rels', '''
<?xml version="1.0" encoding="UTF-8"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
</Relationships>''');

  add('xl/workbook.xml', '''
<?xml version="1.0" encoding="UTF-8"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"
          xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <sheets>
    <sheet name="$sheetName" sheetId="1" r:id="rId1"/>
  </sheets>
</workbook>''');

  add('xl/_rels/workbook.xml.rels', '''
<?xml version="1.0" encoding="UTF-8"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
</Relationships>''');

  add('xl/styles.xml', stylesXml);
  add('xl/worksheets/sheet1.xml', '''
<?xml version="1.0" encoding="UTF-8"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <sheetData>${cellXml ?? ''}</sheetData>
</worksheet>''');

  final encoded = ZipEncoder().encode(archive);
  return Uint8List.fromList(encoded!);
}

/// The styles part exactly as a real accounting workbook can contain it:
/// `numFmtId="44"` is inside the 0-163 built-in range, which is what makes the
/// `excel` package throw.
const String reservedNumFmtStyles = '''
<?xml version="1.0" encoding="UTF-8"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <numFmts count="2">
    <numFmt numFmtId="44" formatCode="#,##0.00"/>
    <numFmt numFmtId="170" formatCode="dd/mm/yyyy"/>
  </numFmts>
  <cellXfs count="2">
    <xf numFmtId="44" fontId="0" fillId="0" borderId="0" xfId="0"/>
    <xf numFmtId="170" fontId="0" fillId="0" borderId="0" xfId="0"/>
  </cellXfs>
</styleSheet>''';

const String cleanStyles = '''
<?xml version="1.0" encoding="UTF-8"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <numFmts count="1">
    <numFmt numFmtId="170" formatCode="dd/mm/yyyy"/>
  </numFmts>
  <cellXfs count="1">
    <xf numFmtId="170" fontId="0" fillId="0" borderId="0" xfId="0"/>
  </cellXfs>
</styleSheet>''';

/// Reads a part back out of a package so a test can assert on the XML itself.
String readPart(Uint8List bytes, String name) {
  final file = ZipDecoder().decodeBytes(bytes).findFile(name);
  return utf8.decode(file!.content as List<int>);
}

/// The id a repaired styles part gives the format carrying [formatCode].
///
/// The replacement id is not fixed: the repair deliberately allocates one that
/// does not collide with a format the workbook already declared, so this is
/// looked up rather than assumed.
String idForFormatCode(String styles, String formatCode) {
  final match = RegExp(
    'numFmtId="(\\d+)"[^>]*formatCode="${RegExp.escape(formatCode)}"',
  ).firstMatch(styles);
  if (match == null) {
    final reversed = RegExp(
      'formatCode="${RegExp.escape(formatCode)}"[^>]*numFmtId="(\\d+)"',
    ).firstMatch(styles);
    if (reversed != null) return reversed.group(1)!;
  }
  return match?.group(1) ?? '';
}

void main() {
  group('ExcelWorkbookRepair', () {
    test('leaves a compliant workbook byte-identical', () {
      final bytes = buildWorkbook(stylesXml: cleanStyles);
      expect(ExcelWorkbookRepair.repair(bytes), same(bytes));
    });

    test('returns the input unchanged when the bytes are not a zip', () {
      final bytes = Uint8List.fromList(utf8.encode('this is not a workbook'));
      expect(ExcelWorkbookRepair.repair(bytes), same(bytes));
    });

    test('removes the reserved-range declaration the parser rejects', () {
      final styles = readPart(
        ExcelWorkbookRepair.repair(
          buildWorkbook(stylesXml: reservedNumFmtStyles),
        ),
        'xl/styles.xml',
      );
      expect(styles, isNot(contains('numFmtId="44"')));
    });

    // 44 is re-declared at or above 164, and never at an id the workbook was
    // already using, so nothing that depended on 170 changes meaning.
    test('re-declares the format at an id the package accepts', () {
      final styles = readPart(
        ExcelWorkbookRepair.repair(
          buildWorkbook(stylesXml: reservedNumFmtStyles),
        ),
        'xl/styles.xml',
      );
      final newId = int.parse(idForFormatCode(styles, '#,##0.00'));
      expect(newId, greaterThanOrEqualTo(164));
      expect(newId, isNot(170));
    });

    // The format code is the whole point. Losing it would silently turn a
    // formatted cell into a plain number, so it must survive the renumbering.
    test('keeps the format code of the moved format', () {
      final styles = readPart(
        ExcelWorkbookRepair.repair(
          buildWorkbook(stylesXml: reservedNumFmtStyles),
        ),
        'xl/styles.xml',
      );
      expect(styles, contains('formatCode="#,##0.00"'));
    });

    // A format the workbook already declared must keep its own id, or cells
    // using it would silently change meaning.
    test('leaves a compliant custom format id alone', () {
      final styles = readPart(
        ExcelWorkbookRepair.repair(
          buildWorkbook(stylesXml: reservedNumFmtStyles),
        ),
        'xl/styles.xml',
      );
      expect(styles, contains('numFmtId="170"'));
    });

    // The cellXfs entry that referenced 44 must follow it to the new id,
    // otherwise the format is orphaned and the cell falls back to built-in 44.
    test('repoints cell style references at the new id', () {
      final styles = readPart(
        ExcelWorkbookRepair.repair(
          buildWorkbook(stylesXml: reservedNumFmtStyles),
        ),
        'xl/styles.xml',
      );
      final newId = idForFormatCode(styles, '#,##0.00');
      final cellXfs = styles.substring(styles.indexOf('<cellXfs'));
      expect(cellXfs, contains('numFmtId="$newId"'));
    });

    test('is idempotent, so a repaired file can be repaired again', () {
      final once = ExcelWorkbookRepair.repair(
        buildWorkbook(stylesXml: reservedNumFmtStyles),
      );
      final twice = ExcelWorkbookRepair.repair(once);
      expect(readPart(twice, 'xl/styles.xml'), readPart(once, 'xl/styles.xml'));
    });

    // Only styles.xml may be rewritten. Every other part has to come across
    // untouched or the workbook loses data.
    test('carries every other part across unchanged', () {
      final original = buildWorkbook(
        stylesXml: reservedNumFmtStyles,
        sheetName: 'Accounts',
      );
      final repaired = ExcelWorkbookRepair.repair(original);
      for (final part in const [
        '[Content_Types].xml',
        '_rels/.rels',
        'xl/workbook.xml',
        'xl/_rels/workbook.xml.rels',
        'xl/worksheets/sheet1.xml',
      ]) {
        expect(
          readPart(repaired, part),
          readPart(original, part),
          reason: 'part must not be rewritten',
        );
      }
    });
  });
}
