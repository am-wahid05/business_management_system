import 'package:excel/excel.dart';

import '../../domain/models/delivery.dart';

/// Reads a Record Type cell into a [DeliveryRecordType].
///
/// Only an explicit "bulk" wording selects a weighing-bridge record. Anything
/// else, including a blank cell, means individual, so a workbook without a
/// Record Type column behaves exactly as it did before this field existed.
DeliveryRecordType parseImportRecordType(String? value) {
  final text = (value ?? '').trim().toLowerCase();
  if (text.isEmpty) return DeliveryRecordType.individual;
  if (text == 'bulk' ||
      text == 'bulk / weighing bridge' ||
      text == 'weighing bridge' ||
      text == 'bulk weighing' ||
      text == 'bridge') {
    return DeliveryRecordType.bulk;
  }
  return DeliveryRecordType.individual;
}

/// A single spreadsheet cell converted into a shape the import can validate.
///
/// The previous implementation called `toString()` on every cell. That throws
/// away the cell type, which is why workbooks created outside this application
/// failed to import: a native date cell stringifies to a UTC ISO timestamp
/// (`2026-09-26T00:00:00.000Z`), which silently shifts the day for any device
/// that is not on UTC, and a formula cell stringifies to formula text.
class ParsedCell {
  const ParsedCell({
    required this.text,
    this.number,
    this.date,
    this.isFormula = false,
    this.formula,
    this.cachedText,
  });

  /// A cell with no value at all.
  const ParsedCell.blank()
    : text = '',
      number = null,
      date = null,
      isFormula = false,
      formula = null,
      cachedText = null;

  /// The cell contents as text, for display and for editable drafts.
  ///
  /// A native date is formatted as `dd/MM/yyyy` so the value the user sees in
  /// the preview is exactly the value that will be stored.
  final String text;

  /// The numeric value, when the cell was stored as a number.
  final double? number;

  /// The date, when the cell was stored as a date. Always a *local* DateTime
  /// built from the calendar fields Excel stored, so no timezone is applied.
  final DateTime? date;

  /// True when the cell holds a formula rather than a literal value.
  final bool isFormula;

  /// The formula Excel wrote, without the leading `=`.
  ///
  /// This is kept alongside [cachedText] so a formula cell never has to choose
  /// between showing its expression and showing what it evaluated to.
  final String? formula;

  /// The result Excel stored for [formula], read from the worksheet XML.
  ///
  /// Null when the workbook has no cached result for the cell.
  final String? cachedText;

  /// What the cell should display, in the order a spreadsheet uses.
  ///
  /// A formula the caller can already calculate wins, because it follows a live
  /// edit. Otherwise the value Excel itself stored is shown, so an unsupported
  /// formula reads as its result rather than as an expression. The formula text
  /// is the last resort, and is never replaced by a guess.
  String? get displayText {
    if (!isFormula) return text;
    final cached = cachedText;
    if (cached == null || cached.trim().isEmpty) {
      return formula ?? text;
    }
    return cached;
  }

  bool get isBlank => text.trim().isEmpty;

  /// Reads the cell as a date.
  ///
  /// [allowSerial] should only be set for a column that is known to hold
  /// dates: a bare number is ambiguous (50240 is both a plausible weight and a
  /// plausible Excel serial date), so the caller supplies the column context.
  DateTime? asDate({bool allowSerial = false}) =>
      date ?? parseImportDate(text, allowSerial: allowSerial);

  /// Reads the cell as a number, tolerating thousands separators.
  double? asNumber() => number ?? parseImportNumber(text);
}

/// Converts any [CellValue] into a [ParsedCell] without losing its type.
ParsedCell parseCellValue(CellValue? value) {
  if (value == null) return const ParsedCell.blank();
  if (value is DateCellValue) {
    // asDateTimeLocal() keeps the calendar fields Excel stored. The UTC
    // variant used by toString() is what caused the off-by-one-day bug.
    final local = value.asDateTimeLocal();
    return ParsedCell(
      text: _formatDateAndTime(local),
      date: local,
    );
  }
  if (value is DateTimeCellValue) {
    final local = value.asDateTimeLocal();
    return ParsedCell(
      text: _formatDateAndTime(local, hasSeconds: true),
      date: local,
    );
  }
  if (value is IntCellValue) {
    return ParsedCell(
      text: value.value.toString(),
      number: value.value.toDouble(),
    );
  }
  if (value is DoubleCellValue) {
    return ParsedCell(text: formatImportNumber(value.value), number: value.value);
  }
  if (value is BoolCellValue) {
    return ParsedCell(text: value.value ? 'true' : 'false');
  }
  if (value is FormulaCellValue) {
    // The excel package stores the cached result of a formula in this field,
    // so the cached value is still importable. It is flagged so the preview
    // can show that the cell is derived rather than typed.
    return ParsedCell(text: value.formula.trim(), isFormula: true);
  }
  // TextCellValue, and anything added by a newer package version.
  return ParsedCell(text: value.toString());
}

