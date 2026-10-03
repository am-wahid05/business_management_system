import '../suppliers/supplier_repository.dart';
import 'excel_cell_parser.dart';
import 'workbook_grid_model.dart';

/// One name found in a workbook column, with why it was kept or dropped.
class DetectedSupplier {
  const DetectedSupplier({
    required this.name,
    required this.accepted,
    this.reason,
    this.alreadyExists = false,
  });

  /// The name as it will be stored, trimmed.
  final String name;

  /// False when the value was ignored, in which case [reason] says why.
  final bool accepted;

  /// Why an ignored value was ignored.
  final String? reason;

  /// True when a supplier with this name already exists for the company.
  final bool alreadyExists;
}

/// The result of reading supplier names out of one workbook column.
class SupplierDetection {
  const SupplierDetection({required this.entries});

  /// Every value the column held, accepted or not, in the order seen.
  final List<DetectedSupplier> entries;

  /// The distinct names worth creating, in first-seen order.
  List<DetectedSupplier> get toCreate =>
      entries.where((e) => e.accepted && !e.alreadyExists).toList();

  /// The distinct names that already exist, so they are not created twice.
  List<DetectedSupplier> get existing =>
      entries.where((e) => e.accepted && e.alreadyExists).toList();

  /// The values that were ignored, with the reason.
  List<DetectedSupplier> get ignored =>
      entries.where((e) => !e.accepted).toList();
}

/// Reads supplier names out of one column of an imported workbook.
///
/// This only *reads*. Nothing is written until the caller confirms the preview,
/// so a preview can never change the database.
///
/// Nothing is guessed: the caller supplies the column, either because a header
/// clearly identified it or because the user picked it from the grid.
class SupplierNameDetector {
  const SupplierNameDetector();

  /// The header labels that name a column rather than holding a value.
  static const Set<String> _headerWords = {
    'supplier',
    'suppliers',
    'supplier name',
    'supplier names',
    'supplier code',
    'supplier id',
    'supplierno',
    'name',
    'names',
    'farmer',
    'farmers',
    'customer',
    'customers',
    'vendor',
    'vendors',
    'dealer',
    'dealers',
    'buyer',
    'buyers',
    'product',
    'products',
    'item',
    'items',
    'date',
    'quantity',
    'qty',
    'weight',
    'amount',
    'price',
    'phone',
    'town',
    'district',
    'region',
    'summary',
  };

  /// Strong headings used for automatic column suggestion. Generic headings
  /// such as "Product" and "Weight" are ignored during detection, but cannot
  /// suggest a supplier-name column.
  static const Set<String> _supplierHeadingWords = {
    'supplier',
    'suppliers',
    'supplier name',
    'supplier names',
    'supplier code',
    'supplier id',
    'supplierno',
    'farmer',
    'farmers',
    'farmer name',
    'farmer names',
    'vendor',
    'vendors',
    'seller',
    'sellers',
  };

  /// Labels that mean a row is a total rather than a supplier.
  static final RegExp _totalRow = RegExp(
    r'^(total|totals|subtotal|sub\s*total|grand\s*total|summary|sum)\b',
    caseSensitive: false,
  );

  /// Whether a header cell is describing the column rather than naming a
  /// supplier.
  static bool looksLikeHeader(String value) {
    final text = _clean(value);
    if (text.isEmpty) return true;
    final lowered = text.toLowerCase();
    return _headerWords.contains(lowered);
  }

  static bool _looksLikeSupplierHeading(String value) =>
      _supplierHeadingWords.contains(_clean(value).toLowerCase());

  /// Whether a value reads like a total row rather than a supplier name.
  static bool looksLikeTotal(String value) => _totalRow.hasMatch(_clean(value));

  /// The comparison key, matching the repository's own rule so "Kofi Farms",
  /// "kofi farms" and " Kofi  Farms " are one supplier.
  static String key(String value) => SupplierRepository.normalizeName(value);

