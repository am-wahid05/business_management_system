import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../imports/excel_cell_parser.dart';
import '../imports/workbook_grid_model.dart';
import '../spreadsheet/spreadsheet_clipboard.dart';

/// Matches a value that is *entirely* a number, so a name that merely contains
/// digits is not mistaken for one.
final RegExp _wholeNumber = RegExp(r'^[-+]?\d+(\.\d+)?$');

/// Classifies a value the user typed, so a cell keeps a sensible type.
///
/// A leading `=` is kept as formula text, which is exactly what the decoder
/// itself reports for a formula. A value that is wholly a number is stored as
/// one, so editing is not the same as converting every cell to text.
///
/// The whole-value check matters. [parseImportNumber] is written for a
/// spreadsheet cell that may carry a currency decoration, so it discards
/// anything it does not recognise and reads `Product/Service 1` as `1`. Using it
/// here would silently destroy a text cell the moment the user typed it, so a
/// number is only accepted when the *entire* value is numeric.
///
/// A date is deliberately not guessed from typed text, because `03/04` is
/// ambiguous; an imported date cell keeps its own type until the user
/// overwrites it.
ParsedCell classifyTypedCell(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return const ParsedCell.blank();
  if (text.startsWith('=')) return ParsedCell(text: text, isFormula: true);
  if (_wholeNumber.hasMatch(text)) {
    final number = double.tryParse(text);
    if (number != null && number.isFinite) {
      return ParsedCell(text: text, number: number);
    }
  }
  return ParsedCell(text: text);
}

/// Renders a worksheet as an Excel-style grid.
///
/// The sheet's own layout is the layout: there is no Date, Supplier or Weight
/// column here, and no header is assumed. A pinned column-letter header, a
/// pinned row-number gutter and a body of bordered cells scroll in both
/// directions, exactly as a worksheet does.
///
/// Only the rows on screen are built. The body and the gutter are two
/// [ListView.builder]s whose offsets are kept in step, so a sheet with tens of
/// thousands of rows scrolls without ever creating tens of thousands of widgets.
class WorkbookGridView extends StatefulWidget {
  const WorkbookGridView({
    required this.grid,
    required this.onEdit,
    this.selectedRow = 0,
    this.selectedColumn = 0,
    this.onSelectionChanged,
    this.selectionAnchor,
    this.onSelectCell,
    this.onMove,
    this.visibleRows,
    super.key,
  });

  final WorkbookGrid grid;

  /// Called with the cell position and the text the user typed.
  final void Function(int row, int column, String value) onEdit;

  final int selectedRow;
  final int selectedColumn;
  final VoidCallback? onSelectionChanged;

  /// The cell the selection was anchored on, so a range can be extended.
  final CellPosition? selectionAnchor;

  /// Reports a picked cell, with the anchor, so the caller owns the range.
  final void Function(CellPosition? anchor, CellPosition cell)? onSelectCell;

  /// Reports a keyboard move; [extend] keeps the anchor in place.
  final void Function(int row, int column, bool extend)? onMove;

  /// The rows to draw, as sheet row indexes.
  ///
  /// Filtering only changes what is drawn. The grid never removes a row, so
  /// clearing the filter brings the whole sheet back untouched.
  final List<int>? visibleRows;

  /// Blank rows kept below the data so the sheet can always be extended.
  static const int trailingBlankRows = 40;

  /// Blank columns kept to the right of the data.
  static const int trailingBlankColumns = 4;

  @override
  State<WorkbookGridView> createState() => _WorkbookGridViewState();
}
class _WorkbookGridViewState extends State<WorkbookGridView> {
  static const double _headerHeight = 28;
  static const double _gutterWidth = 48;
  static const double _cellWidth = 130;
  static const double _cellHeight = 30;

  /// Drives the cell body, the lazy list that holds the actual sheet.
  final ScrollController _body = ScrollController();

