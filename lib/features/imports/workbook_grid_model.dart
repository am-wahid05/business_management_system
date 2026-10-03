import '../spreadsheet/spreadsheet_clipboard.dart';
import '../spreadsheet/spreadsheet_formula.dart';
import 'excel_cell_parser.dart';

/// Turns a zero-based column index into its spreadsheet letter.
///
/// 0 is A, 25 is Z, 26 is AA. This is the same bijective base-26 Excel uses, so
/// the header of a column always matches the letter shown in the file the user
/// is looking at.
String columnLetter(int index) {
  if (index < 0) return '';
  var value = index;
  final buffer = StringBuffer();
  while (value >= 0) {
    buffer.write(String.fromCharCode(65 + value % 26));
    value = value ~/ 26 - 1;
  }
  return buffer.toString().split('').reversed.join();
}

/// The one-based spreadsheet address of a cell, such as `B7`.
String cellAddress(int row, int column) => '${columnLetter(column)}${row + 1}';

/// A merged rectangle carried over from the workbook.
class WorkbookMerge {
  const WorkbookMerge({
    required this.startRow,
    required this.startColumn,
    required this.endRow,
    required this.endColumn,
  });

  final int startRow;
  final int startColumn;
  final int endRow;
  final int endColumn;

  bool contains(int row, int column) =>
      row >= startRow &&
      row <= endRow &&
      column >= startColumn &&
      column <= endColumn;

  /// True when the merge covers more than the single cell it anchors on.
  bool get isSpanned =>
      startRow != endRow || startColumn != endColumn;

  Map<String, Object?> toJson() => {
    'r': startRow,
    'c': startColumn,
    'r2': endRow,
    'c2': endColumn,
  };

  static WorkbookMerge fromJson(Map<String, Object?> json) => WorkbookMerge(
    startRow: (json['r']! as num).toInt(),
    startColumn: (json['c']! as num).toInt(),
    endRow: (json['r2']! as num).toInt(),
    endColumn: (json['c2']! as num).toInt(),
  );
}

/// One worksheet read as a spreadsheet, in its original shape.
///
/// This is deliberately *not* the delivery-shaped [ImportSheet] the business
/// importer builds. Nothing here assumes a header row, a date column or a
/// supplier column: row 0 is whatever the user wrote in row 1, blank rows are
/// kept because their position is part of the sheet, and every cell keeps the
/// type the decoder reported.
class WorkbookGrid {
  WorkbookGrid({
    required this.name,
    required this._cells,
    this.merges = const [],
    Map<String, WorkbookCellStyle> styles = const {},
    this.sourceFilename = '',
  }) : styles = Map<String, WorkbookCellStyle>.of(styles);

  /// The worksheet name shown in the file's tab.
  final String name;

  /// The file this grid came from, used only to key the saved copy.
  final String sourceFilename;

  final List<List<ParsedCell>> _cells;

  /// Merged ranges the workbook declared, rendered as one spanned cell.
  final List<WorkbookMerge> merges;

  /// The presentation the workbook gave individual cells, keyed `'row#column'`.
  ///
  /// Only cells the workbook actually styled are present, so an unstyled sheet
  /// costs nothing.
  final Map<String, WorkbookCellStyle> styles;
  List<List<ParsedCell>> get cells => _cells;

  int get rowCount => _cells.length;

  /// The widest row. The grid is always at least as wide as this, so a sheet
  /// whose last column is narrow still has somewhere to type.
  int get columnCount => _cells.fold<int>(0, (wide, row) => row.length > wide ? row.length : wide);

  /// The cell at a position, or a blank cell outside the used range.
  ///
  /// Callers may address any row or column, so a grid can be navigated and
  /// edited past the data the file happened to contain.
  ParsedCell cellAt(int row, int column) {
    if (row < 0 || row >= _cells.length) return const ParsedCell.blank();
    final line = _cells[row];
    if (column < 0 || column >= line.length) return const ParsedCell.blank();
    return line[column];
  }