  /// Reads the names from one column.
  ///
  /// [existingNames] are the names already stored for the current company, so
  /// the preview can mark a name that will be skipped.
  SupplierDetection detect({
    required WorkbookGrid grid,
    required int column,
    Iterable<String> existingNames = const [],
  }) {
    final existing = {for (final name in existingNames) key(name): name};
    // The first occurrence of a name wins, so the preview is stable and a run
    // twice produces the same list.
    final seen = <String>{};
    final entries = <DetectedSupplier>[];

    for (var row = 0; row < grid.rowCount; row++) {
      final cell = grid.cellAt(row, column);
      // A formula contributes only its result. Its own expression is never a
      // supplier name, so a formula that cannot be evaluated yields nothing
      // rather than leaking `=D1:A2` into the preview.
      final name = _clean(_resultOf(grid, row, column, cell));

      if (name.isEmpty) {
        entries.add(
          const DetectedSupplier(name: '', accepted: false, reason: 'Blank'),
        );
        continue;
      }
      if (cell.number != null ||
          cell.date != null ||
          _numericValue.hasMatch(name)) {
        entries.add(
          DetectedSupplier(
            name: name,
            accepted: false,
            reason: 'Non-text value',
          ),
        );
        continue;
      }
      if (looksLikeTotal(name)) {
        entries.add(
          DetectedSupplier(name: name, accepted: false, reason: 'Total row'),
        );
        continue;
      }
      if (row == 0 && _looksLikeUnlabelledHeaderRow(grid, column)) {
        entries.add(
          DetectedSupplier(
            name: name,
            accepted: false,
            reason: 'Column heading',
          ),
        );
        continue;
      }
      if (looksLikeHeader(name)) {
        entries.add(
          DetectedSupplier(
            name: name,
            accepted: false,
            reason: 'Column heading',
          ),
        );
        continue;
      }

      final normalized = key(name);
      if (!seen.add(normalized)) {
        entries.add(
          DetectedSupplier(
            name: name,
            accepted: false,
            reason: 'Repeated in this file',
          ),
        );
        continue;
      }
      entries.add(
        DetectedSupplier(
          name: name,
          accepted: true,
          alreadyExists: existing.containsKey(normalized),
        ),
      );
    }
    return SupplierDetection(entries: entries);
  }

  static String _clean(String value) =>
      value.trim().replaceAll(RegExp(r'\s+'), ' ');

  static final RegExp _numericValue = RegExp(
    r'^[+-]?(?:[$£€]\s*)?\d[\d,]*(?:\.\d+)?%?$',
  );

  /// If the first row is a generic table-heading row rather than a known
  /// supplier heading, avoid previewing a label such as "Beta" as a supplier.
  /// Requiring multiple populated columns and data beneath the selected column
  /// keeps a one-column, headerless supplier list intact.
  bool _looksLikeUnlabelledHeaderRow(WorkbookGrid grid, int selectedColumn) {
    if (grid.rowCount < 2 || grid.columnCount < 2) return false;
    final populatedHeaders = [
      for (var column = 0; column < grid.columnCount; column++)
        _clean(_resultOf(grid, 0, column, grid.cellAt(0, column))),
    ].where((value) => value.isNotEmpty).length;
    if (populatedHeaders < 2) return false;
    final next = grid.cellAt(1, selectedColumn);
    final nextValue = _clean(_resultOf(grid, 1, selectedColumn, next));
    return nextValue.isNotEmpty &&
        next.number == null &&
        next.date == null &&
        !_numericValue.hasMatch(nextValue) &&
        !looksLikeTotal(nextValue);
  }

  /// The value a cell contributes as a name.
  ///
  /// A formula is read through its result only. [WorkbookGrid.displayAt] would
  /// fall back to printing the expression when a grid has no formula engine
  /// built, which would let `=D1:A2` through as if it were a supplier, so the
  /// cached result and the evaluated result are used directly instead and an
  /// unevaluable formula contributes nothing.
  static String _resultOf(
    WorkbookGrid grid,
    int row,
    int column,
    ParsedCell cell,
  ) {
    if (!cell.isFormula) return cell.text;
    final cached = cell.cachedText;
    if (cached != null && cached.trim().isNotEmpty) return cached;
    final expression = (cell.formula ?? cell.text).trim().replaceFirst('=', '');
    // A bare range is not a scalar formula result. Some spreadsheet formula
    // engines attempt to walk it as a named expression, so skip it without
    // passing the raw `=D1:A2` text through as a supplier name.
    if (RegExp(r'^\$?[A-Za-z]{1,3}\$?\d+\s*:\s*\$?[A-Za-z]{1,3}\$?\d+$')
        .hasMatch(expression)) {
      return '';
    }
    final result = grid.evaluateAt(row, column);
    if (result.isFailure) return '';
    return result.text ?? '';
  }

  /// Finds the column a supplier list is most likely in, or null.
  ///
  /// A column is only suggested when its first row reads as a supplier heading
  /// *and* the values under it look like names rather than numbers. The caller
  /// still previews the result, and can pick a different column, so this is a
  /// convenience and never a decision.
  int? suggestColumn(WorkbookGrid grid) {
    for (var column = 0; column < grid.columnCount; column++) {
      if (!_looksLikeSupplierHeading(grid.displayAt(0, column).label)) continue;
      var named = 0;
      var numeric = 0;
      for (var row = 1; row < grid.rowCount; row++) {
        final cell = grid.cellAt(row, column);
        if (cell.isBlank) continue;
        if (cell.number != null) {
          numeric++;
        } else if (!looksLikeHeader(cell.text) && !looksLikeTotal(cell.text)) {
          named++;
        }
      }
      if (named > 0 && named >= numeric) return column;
    }
    return null;
  }
}
