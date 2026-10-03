import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// What a worksheet's XML actually says about one formula cell.
///
/// The `excel` package reads a formula cell as a single string and has to choose
/// between the expression and the cached result, so one of the two is always
/// lost. Reading the worksheet XML directly recovers both, which is what lets a
/// cell show the value Excel displayed while keeping the formula intact.
class FormulaCellParts {
  const FormulaCellParts({
    required this.formula,
    required this.cachedText,
    this.type,
  });

  /// The expression, exactly as Excel wrote it, without a leading `=`.
  final String formula;

  /// The result Excel stored, or null when the file has none.
  final String? cachedText;

  /// The cell's `t` attribute, which says how to read [cachedText].
  final String? type;
}

/// Reads the formula and cached result of every formula cell in a workbook.
///
/// This is not a second Excel parser. It only opens the worksheet XML, finds
/// the cells that carry an `<f>` element, and reports the expression and the
/// `<v>` result for each. Everything else about a cell is still read by the
/// `excel` package as before, and the workbook bytes are never modified.
class WorkbookFormulaCache {
  const WorkbookFormulaCache(this._bySheet);

  /// Worksheet name to that sheet's formula cells, keyed `'row#column'`.
  final Map<String, Map<String, FormulaCellParts>> _bySheet;

  static const formulaCellCacheKeySeparator = '#';

  /// The parts for a cell, or null when it is not a formula cell.
  FormulaCellParts? partsFor(String sheetName, int row, int column) =>
      _bySheet[sheetName]?['$row$formulaCellCacheKeySeparator$column'];

  /// Reads every worksheet of the workbook at [bytes].
  ///
  /// Any problem returns an empty cache rather than throwing: the workbook is
  /// still imported exactly as before, it simply keeps the single value the
  /// `excel` package gave it.
  static WorkbookFormulaCache read(Uint8List bytes) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      final targets = _worksheetTargets(archive);
      if (targets.isEmpty) return const WorkbookFormulaCache({});
      final bySheet = <String, Map<String, FormulaCellParts>>{};
      targets.forEach((sheetName, target) {
        final parts = _cellsOf(archive, target);
        if (parts.isNotEmpty) bySheet[sheetName] = parts;
      });
      return WorkbookFormulaCache(bySheet);
    } catch (_) {
      return const WorkbookFormulaCache({});
    }
  }

  /// Maps each worksheet name to the part that holds its cells.
  static Map<String, String> _worksheetTargets(Archive archive) {
    final book = archive.findFile('xl/workbook.xml');
    final rels = archive.findFile('xl/_rels/workbook.xml.rels');
    if (book == null || rels == null) return {};

    final relTargets = <String, String>{};
    for (final node in _parse(rels)!.findAllElements('Relationship')) {
      final id = node.getAttribute('Id');
      var target = node.getAttribute('Target') ?? '';
      if (id == null || target.isEmpty) continue;
      if (!target.startsWith('/') && !target.startsWith('xl/')) {
        target = 'xl/$target';
      }
      relTargets[id] = target.replaceFirst(RegExp(r'^/?xl/'), '');
    }

    final sheets = <String, String>{};
    for (final node in _parse(book)!.findAllElements('sheet')) {
      final name = node.getAttribute('name');
      final id = node.getAttribute('r:id');
      if (name == null || id == null) continue;
      final target = relTargets[id];
      if (target != null) sheets[name] = 'xl/$target';
    }
    return sheets;
  }

  /// Every formula cell in one worksheet part.
  static Map<String, FormulaCellParts> _cellsOf(
    Archive archive,
    String target,
  ) {
    final xml = archive.findFile(target);
    if (xml == null) return {};
    final document = _parse(xml);
    if (document == null) return {};

    final parts = <String, FormulaCellParts>{};
    for (final cell in document.findAllElements('c')) {
      final formula = cell.findElements('f').firstOrNull;
      if (formula == null) continue;
      final expression = formula.innerText.trim();
      // A shared-formula slave carries an empty <f t="shared" si="n"/> and
      // only points at its master, so there is no expression to keep here.
      if (expression.isEmpty) continue;
      final position = _position(cell.getAttribute('r'));
      if (position == null) continue;
      parts[position] = FormulaCellParts(
        formula: expression,
        cachedText: cell.findElements('v').firstOrNull?.innerText,
        type: cell.getAttribute('t'),
      );
    }
    return parts;
  }

  /// Parses an A1 reference into a zero-based `row#column` key.
  static String? _position(String? reference) {
    if (reference == null) return null;
    final match = RegExp(
      r'^([A-Za-z]+)(\d+)$',
    ).firstMatch(reference.trim());
    if (match == null) return null;
    var column = 0;
    for (final code in match.group(1)!.toUpperCase().codeUnits) {
      column = column * 26 + (code - 64);
    }
    final row = int.tryParse(match.group(2)!);
    if (row == null || row < 1) return null;
    return '${row - 1}$formulaCellCacheKeySeparator${column - 1}';
  }

  static XmlDocument? _parse(ArchiveFile file) {
    try {
      return XmlDocument.parse(utf8.decode(file.content as List<int>));
    } catch (_) {
      return null;
    }
  }
}