  void setCell(int row, int column, ParsedCell cell) {
    while (_cells.length <= row) {
      _cells.add(<ParsedCell>[]);
    }
    final line = _cells[row];
    while (line.length <= column) {
      line.add(const ParsedCell.blank());
    }
    line[column] = cell;
  }

  /// The merge covering a cell, or null when it is not inside one.
  WorkbookMerge? mergeAt(int row, int column) {
    for (final merge in merges) {
      if (merge.contains(row, column)) return merge;
    }
    return null;
  }

  /// The cell that owns a merged range.
  ///
  /// Editing or styling a cell inside a merge means editing its anchor, which is
  /// the only cell that actually holds the value.
  WorkbookMerge? mergeAnchorAt(int row, int column) {
    final merge = mergeAt(row, column);
    if (merge == null) return null;
    if (merge.startRow == row && merge.startColumn == column) return null;
    return merge;
  }

  /// How many columns the cell at [row]/[column] occupies, counting any merge.
  int spanColumns(int row, int column) {
    final merge = mergeAt(row, column);
    if (merge == null) return 1;
    return merge.endColumn - merge.startColumn + 1;
  }

  /// How many rows the cell at [row]/[column] occupies, counting any merge.
  int spanRows(int row, int column) {
    final merge = mergeAt(row, column);
    if (merge == null) return 1;
    return merge.endRow - merge.startRow + 1;
  }

  /// The presentation the workbook gave a cell.
  WorkbookCellStyle? styleAt(int row, int column) => styles[_key(row, column)];

  /// Records the presentation for a cell, replacing anything already there.
  void setStyle(int row, int column, WorkbookCellStyle? style) {
    final key = _key(row, column);
    if (style == null) {
      styles.remove(key);
    } else {
      styles[key] = style;
    }
  }

  static String _key(int row, int column) => '$row#$column';

  /// The grid the formula engine reads values from.
  ///
  /// The engine is display-only: it never writes a result back into a cell, so
  /// evaluating a formula can never turn one into an official business value.
  FormulaGrid get formulaGrid => _GridFormulaSource(this);

  /// Evaluates a cell's formula, or returns the cell itself when it is not one.
  ///
  /// A formula the engine does not understand is never replaced with a wrong
  /// value or with zero: the original text stays exactly as the workbook wrote
  /// it, and the caller is told the evaluation failed.
  FormulaResult evaluateAt(int row, int column) {
    final cell = cellAt(row, column);
    if (!cell.isFormula) return FormulaResult.literal(cell.text);
    // The recovered expression is preferred over the cell's display text, which
    // for a formula is a result rather than something to calculate.
    final expression = cell.formula == null
        ? cell.text
        : '=${cell.formula}';
    return FormulaEvaluator(formulaGrid).evaluate(expression);
  }

  /// The text a cell should display, recalculating a supported formula.
  ///
  /// The order is deliberate and matches what a spreadsheet shows:
  ///
  ///  1. a formula the existing engine can evaluate, so an edit to an input is
  ///     reflected straight away;
  ///  2. otherwise the cached result Excel itself stored, so an unsupported
  ///     formula such as `VLOOKUP` reads as the value the user saw rather than
  ///     as an expression;
  ///  3. otherwise the original formula text, which is never replaced with a
  ///     zero or an invented number.
  ({String label, FormulaError? error}) displayAt(int row, int column) {
    final cell = cellAt(row, column);
    if (cell.date != null) {
      return (label: formatImportDate(cell.date!), error: null);
    }
    if (!cell.isFormula) {
      if (cell.number != null) {
        return (label: formatImportNumber(cell.number!), error: null);
      }
      return (label: cell.text, error: null);
    }
    final result = evaluateAt(row, column);
    if (!result.isFailure) {
      final value = result.value;
      if (value != null) {
        return (label: formatImportNumber(value), error: null);
      }
      final text = result.text;
      if (text != null && text.isNotEmpty) {
        return (label: text, error: null);
      }
    }
    // The engine could not do it, so Excel's own result is shown, and failing
    // that the formula itself.
    return (label: cell.displayText ?? cell.text, error: result.error);
  }

