import '../imports/excel_cell_parser.dart';
import '../imports/workbook_grid_model.dart';
import 'spreadsheet_controller.dart';
import 'spreadsheet_formatting.dart';
import 'spreadsheet_row.dart';

/// Projects the Admin Spreadsheet's delivery rows into a workbook grid.
///
/// This is deliberately an *adapter* and not a second engine. It reads the
/// existing [SpreadsheetController] and hands a [WorkbookGrid] to the existing
/// `WorkbookGridView`; every edit travels back through
/// [SpreadsheetController.setCell], so validation, dirty tracking, `save()`,
/// `discard()` and the delivery persistence all stay exactly as they were.
///
/// The column count comes from the controller's own [SpreadsheetController.gridColumns]
/// rather than a list written here, so a future controller column is picked up
/// automatically. No header row is invented: row 0 of the grid is the first
/// record, and the cells hold the record's real values.
class SpreadsheetGridAdapter {
  SpreadsheetGridAdapter(this.controller, {this.showRemoved = true});

  final SpreadsheetController controller;

  /// Whether a row the user removed is still drawn.
  ///
  /// This is the existing 'Show removed' control. A removed row is never deleted
  /// from the sheet, so turning this off only hides it.
  final bool showRemoved;

  /// The controller's own columns, so the grid is never hardcoded here.
  int get columnCount => SpreadsheetController.gridColumns.length;

  /// The rows the grid should draw.
  ///
  /// Search and filters can narrow this list, and 'Show removed' can hide a
  /// removed row, but the underlying rows are untouched, so clearing either
  /// brings everything back.
  List<SpreadsheetRow> get rows {
    final visible = controller.visibleRows;
    if (showRemoved) return visible;
    return visible.where((row) => !row.isRemoved).toList(growable: false);
  }

  /// Builds the grid the existing workbook view renders.
  WorkbookGrid build() {
    final shown = rows;
    final cells = <List<ParsedCell>>[];
    final styles = <String, WorkbookCellStyle>{};

    for (var rowIndex = 0; rowIndex < shown.length; rowIndex++) {
      final row = shown[rowIndex];
      final line = <ParsedCell>[];
      for (var column = 0; column < columnCount; column++) {
        // A cell covered by a merge belongs to its anchor, so it is not shown
        // twice and its value is never duplicated.
        if (controller.isCoveredByMerge(row, column)) {
          line.add(const ParsedCell.blank());
          continue;
        }
        final formula = controller.formulaAt(row, column);
        if (formula != null && formula.trim().isNotEmpty) {
          line.add(
            ParsedCell(
              text: formula.startsWith('=') ? formula : '=$formula',
              isFormula: true,
            ),
          );
        } else {
          final text = controller.cellText(row, column);
          final number = controller.cellNumber(row, column);
          line.add(
            ParsedCell(
              text: text,
              // A number is only claimed when the whole cell really is one, so
              // a supplier name that contains a digit stays text.
              number: text.trim() == (number?.toString() ?? '') ? number : null,
            ),
          );
        }
        final style = _styleOf(controller.formatAt(row, column));
        if (!style.isPlain) styles['$rowIndex#$column'] = style;
      }
      cells.add(line);
    }

    return WorkbookGrid(
      name: 'Spreadsheet',
      cells: cells,
      styles: styles,
      merges: _merges(shown),
    );
  }

  /// Routes a cell edit back into the controller, which owns validation and
  /// the edited/removed state.
  ///
  /// [rowIndex] is an index into the currently visible rows, so an edit always
  /// lands on the record the user is actually looking at. A cell inside a
  /// merged range is written through the merge's anchor, which is the only cell
  /// that actually holds the value.
  void setCell(int rowIndex, int column, String value) {
    final shown = rows;
    if (rowIndex < 0 || rowIndex >= shown.length) return;
    if (column < 0 || column >= columnCount) return;
    final row = shown[rowIndex];
    final keys = controller.rowKeys;
    final covering = controller.merges.mergeCovering(keys, rowIndex, column);
    controller.setCell(row, covering?.anchorColumn ?? column, value);
  }

  /// The sheet's merged ranges, translated from row keys into grid rows.
  ///
  /// A merge is skipped when either of its rows is not currently visible,
  /// because it cannot be drawn against rows that are not on screen.
  List<WorkbookMerge> _merges(List<SpreadsheetRow> shown) {
    final indexOf = <String, int>{};
    for (var index = 0; index < shown.length; index++) {
      indexOf[controller.rowKey(shown[index])] = index;
    }
    final merges = <WorkbookMerge>[];
    for (final merge in controller.merges.merges) {
      if (merge.isSingleCell) continue;
      final start = indexOf[merge.anchorRowKey];
      final end = indexOf[merge.endRowKey];
      if (start == null || end == null) continue;
      merges.add(
        WorkbookMerge(
          startRow: start,
          startColumn: merge.anchorColumn,
          endRow: end,
          endColumn: merge.endColumn,
        ),
      );
    }
    return merges;
  }

  /// Converts the controller's format into the grid's presentation.
  static WorkbookCellStyle _styleOf(CellFormat format) => WorkbookCellStyle(
    bold: format.bold,
    italic: format.italic,
    horizontalAlign: switch (format.alignment) {
      CellAlignment.center => 'center',
      CellAlignment.right => 'right',
      CellAlignment.left => null,
    },
    textColor: _hex(format.text?.argb),
    backgroundColor: _hex(format.background.argb),
  );

  static String? _hex(int? argb) {
    if (argb == null) return null;
    return argb.toRadixString(16).padLeft(8, '0').substring(2);
  }
}
