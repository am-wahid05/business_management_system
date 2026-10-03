import 'excel_cell_parser.dart';
import 'import_header_detector.dart';
import 'import_models.dart';

/// Builds an [ImportSheet] from a raw grid of typed cells.
///
/// This is deliberately free of any database dependency, so the whole reading
/// path can be exercised by tests and reused by the CSV reader.
ImportSheet? buildImportSheet(String name, List<List<ParsedCell>> grid) {
  if (grid.isEmpty) return null;

  // The header is not assumed to be the first row: workbooks commonly start
  // with a title or a blank spacer row.
  final headerIndex = detectHeaderRow(
    grid.map((row) => row.map((cell) => cell.text).toList()).toList(),
  );
  final headerRow = grid[headerIndex];
  var width = headerRow.length;
  for (final row in grid.skip(headerIndex + 1)) {
    if (row.length > width) width = row.length;
  }
  final headers = List<String>.generate(
    width,
    (index) =>
        index < headerRow.length && headerRow[index].text.trim().isNotEmpty
        ? headerRow[index].text.trim()
        : 'Column ${index + 1}',
    growable: false,
  );

  final rows = <List<ParsedCell>>[];
  for (final row in grid.skip(headerIndex + 1)) {
    // A blank spacer row inside the data is skipped, not reported as an error.
    if (row.every((cell) => cell.isBlank)) continue;
    rows.add(
      List<ParsedCell>.generate(
        width,
        (index) => index < row.length ? row[index] : const ParsedCell.blank(),
        growable: false,
      ),
    );
  }
  if (rows.isEmpty) return null;
  return ImportSheet(
    name: name,
    headers: headers,
    rows: rows,
    headerRowIndex: headerIndex,
  );
}

/// Splits CSV text into rows, honouring quoted fields that contain commas or
/// doubled quotes. Returns the fields as plain strings.
List<List<String>> splitCsvLines(String text) {
  final lines = <List<String>>[];
  var field = StringBuffer();
  var row = <String>[];
  var inQuotes = false;
  for (var index = 0; index < text.length; index++) {
    final char = text[index];
    if (inQuotes) {
      if (char == '"') {
        // A doubled quote inside a quoted field is a literal quote.
        if (index + 1 < text.length && text[index + 1] == '"') {
          field.write('"');
          index++;
        } else {
          inQuotes = false;
        }
      } else {
        field.write(char);
      }
      continue;
    }
    if (char == '"') {
      inQuotes = true;
    } else if (char == ',') {
      row.add(field.toString());
      field = StringBuffer();
    } else if (char == '\n' || char == '\r') {
      // Treat CRLF as a single line break.
      if (char == '\r' && index + 1 < text.length && text[index + 1] == '\n') {
        index++;
      }
      row.add(field.toString());
      field = StringBuffer();
      lines.add(row);
      row = <String>[];
    } else {
      field.write(char);
    }
  }
  if (field.isNotEmpty || row.isNotEmpty) {
    row.add(field.toString());
    lines.add(row);
  }
  return lines;
}

/// Converts CSV text rows into a sheet, using the same header detection and
/// the same typed cell model as the .xlsx reader.
ImportSheet? buildImportSheetFromCsv(String text) {
  final grid = <List<ParsedCell>>[];
  for (final line in splitCsvLines(text)) {
    if (line.every((cell) => cell.trim().isEmpty)) continue;
    grid.add(line.map((value) => ParsedCell(text: value)).toList());
  }
  return buildImportSheet('Sheet1', grid);
}