  /// Whether every formula on the sheet is one this engine understands.
  ///
  /// Sorting or filtering rows reorders what a relative reference points at, so
  /// a sheet that mixes supported and unsupported formulas is left alone.
  bool get hasUnsupportedFormulas {
    for (final row in _cells) {
      for (final cell in row) {
        if (!cell.isFormula) continue;
        if (evaluateAtFormulaOnly(cell.text).isFailure) return true;
      }
    }
    return false;
  }

  /// Evaluates a formula string without a grid, used to classify it.
  ///
  /// A function name the engine does not know is detected from the text, so
  /// this never has to resolve a single cell reference.
  static FormulaResult evaluateAtFormulaOnly(String formula) {
    final body = formula.trim();
    if (!body.startsWith('=')) {
      return FormulaResult.literal(body);
    }
    final inner = body.substring(1).trim();
    final call = RegExp(r'^([A-Za-z]+)\(').firstMatch(inner);
    // `FormulaResult.literal` is a factory that interpolates its value, so it
    // cannot be const. `FormulaResult.failure` is a real const constructor and
    // stays const.
    if (call == null) return FormulaResult.literal('');
    const supported = {'SUM', 'AVERAGE', 'COUNT', 'MIN', 'MAX'};
    return supported.contains(call.group(1)!.toUpperCase())
        ? FormulaResult.literal('')
        : const FormulaResult.failure(FormulaError.unknownFunction);
  }

  /// Finds every cell whose displayed value contains [query].
  ///
  /// The displayed value is searched rather than the raw cell, so a number, a
  /// date and a recalculated formula are all found by what the user can see.
  /// An empty query matches nothing rather than everything, so a cleared search
  /// box does not suddenly highlight the whole sheet.
  List<CellPosition> search(String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return const [];
    final hits = <CellPosition>[];
    for (var row = 0; row < rowCount; row++) {
      for (var column = 0; column < columnCount; column++) {
        if (mergeAnchorAt(row, column) != null) continue;
        final label = displayAt(row, column).label;
        if (label.isEmpty) continue;
        if (label.toLowerCase().contains(needle)) {
          hits.add(CellPosition(row, column));
        }
      }
    }
    return hits;
  }

