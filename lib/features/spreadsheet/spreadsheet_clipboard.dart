import 'spreadsheet_formula.dart';

/// A rectangular selection of cells, addressed by column and row index.
class CellRange {
  const CellRange({
    required this.startColumn,
    required this.startRow,
    required this.endColumn,
    required this.endRow,
  });

  /// A single cell.
  const CellRange.single(int column, int row)
    : startColumn = column,
      startRow = row,
      endColumn = column,
      endRow = row;

  /// Builds a range from two corner cells in any order.
  factory CellRange.between(CellPosition from, CellPosition to) {
    final startRow = from.row <= to.row ? from.row : to.row;
    final endRow = from.row <= to.row ? to.row : from.row;
    final startColumn = from.column <= to.column ? from.column : to.column;
    final endColumn = from.column <= to.column ? to.column : from.column;
    return CellRange(
      startColumn: startColumn,
      startRow: startRow,
      endColumn: endColumn,
      endRow: endRow,
    );
  }

  final int startColumn;
  final int startRow;
  final int endColumn;
  final int endRow;

  int get columnCount => endColumn - startColumn + 1;
  int get rowCount => endRow - startRow + 1;
  bool get isSingleCell => columnCount == 1 && rowCount == 1;
  bool get isSingleRow => rowCount == 1;

  /// A readable label such as `A1` or `A1:C5`.
  String get label {
    final start = '${FormulaGrid.columnLetter(startColumn)}${startRow + 1}';
    if (isSingleCell) return start;
    final end = '${FormulaGrid.columnLetter(endColumn)}${endRow + 1}';
    return '$start:$end';
  }
}

/// One cell inside a copied block.
class CellPosition {
  const CellPosition(this.row, this.column);
  final int row;
  final int column;

  @override
  bool operator ==(Object other) =>
      other is CellPosition && other.row == row && other.column == column;

  @override
  int get hashCode => Object.hash(row, column);
}

/// A block of copied cell text, ready to be pasted anywhere.
class ClipboardBlock {
  const ClipboardBlock({required this.range, required this.values});

  factory ClipboardBlock.of(CellRange range, List<List<String>> values) {
    // Only the copied rectangle is kept, so a paste cannot bring extra cells.
    // The grid is addressed by absolute row and column, so the range offsets
    // are applied rather than reading from the top left corner.
    final rows = <List<String>>[];
    for (var row = 0; row < range.rowCount; row++) {
      final source = range.startRow + row < values.length
          ? values[range.startRow + row]
          : const <String>[];
      final cells = <String>[];
      for (var column = 0; column < range.columnCount; column++) {
        final position = range.startColumn + column;
        cells.add(position < source.length ? source[position] : '');
      }
      rows.add(cells);
    }
    return ClipboardBlock(range: range, values: rows);
  }

  final CellRange range;
  final List<List<String>> values;

  int get rowCount => values.length;
  int get columnCount => values.isEmpty ? 0 : values.first.length;
}
