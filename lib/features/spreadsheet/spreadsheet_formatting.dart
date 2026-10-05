import 'spreadsheet_clipboard.dart';

/// A small, controlled highlight palette.
///
/// This is deliberately a fixed set of business-friendly colours rather than a
/// free colour picker, and it is session-only: nothing here is stored against a
/// record, so no database change is needed.
enum CellColor { none, yellow, green, blue, red, orange, purple }

extension CellColorValue on CellColor {
  /// An ARGB value, or null for [CellColor.none].
  int? get argb => switch (this) {
    CellColor.none => null,
    CellColor.yellow => 0xFFFFF3B0,
    CellColor.green => 0xFFC8E6C9,
    CellColor.blue => 0xFFBBDEFB,
    CellColor.red => 0xFFEF9A9A,
    CellColor.orange => 0xFFFFCC80,
    CellColor.purple => 0xFFE1BEE7,
  };

  String get label => switch (this) {
    CellColor.none => 'No colour',
    CellColor.yellow => 'Yellow',
    CellColor.green => 'Green',
    CellColor.blue => 'Blue',
    CellColor.red => 'Red',
    CellColor.orange => 'Orange',
    CellColor.purple => 'Purple',
  };
}

/// How the text in a cell is aligned.
enum CellAlignment { left, center, right }

/// The visual formatting of a cell.
///
/// This is spreadsheet session state held in memory only. It is never written
/// to a delivery record, so formatting can never change stored business data.
class CellFormat {
  const CellFormat({
    this.background = CellColor.none,
    this.text,
    this.bold = false,
    this.italic = false,
    this.alignment = CellAlignment.left,
  });

  final CellColor background;

  /// An optional text colour, from the same controlled palette.
  final CellColor? text;
  final bool bold;
  final bool italic;
  final CellAlignment alignment;

  bool get isPlain =>
      background == CellColor.none &&
      text == null &&
      !bold &&
      !italic &&
      alignment == CellAlignment.left;

  CellFormat copyWith({
    CellColor? background,
    CellColor? text,
    bool clearText = false,
    bool? bold,
    bool? italic,
    CellAlignment? alignment,
  }) => CellFormat(
    background: background ?? this.background,
    text: clearText ? null : (text ?? this.text),
    bold: bold ?? this.bold,
    italic: italic ?? this.italic,
    alignment: alignment ?? this.alignment,
  );

  Map<Object, Object?> toMap() => {
    'background': background.name,
    if (text != null) 'text': text!.name,
    if (bold) 'bold': true,
    if (italic) 'italic': true,
    if (alignment != CellAlignment.left) 'alignment': alignment.name,
  };

  static CellFormat fromMap(Map<Object?, Object?> map) => CellFormat(
    background: CellColor.values.firstWhere(
      (value) => value.name == map['background'],
      orElse: () => CellColor.none,
    ),
    text: map['text'] == null
        ? null
        : CellColor.values.firstWhere(
            (value) => value.name == map['text'],
            orElse: () => CellColor.none,
          ),
    bold: map['bold'] == true,
    italic: map['italic'] == true,
    alignment: CellAlignment.values.firstWhere(
      (value) => value.name == map['alignment'],
      orElse: () => CellAlignment.left,
    ),
  );
}

/// Holds the copy buffer and the formatting for the current session.
class SpreadsheetClipboard {
  ClipboardBlock? _block;
  final Map<CellPosition, CellFormat> _formats = {};

  /// The most recently copied block, or null when nothing has been copied.
  ClipboardBlock? get block => _block;

  bool get hasContent => _block != null;

  /// Copies a rectangle of cell text.
  void copy(CellRange range, List<List<String>> values) {
    _block = ClipboardBlock.of(range, values);
  }

  /// Clears the copy buffer.
  void clear() {
    _block = null;
  }

  CellFormat formatAt(CellPosition position) =>
      _formats[position] ?? const CellFormat();

  /// Applies a format to every cell in a range.
  void format(CellRange range, CellFormat Function(CellFormat current) change) {
    for (var row = range.startRow; row <= range.endRow; row++) {
      for (
        var column = range.startColumn;
        column <= range.endColumn;
        column++
      ) {
        final position = CellPosition(row, column);
        final updated = change(formatAt(position));
        if (updated.isPlain) {
          _formats.remove(position);
        } else {
          _formats[position] = updated;
        }
      }
    }
  }

  /// The formats for the current sheet, so a reload cannot carry stale colours
  /// onto different records.
  Map<CellPosition, CellFormat> get formats =>
      Map<CellPosition, CellFormat>.unmodifiable(_formats);

  void clearFormatting() => _formats.clear();
}
