import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// Repairs an OOXML workbook whose `styles.xml` declares custom number formats
/// with identifiers the Dart `excel` package refuses to parse.
///
/// ## Why this exists
///
/// ECMA-376 reserves number-format identifiers 0-163 for formats built in to
/// the spreadsheet application, and requires *custom* formats to start at 164.
/// Real workbooks created in Microsoft Excel break that rule: accounting and
/// other heavily formatted sheets routinely write a
/// `<numFmt numFmtId="44" .../>` element, where 44 is inside the built-in
/// range. Excel tolerates this and applies the supplied `formatCode`.
///
/// The `excel` package does not. While reading `styles.xml` it throws, and
/// because that happens up front it aborts the whole decode before a single
/// worksheet is read:
///
/// ```text
/// Exception: custom numFmtId starts at 164 but found a value of 44
/// ```
///
/// so the user sees a decode error and no rows at all, however ordinary their
/// columns are.
///
/// ## What the repair does
///
/// Each declared format whose id falls inside the reserved range is given a
/// fresh identifier at or above 164, keeping the same `formatCode`. Every
/// reference to the old id - the `numFmtId` attribute on the `cellXfs` and
/// `cellStyleXfs` entries - is rewritten to the new id.
///
/// This is a *renumbering*, not a deletion. Dropping the declaration would
/// make the package fall back to its built-in table for that id, which can turn
/// a date-formatted cell into a plain number and silently corrupt the import.
/// Renumbering keeps the exact format code, so downstream date and number
/// detection is unchanged.
///
/// ## What it deliberately does not do
///
/// * It never modifies the user's file on disk; the work happens on an
///   in-memory copy.
/// * It does not strip XML, drop sheets, convert cells to text, or touch any
///   part of the archive other than `xl/styles.xml`.
/// * It does not execute or read macro content, so a macro-enabled `.xlsm`
///   workbook is imported purely as the data it contains.
/// * It is a no-op for a workbook without the defect, so the common case stays
///   on the original bytes with no re-zip at all.
abstract final class ExcelWorkbookRepair {
  /// The first identifier the spec allows for a custom number format.
  static const int firstCustomNumFmtId = 164;

  /// Where number formats live inside an OOXML package.
  static const String stylesPart = 'xl/styles.xml';

  /// Returns bytes that the `excel` package is able to decode.
  ///
  /// The input comes back unchanged when it needs no repair, so the zip round
  /// trip is only paid for by workbooks that actually trip the bug. Any
  /// failure to read the archive is swallowed and the original bytes returned,
  /// so a genuinely unreadable file still produces the decoder's own
  /// diagnostic rather than a confusing repair error.
  static Uint8List repair(Uint8List bytes) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      return bytes;
    }

    final styles = archive.findFile(stylesPart);
    if (styles == null) return bytes;

    final List<int> raw;
    try {
      raw = styles.content as List<int>;
    } catch (_) {
      return bytes;
    }

    final String source;
    try {
      source = utf8.decode(raw);
    } catch (_) {
      return bytes;
    }

    final String repaired;
    try {
      repaired = _renumberReservedFormats(source);
    } catch (_) {
      // A styles part this repair does not understand is left exactly as it
      // was, so the decoder's own error still points at the real problem.
      return bytes;
    }
    if (identical(repaired, source)) return bytes;

    // addFile replaces an existing entry of the same name, so every other part
    // of the workbook is carried across untouched.
    archive.addFile(
      ArchiveFile(stylesPart, repaired.length, utf8.encode(repaired)),
    );
    final List<int>? encoded = ZipEncoder().encode(archive);
    if (encoded == null || encoded.isEmpty) return bytes;
    return Uint8List.fromList(encoded);
  }


  /// Returns the styles XML with reserved-range format ids moved above 164, or
  /// the identical string when there is nothing to move.
  static String _renumberReservedFormats(String source) {
    final document = XmlDocument.parse(source);

    // Only ids the workbook actually *declares* need moving. An id that is
    // merely referenced by a cell style keeps its built-in meaning, which is
    // correct: a cell using built-in 14 really is a date in Excel.
    final reserved = <int>{};
    for (final node in document.findAllElements('numFmt')) {
      final id = int.tryParse(node.getAttribute('numFmtId') ?? '');
      if (id != null && id < firstCustomNumFmtId) reserved.add(id);
    }
    if (reserved.isEmpty) return source;

    // Allocate above 164 without colliding with a format the file already
    // declares, so repairing the same workbook twice is stable.
    var next = firstCustomNumFmtId;
    for (final node in document.findAllElements('numFmt')) {
      final id = int.tryParse(node.getAttribute('numFmtId') ?? '');
      if (id != null && id >= next) next = id + 1;
    }

    final remapped = <int, int>{};
    for (final id in reserved.toList()..sort()) {
      remapped[id] = next++;
    }

    // Move the declarations first, keeping every formatCode intact.
    for (final node in document.findAllElements('numFmt')) {
      final id = int.tryParse(node.getAttribute('numFmtId') ?? '');
      final replacement = id == null ? null : remapped[id];
      if (replacement != null) node.setAttribute('numFmtId', '$replacement');
    }

    // Then repoint every remaining reference - the xf entries inside cellXfs
    // and cellStyleXfs - so each cell keeps the format it was written with. The
    // declarations just moved to ids that are not keys of the map, so this pass
    // leaves them alone.
    for (final node in document.descendantElements) {
      final raw = node.getAttribute('numFmtId');
      if (raw == null) continue;
      final replacement = remapped[int.tryParse(raw) ?? -1];
      if (replacement != null) node.setAttribute('numFmtId', '$replacement');
    }

    return document.toXmlString();
  }
}