  /// The rows a filter should show, as sheet row indexes.
  ///
  /// Filtering never removes or changes a row: this only decides what the view
  /// draws, so clearing the filter brings the whole sheet back untouched. With
  /// no [query] every row is visible.
  List<int> visibleRows({String query = '', int? column}) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty || column == null) {
      return [for (var row = 0; row < rowCount; row++) row];
    }
    return [
      for (var row = 0; row < rowCount; row++)
        if (displayAt(row, column).label.toLowerCase().contains(needle)) row,
    ];
  }

  /// Why sorting is unavailable on this sheet, or null when it is safe.
  ///
  /// A merge spans cells that belong together, and the styles are stored by row
  /// position, so reordering rows would either tear a merge apart or attach a
  /// heading's formatting to the wrong data. Rather than quietly corrupting
  /// either, sorting is refused and this explains why.
  String? get sortBlockedReason {
    if (merges.isNotEmpty) {
      return 'Sorting is unavailable because this sheet has merged cells.';
    }
    if (styles.isNotEmpty) {
      return 'Sorting is unavailable because this sheet has formatted cells.';
    }
    if (hasUnsupportedFormulas) {
      return 'Sorting is unavailable because this sheet has formulas that '
          'cannot be recalculated, so reordering rows would change their '
          'meaning.';
    }
    return null;
  }

  /// Sorts the sheet in place by one column.
  ///
  /// Returns false and changes nothing when [sortBlockedReason] explains why the
  /// sheet cannot be reordered safely.
  bool sortByColumn(int column, {bool ascending = true}) {
    if (sortBlockedReason != null) return false;
    final sorted = [..._cells]..sort((left, right) {
        final a = _sortKey(left, column);
        final b = _sortKey(right, column);
        final compared = _compareSortKeys(a, b);
        return ascending ? compared : -compared;
      });
    _cells
      ..clear()
      ..addAll(sorted);
    return true;
  }

  /// Numbers sort before text, and blanks last, which is what a spreadsheet does.
  (int, double, String) _sortKey(List<ParsedCell> row, int column) {
    final cell = column < row.length ? row[column] : const ParsedCell.blank();
    if (cell.isBlank) return (2, 0, '');
    if (cell.number != null) return (0, cell.number!, '');
    final text = cell.isFormula ? cell.text : cell.text;
    return (1, 0, text.toLowerCase());
  }

  static int _compareSortKeys((int, double, String) a, (int, double, String) b) {
    if (a.$1 != b.$1) return a.$1.compareTo(b.$1);
    if (a.$1 == 0) return a.$2.compareTo(b.$2);
    return a.$3.compareTo(b.$3);
  }

  /// Copies a rectangle of cells, preserving what each one holds.
  ///
  /// Only the rectangle is taken, so a paste can never bring extra cells with
  /// it. A cell inside a merge copies as blank, because the value of a merge
  /// belongs to its anchor and pasting a second copy would duplicate it.
  WorkbookClipboard copyRange(CellRange range) => WorkbookClipboard(
    [
      for (var row = range.startRow; row <= range.endRow; row++)
        [
          for (
            var column = range.startColumn;
            column <= range.endColumn;
            column++
          )
            if (mergeAnchorAt(row, column) != null)
              const ParsedCell.blank()
            else
              cellAt(row, column),
        ],
    ],
    sourceRow: range.startRow,
    sourceColumn: range.startColumn,
  );

  /// Pastes a copied block with its top-left corner at the target.
  ///
  /// A copied formula has its relative references moved by the same distance it
  /// was pasted, the way Excel does. A reference written with a `$` is absolute
  /// and is left alone. If any reference would fall off the sheet, the formula
  /// is pasted exactly as it was copied rather than being rewritten into
  /// something wrong.
  ///
  /// Returns how many cells were written.
  int pasteClipboard(WorkbookClipboard clipboard, int targetRow, int targetColumn) {
    if (clipboard.rowCount == 0) return 0;
    // The shift is the distance from where the block was copied, not from
    // column A, so a formula copied from C keeps its true offset.
    final deltaRow = targetRow - clipboard.sourceRow;
    final deltaColumn = targetColumn - clipboard.sourceColumn;
    var written = 0;
    for (var row = 0; row < clipboard.rowCount; row++) {
      for (var column = 0; column < clipboard.columnCount; column++) {
        final source = clipboard.cells[row][column];
        if (source.isBlank && !source.isFormula) continue;
        final cell = source.isFormula
            ? ParsedCell(
                text: _shiftFormula(source.text, deltaRow, deltaColumn),
                isFormula: true,
              )
            : source;
        setCell(targetRow + row, targetColumn + column, cell);
        written++;
      }
    }
    return written;
  }

  /// Moves a formula's relative references by a row and column offset.
  ///
  /// Only references without a `$` are moved. If a reference would become zero
  /// or negative, or would point outside the sheet, the original text is
  /// returned unchanged: a formula that is slightly wrong about its position is
  /// better than one that silently points somewhere else.
  static String _shiftFormula(String formula, int deltaRow, int deltaColumn) {
    if (deltaRow == 0 && deltaColumn == 0) return formula;
    var outOfBounds = false;
    final shifted = formula.replaceAllMapped(
      RegExp(r'(\$?)([A-Za-z]{1,3})(\$?)(\d+)'),
      (match) {
        final columnAbsolute = match.group(1)!.isNotEmpty;
        final rowAbsolute = match.group(3)!.isNotEmpty;
        final column = _lettersToIndex(match.group(2)!);
        final row = int.tryParse(match.group(4)!);
        if (column == null || row == null) return match.group(0)!;
        final newColumn = columnAbsolute ? column : column + deltaColumn;
        final newRow = rowAbsolute ? row : row + deltaRow;
        if (newColumn < 0 || newRow < 1) {
          outOfBounds = true;
          return match.group(0)!;
        }
        return '${match.group(1)}${columnLetter(newColumn)}'
            '${match.group(3)}$newRow';
      },
    );
    return outOfBounds ? formula : shifted;
  }

  static int? _lettersToIndex(String letters) {
    if (letters.isEmpty) return null;
    var value = 0;
    for (final code in letters.toUpperCase().codeUnits) {
      if (code < 65 || code > 90) return null;
      value = value * 26 + (code - 64);
    }
    return value - 1;
  }

  /// Serialised form used to persist an edited grid.
  List<List<Object?>> toJsonCells() => _cells
      .map(
        (row) => row
            .map(
              (cell) => {
                't': cell.text,
                if (cell.number != null) 'n': cell.number,
                if (cell.date != null) 'd': cell.date!.toIso8601String(),
                if (cell.isFormula) 'f': true,
                // A formula and its cached result are both kept, so reopening a
                // saved sheet still shows the value and still holds the formula.
                if (cell.formula != null) 'fx': cell.formula,
                if (cell.cachedText != null) 'cv': cell.cachedText,
              },
            )
            .toList(),
      )
      .toList();

  static WorkbookGrid fromJson({
    required String name,
    required String sourceFilename,
    required List<Object?> raw,
    List<Object?> rawMerges = const [],
    Map<String, Object?> rawStyles = const {},
  }) {
    final cells = <List<ParsedCell>>[];
    for (final line in raw) {
      final parsed = <ParsedCell>[];
      for (final entry in (line as List<Object?>)) {
        final map = (entry as Map<String, Object?>?) ?? const {};
        final dateText = map['d'] as String?;
        parsed.add(
          ParsedCell(
            text: (map['t'] as String?) ?? '',
            number: (map['n'] as num?)?.toDouble(),
            date: dateText == null ? null : DateTime.tryParse(dateText),
            isFormula: map['f'] == true,
            formula: map['fx'] as String?,
            cachedText: map['cv'] as String?,
          ),
        );
      }
      cells.add(parsed);
    }
    return WorkbookGrid(
      name: name,
      sourceFilename: sourceFilename,
      cells: cells,
      merges: [
        for (final entry in rawMerges)
          WorkbookMerge.fromJson(
            (entry as Map<String, Object?>?) ?? const {},
          ),
      ],
      styles: {
        for (final entry in rawStyles.entries)
          entry.key: WorkbookCellStyle.fromJson(
            (entry.value as Map<String, Object?>?) ?? const {},
          ),
      },
    );
  }
}