/// Parses a date written as text.
///
/// Supported: ISO-8601, `dd/MM/yyyy`, `dd-MM-yyyy`, `dd.MM.yyyy`, `d/M/yy`,
/// and `MM/dd/yyyy` where the day is greater than 12 and so cannot be a month.
/// An ambiguous `03/04/2026` is read as `dd/MM` (Ghanaian convention).
///
/// Returns a local [DateTime] built from the written calendar fields, so the
/// stored date is always the date shown in the spreadsheet.
DateTime? parseImportDate(String raw, {bool allowSerial = false}) {
  final text = raw.trim();
  if (text.isEmpty) return null;

  if (allowSerial) {
    final serial = parseImportNumber(text);
    if (serial != null) return excelSerialToDate(serial);
  }

  // ISO-8601. The calendar fields are taken as written rather than converted
  // from UTC, so a trailing `Z` can never move the date.
  final iso = DateTime.tryParse(text);
  if (iso != null) return _buildDate(iso.year, iso.month, iso.day);

  final match = RegExp(
    r'^(\d{1,4})\s*[/\-.]\s*(\d{1,2})\s*[/\-.]\s*(\d{1,4})$',
  ).firstMatch(text);
  if (match == null) return null;

  final firstText = match.group(1)!;
  final first = int.parse(firstText);
  final second = int.parse(match.group(2)!);
  final last = int.parse(match.group(3)!);

  int year;
  int month;
  int day;
  if (firstText.length == 4) {
    // Already year-first, e.g. 2026-09-26.
    year = first;
    month = second;
    day = last;
  } else if (first > 12) {
    // Unambiguously day-first, e.g. 26/09/2026.
    day = first;
    month = second;
    year = _expandYear(last);
  } else if (second > 12) {
    // Unambiguously month-first, e.g. 09/26/2026.
    month = first;
    day = second;
    year = _expandYear(last);
  } else {
    // Ambiguous, so the local day-first convention is used.
    day = first;
    month = second;
    year = _expandYear(last);
  }
  return _buildDate(year, month, day);
}

/// Parses a number written as text, ignoring thousands separators and
/// surrounding whitespace: `50240`, `50,240` and `50,240.5` all parse.
double? parseImportNumber(String raw) {
  var text = raw.trim();
  if (text.isEmpty) return null;
  // Remove grouping separators: commas, apostrophes, underscores and spaces
  // (including non-breaking ones). The decimal point is left alone.
  text = text.replaceAll(RegExp(r"[\s\u00a0',_]"), '');
  // Then drop any leading currency or other decoration, and anything trailing.
  text = text.replaceAll(RegExp(r'^[^\d\-+.]+'), '');
  text = text.replaceAll(RegExp(r'[^\d\-+.]+$'), '');
  if (text.isEmpty) return null;
  return double.tryParse(text);
}

/// Formats a parsed date cell, keeping the time of day when the cell has one.
///
/// A date cell that stores a time must not be flattened to a bare date, or the
/// recorded time of a delivery is silently lost. Midnight is written as a date
/// alone so a plain date cell still reads cleanly.
String _formatDateAndTime(DateTime date, {bool hasSeconds = false}) {
  final datePart = formatImportDate(date);
  if (date.hour == 0 && date.minute == 0 && (date.second == 0 || !hasSeconds)) {
    return datePart;
  }
  final time = '${date.hour.toString().padLeft(2, '0')}:'
      '${date.minute.toString().padLeft(2, '0')}';
  return '$datePart $time';
}

/// Converts an Excel serial day number to a local date.
///
/// Excel counts from 1899-12-30 and treats 1900 as a leap year, which is why
/// the epoch is the 30th rather than the 31st of December 1899.
DateTime? excelSerialToDate(double serial) {
  if (!serial.isFinite || serial < 1 || serial > 2958465) return null;
  final wholeDays = serial.floor();
  final base = DateTime.utc(1899, 12, 30).add(Duration(days: wholeDays));
  // A serial is a literal calendar value, so it is converted directly rather
  // than through the business-date guard, which rejects pre-1900 years. Excel's
  // first serial really is 1899-12-31 and must convert rather than fail.
  return DateTime(
    base.year,
    base.month,
    base.day,
    base.hour,
    base.minute,
  );
}

/// Formats a date the way it is shown in the preview and stored.
String formatImportDate(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/'
    '${date.month.toString().padLeft(2, '0')}/${date.year}';

/// Formats a number without a trailing `.0` for whole values.
String formatImportNumber(double value) {
  if (value == value.roundToDouble() && value.abs() < 1e15) {
    return value.toInt().toString();
  }
  return value.toString();
}

int _expandYear(int year) {
  if (year >= 100) return year;
  // Spreadsheets commonly use two-digit years.
  return year >= 70 ? 1900 + year : 2000 + year;
}

DateTime? _buildDate(int year, int month, int day) {
  // DateTime silently rolls 31/02 over into March, so an impossible date is
  // rejected instead of storing a different day than the spreadsheet shows.
  if (year < 1900 || year > 9999) return null;
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  final date = DateTime(year, month, day);
  if (date.month != month || date.day != day) return null;
  return date;
}