  /// Drives the row-number gutter. It is a separate lazy list, and its offset
  /// is kept equal to the body's so the numbers line up with their rows.
  final ScrollController _gutter = ScrollController();

  /// Drives horizontal scrolling, shared by the letter header and the body.
  final ScrollController _horizontal = ScrollController();

  final TextEditingController _editing = TextEditingController();
  final FocusNode _editorFocus = FocusNode();

  bool _editingCell = false;
  bool _syncingGutter = false;
  late int _selectedRow = widget.selectedRow;
  late int _selectedColumn = widget.selectedColumn;

  int get _rowCount =>
      widget.grid.rowCount + WorkbookGridView.trailingBlankRows;
  int get _columnCount =>
      widget.grid.columnCount + WorkbookGridView.trailingBlankColumns;

  /// The sheet rows that are actually drawn, in order.
  ///
  /// With a filter applied this is a subset of the sheet; without one it is
  /// every row. A row is never removed from the grid to satisfy a filter.
  late final List<int> _rows = () {
    final filter = widget.visibleRows;
    if (filter != null) return filter;
    return [for (var row = 0; row < _rowCount; row++) row];
  }();

  @override
  void initState() {
    super.initState();
    _body.addListener(_syncGutter);
  }

  @override
  void didUpdateWidget(covariant WorkbookGridView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedRow != widget.selectedRow) {
      _selectedRow = widget.selectedRow;
    }
    if (oldWidget.selectedColumn != widget.selectedColumn) {
      _selectedColumn = widget.selectedColumn;
    }
  }

  /// Keeps the row numbers beside the rows they label.
  void _syncGutter() {
    if (_syncingGutter || !_gutter.hasClients) return;
    _syncingGutter = true;
    _gutter.jumpTo(
      _body.offset.clamp(
        _gutter.position.minScrollExtent,
        _gutter.position.maxScrollExtent,
      ),
    );
    _syncingGutter = false;
  }

  @override
  void dispose() {
    _body.removeListener(_syncGutter);
    _body.dispose();
    _gutter.dispose();
    _horizontal.dispose();
    _editing.dispose();
    _editorFocus.dispose();
    super.dispose();
  }

  void _commitEdit() {
    if (!_editingCell) return;
    widget.onEdit(_selectedRow, _selectedColumn, _editing.text);
    setState(() => _editingCell = false);
  }

  void _select(int row, int column) {
    setState(() {
      _selectedRow = row;
      _selectedColumn = column;
    });
    widget.onSelectionChanged?.call();
  }

  /// Moves the selection without opening the editor, so the arrow keys browse
  /// the sheet the way they do in a spreadsheet.
  void _moveSelection(LogicalKeyboardKey key) {
    var row = _selectedRow;
    var column = _selectedColumn;
    if (key == LogicalKeyboardKey.arrowDown) {
      row = (row + 1).clamp(0, _rowCount - 1);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      row = (row - 1).clamp(0, _rowCount - 1);
    } else if (key == LogicalKeyboardKey.arrowRight) {
      column = (column + 1).clamp(0, _columnCount - 1);
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      column = (column - 1).clamp(0, _columnCount - 1);
    } else {
      row = (row + 1).clamp(0, _rowCount - 1);
    }
    _select(row, column);
    widget.onMove?.call(row, column, false);
  }

  void _beginEdit(int row, int column) {
    _editing.text = widget.grid.cellAt(row, column).text;
    setState(() => _editingCell = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_editingCell) return;
      _editorFocus.requestFocus();
      _editing.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _editing.text.length,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FocusScope(
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.escape && _editingCell) {
          setState(() => _editingCell = false);
          return KeyEventResult.handled;
        }
        if (_editingCell) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.arrowDown ||
            event.logicalKey == LogicalKeyboardKey.arrowUp ||
            event.logicalKey == LogicalKeyboardKey.arrowLeft ||
            event.logicalKey == LogicalKeyboardKey.arrowRight ||
            event.logicalKey == LogicalKeyboardKey.enter) {
          _moveSelection(event.logicalKey);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Column(
        children: [
          SizedBox(
            height: _headerHeight,
            child: Row(
              children: [
                _box(theme, '', width: _gutterWidth, header: true),
                Expanded(
                  child: SingleChildScrollView(
                    controller: _horizontal,
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (var column = 0; column < _columnCount; column++)
                          _box(
                            theme,
                            columnLetter(column),
                            width: _cellWidth,
                            header: true,
                            selected: column == _selectedColumn,
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // The gutter is its own lazy list kept in step with the body, so
                // it stays pinned left while the numbers scroll vertically.
                SizedBox(
                  width: _gutterWidth,
                  child: ListView.builder(
                    controller: _gutter,
                    itemCount: _rowCount,
                    itemExtentBuilder: (index, _) => _rowExtent(index),
                    itemBuilder: (context, index) {
                      final row = index < _rows.length ? _rows[index] : index;
                      return _box(
                        theme,
                        '${row + 1}',
                        width: _gutterWidth,
                        height: _rowExtent(index),
                        header: true,
                        selected: row == _selectedRow,
                      );
                    },
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    controller: _horizontal,
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: _cellWidth * _columnCount,
                      // Only the rows on screen are built, which is what keeps a
                      // long sheet responsive.
                      child: ListView.builder(
                        controller: _body,
                        itemCount: _rowCount,
                        itemExtentBuilder: (index, _) => _rowExtent(index),
                        itemBuilder: (context, index) {
                          final row = index < _rows.length
                              ? _rows[index]
                              : index;
                          return _row(theme, row);
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The height of one drawn row.
  ///
  /// A row that anchors a vertical merge is drawn taller, so the merged cell
  /// really does cover the rows beneath it. The body and the row-number gutter
  /// both ask this function, which is what keeps the numbers lined up with
  /// their rows even when a row is taller than the standard height.
  double _rowExtent(int index) {
    final row = index < _rows.length ? _rows[index] : index;
    var span = 1;
    for (var column = 0; column < _columnCount; column++) {
      if (widget.grid.mergeAnchorAt(row, column) != null) continue;
      final height = widget.grid.spanRows(row, column);
      if (height > span) span = height;
    }
    return _cellHeight * span;
  }

  Widget _row(ThemeData theme, int row) {
    final line = row < widget.grid.rowCount
        ? widget.grid.cells[row]
        : const <ParsedCell>[];
    return Row(
      children: [
        for (var column = 0; column < _columnCount; column++)
          _cell(theme, row, column, line),
      ],
    );
  }

  Widget _cell(
    ThemeData theme,
    int row,
    int column,
    List<ParsedCell> line,
  ) {
    final merge = widget.grid.mergeAt(row, column);
    // A cell inside a merge is covered by its anchor, so it is not drawn. The
    // value lives in the anchor only, and is never copied into these cells.
    if (merge != null && mergeAnchorIsNotThisCell(merge, row, column)) {
      return Container(
        width: _cellWidth,
        height: _cellHeight,
        decoration: BoxDecoration(
          border: Border.all(color: theme.dividerColor, width: 0.5),
        ),
      );
    }
    // A merged anchor is drawn as one box as wide and as tall as the range it
    // covers, which is what makes A1:D1 read as a single heading.
    final width = _cellWidth * widget.grid.spanColumns(row, column);
    final height = _rowExtent(row);
    // Tapping anywhere on a merged cell selects and edits its anchor.
    final anchor = merge == null
        ? (row, column)
        : (merge.startRow, merge.startColumn);
    final selected = row == _selectedRow && column == _selectedColumn;
    final editing = _editingCell &&
        anchor.$1 == _selectedRow &&
        anchor.$2 == _selectedColumn;
    final style = widget.grid.styleAt(anchor.$1, anchor.$2);
    final display = widget.grid.displayAt(anchor.$1, anchor.$2);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        _select(anchor.$1, anchor.$2);
        _beginEdit(anchor.$1, anchor.$2);
        widget.onSelectCell?.call(
          widget.selectionAnchor,
          CellPosition(anchor.$1, anchor.$2),
        );
      },
      child: Container(
        width: width,
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primaryContainer.withValues(alpha: 0.25)
              : _backgroundOf(theme, style),
          border: Border.all(color: theme.dividerColor, width: 0.5),
        ),
        child: editing
            ? TextField(
                controller: _editing,
                focusNode: _editorFocus,
                style: TextStyle(
                  fontSize: style?.fontSize?.toDouble() ?? 13,
                  fontWeight: style?.bold == true
                      ? FontWeight.bold
                      : FontWeight.normal,
                  fontStyle: style?.italic == true
                      ? FontStyle.italic
                      : FontStyle.normal,
                ),
                decoration: const InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
                onSubmitted: (_) => _commitEdit(),
              )
            : _cellText(theme, style, display.label, display.error != null),
      ),
    );
  }

  /// Whether this position is inside a merge but is not the cell that owns it.
  static bool mergeAnchorIsNotThisCell(
    WorkbookMerge merge,
    int row,
    int column,
  ) => !(merge.startRow == row && merge.startColumn == column);

  /// The fill the workbook gave a cell, or null for no fill.
  Color? _backgroundOf(ThemeData theme, WorkbookCellStyle? style) {
    final hex = style?.backgroundColor;
    if (hex == null || hex.length != 6 && hex.length != 8) return null;
    final value = int.tryParse(hex.length == 6 ? 'FF$hex' : hex, radix: 16);
    if (value == null) return null;
    return Color(value);
  }

  /// A colour the workbook wrote, or null to use the theme default.
  Color? _textColorOf(WorkbookCellStyle? style) {
    final hex = style?.textColor;
    if (hex == null || hex.length != 6 && hex.length != 8) return null;
    final value = int.tryParse(hex.length == 6 ? 'FF$hex' : hex, radix: 16);
    if (value == null) return null;
    return Color(value);
  }

  /// Draws a cell's value the way the sheet means it.
  ///
  /// [label] has already been recalculated for a supported formula and left as
  /// the original text for one the engine cannot evaluate, so a formula is never
  /// shown as a number it does not have.
  Widget _cellText(
    ThemeData theme,
    WorkbookCellStyle? style,
    String label,
    bool isFormula,
  ) {
    if (label.isEmpty) return const SizedBox.shrink();
    return Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: _textAlignOf(style),
      style: TextStyle(
        fontSize: style?.fontSize?.toDouble() ?? 13,
        fontWeight: style?.bold == true ? FontWeight.bold : FontWeight.normal,
        fontStyle: (style?.italic == true || isFormula)
            ? FontStyle.italic
            : FontStyle.normal,
        color: _textColorOf(style),
      ),
    );
  }

  static TextAlign? _textAlignOf(WorkbookCellStyle? style) {
    switch (style?.horizontalAlign) {
      case 'center':
        return TextAlign.center;
      case 'right':
        return TextAlign.right;
      default:
        return null;
    }
  }

  Widget _box(
    ThemeData theme,
    String label, {
    required double width,
    double height = 28,
    bool header = false,
    bool selected = false,
  }) => Container(
    width: width,
    height: height,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: header
          ? (selected
                ? theme.colorScheme.primaryContainer.withValues(alpha: 0.55)
                : theme.colorScheme.surfaceContainerHighest)
          : null,
      border: Border.all(color: theme.dividerColor, width: 0.5),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 12,
        fontWeight: header ? FontWeight.w600 : FontWeight.normal,
        color: theme.colorScheme.onSurfaceVariant,
      ),
    ),
  );
}