/// All worksheets of one imported file.
class WorkbookGridBook {
  const WorkbookGridBook({required this.filename, required this.sheets});

  final String filename;
  final List<WorkbookGrid> sheets;
}

/// A rectangular block of copied cells, with their types intact.
///
/// This keeps [ParsedCell] rather than plain text, so copying and pasting a
/// number or a formula does not turn it into a string on the way through.
class WorkbookClipboard {
  const WorkbookClipboard(
    this.cells, {
    this.sourceRow = 0,
    this.sourceColumn = 0,
  });

  final List<List<ParsedCell>> cells;

  /// Where the block was copied from.
  ///
  /// A pasted formula moves by the distance between this and the paste target,
  /// so the origin has to travel with the block. Without it a formula copied
  /// from column C would be shifted as though it had been copied from column A.
  final int sourceRow;
  final int sourceColumn;

  int get rowCount => cells.length;
  int get columnCount => cells.isEmpty ? 0 : cells.first.length;

  /// The block as tab-separated text, for the system clipboard.
  ///
  /// This is the plain-text form every other application understands; the typed
  /// cells above are what the grid itself pastes with.
  String get toText => [
    for (final row in cells)
      [for (final cell in row) cell.text].join('\t'),
  ].join('\n');
}

/// The presentation the workbook gave one cell.
///
/// Only attributes the decoder exposes safely are carried across, and only when
/// they differ from the plain default, so an unstyled sheet stays empty.
class WorkbookCellStyle {
  const WorkbookCellStyle({
    this.bold = false,
    this.italic = false,
    this.fontSize,
    this.horizontalAlign,
    this.verticalAlign,
    this.textColor,
    this.backgroundColor,
  });

  final bool bold;
  final bool italic;
  final int? fontSize;

  /// 'left', 'center', 'right' or 'general', as the workbook wrote it.
  final String? horizontalAlign;

  /// 'top', 'center' or 'bottom'.
  final String? verticalAlign;

  /// The font colour as a 6 or 8 digit hex string, without a leading `#`.
  final String? textColor;

  /// The fill colour as a 6 or 8 digit hex string, without a leading `#`.
  final String? backgroundColor;

  /// True when there is nothing to draw, so the cell can be skipped entirely.
  bool get isPlain =>
      !bold &&
      !italic &&
      fontSize == null &&
      horizontalAlign == null &&
      verticalAlign == null &&
      textColor == null &&
      backgroundColor == null;

  /// A copy of this style with some fields changed.
  ///
  /// Every nullable field takes a `clear` flag, because passing `null` on its own
  /// is indistinguishable from "leave it alone". That matters for font size:
  /// stepping a cell back down to the plain default has to actually *remove* the
  /// size rather than leave the old number in place.
  WorkbookCellStyle copyWith({
    bool? bold,
    bool? italic,
    int? fontSize,
    bool clearFontSize = false,
    String? horizontalAlign,
    bool clearHorizontalAlign = false,
    String? verticalAlign,
    bool clearVerticalAlign = false,
    String? textColor,
    bool clearTextColor = false,
    String? backgroundColor,
    bool clearBackgroundColor = false,
  }) => WorkbookCellStyle(
    bold: bold ?? this.bold,
    italic: italic ?? this.italic,
    fontSize: clearFontSize ? null : (fontSize ?? this.fontSize),
    horizontalAlign: clearHorizontalAlign
        ? null
        : (horizontalAlign ?? this.horizontalAlign),
    verticalAlign: clearVerticalAlign ? null : (verticalAlign ?? this.verticalAlign),
    textColor: clearTextColor ? null : (textColor ?? this.textColor),
    backgroundColor: clearBackgroundColor
        ? null
        : (backgroundColor ?? this.backgroundColor),
  );

  Map<String, Object?> toJson() => {
    if (bold) 'b': true,
    if (italic) 'i': true,
    if (fontSize != null) 's': fontSize,
    if (horizontalAlign != null) 'h': horizontalAlign,
    if (verticalAlign != null) 'v': verticalAlign,
    if (textColor != null) 'tc': textColor,
    if (backgroundColor != null) 'bc': backgroundColor,
  };

  static WorkbookCellStyle fromJson(Map<String, Object?> json) =>
      WorkbookCellStyle(
        bold: json['b'] == true,
        italic: json['i'] == true,
        fontSize: (json['s'] as num?)?.toInt(),
        horizontalAlign: json['h'] as String?,
        verticalAlign: json['v'] as String?,
        textColor: json['tc'] as String?,
        backgroundColor: json['bc'] as String?,
      );
}

/// Feeds the existing formula engine from a workbook grid.
///
/// This is an adapter, not a second engine: [FormulaEvaluator] does all the
/// parsing and arithmetic, exactly as the Admin Spreadsheet already uses it.
class _GridFormulaSource implements FormulaGrid {
  const _GridFormulaSource(this._grid);

  final WorkbookGrid _grid;

  @override
  int get rowCount => _grid.rowCount;

  @override
  int get columnCount => _grid.columnCount;

  @override
  double? numberAt(int row, int column) {
    final cell = _grid.cellAt(row, column);
    if (cell.number != null) return cell.number;
    // A referenced formula contributes its own result, so a formula can be
    // built on another formula the way it is in a spreadsheet.
    if (cell.isFormula) {
      final result = _grid.evaluateAt(row, column);
      if (result.isFailure) return null;
      return result.value;
    }
    return null;
  }

  @override
  String textAt(int row, int column) => _grid.displayAt(row, column).label;
}

