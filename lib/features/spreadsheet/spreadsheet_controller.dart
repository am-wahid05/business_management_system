import 'spreadsheet_clipboard.dart';
import 'spreadsheet_formatting.dart';
import 'spreadsheet_formula.dart';
import 'spreadsheet_merges.dart';
import 'spreadsheet_row.dart';
import 'spreadsheet_service.dart';
import 'spreadsheet_state_store.dart';
import 'spreadsheet_validation.dart';
import '../imports/excel_cell_parser.dart';

/// The columns the grid can search and sort on.
enum SpreadsheetColumn { date, supplier, product, weight }

/// How a list of rows is ordered.
enum SpreadsheetSort { none, date, supplier, product, weight }

/// Holds the editable state of the grid.
///
/// The controller owns the rows, the date range, the copy buffer, the session
/// formatting and the current filter, so the UI only renders what it is told
/// and the rules can be tested without a widget.
class SpreadsheetController {
  SpreadsheetController(
    this.service, {
    this.stateStore,
    this.companyIdProvider,
  });

  final SpreadsheetService service;

  /// The company whose sheet is being edited. Every persistent read and write is
  /// scoped to it, which is what keeps one company's formatting and formulas
  /// invisible and untouchable from another company's sheet.
  final String? Function()? companyIdProvider;

  /// The copy buffer for the current session.
  ///
  /// The clipboard itself is never persisted: a copy buffer is transient by
  /// nature. Formatting, which used to live here as session state, is now held
  /// in [formats] and saved with the sheet.
  final SpreadsheetClipboard clipboard = SpreadsheetClipboard();

  /// The persistent presentation state for the active company.
  final SpreadsheetStateStore? stateStore;

  /// Holds the stable key of each row so formatting and formulas follow the row
  /// rather than its position in the grid.
  final Map<SpreadsheetRow, String> _rowKeys = {};

  /// Persistent formatting, keyed by `'$rowKey#$column'`.
  final Map<String, CellFormat> _formats = {};

  /// Persistent formula expressions, keyed the same way.
  final Map<String, String> _formulas = {};

  final MergeManager _merges = MergeManager(const []);

  /// True when formatting, formulas or merges have changed since the last save.
  bool _stateDirty = false;

  /// Whether the sheet has unsaved presentation changes.
  bool get hasStateChanges => _stateDirty;

  /// The merge manager holding the sheet's merged ranges.
  MergeManager get merges => _merges;

  /// The stable key for a row: its delivery id once saved, or a draft key while
  /// it is still new.
  ///
  /// A draft keeps the same key as it is edited so its formatting and formulas
  /// survive until the row is saved, at which point the key becomes the delivery
  /// id and the draft state is re-keyed onto it.
  String rowKey(SpreadsheetRow row) =>
      _rowKeys[row] ??= row.deliveryId ?? _nextDraftKey();

  static int _draftCounter = 0;
  String _nextDraftKey() => 'draft:${_draftCounter++}';

  /// The cell key used to look up formatting and formulas.
  String cellKey(SpreadsheetRow row, int column) =>
      SpreadsheetState.cellKey(rowKey(row), column);

  /// The saved format for a cell, or the default when it has none.
  CellFormat formatAt(SpreadsheetRow row, int column) =>
      _formats[cellKey(row, column)] ?? const CellFormat();

  /// The saved formula expression for a cell, or null when it has none.
  String? formulaAt(SpreadsheetRow row, int column) =>
      _formulas[cellKey(row, column)];

  /// All saved formatting, for export.
  Map<String, CellFormat> get formats => Map.unmodifiable(_formats);

  /// All saved formulas, for export.
  Map<String, String> get formulas => Map.unmodifiable(_formulas);

  /// The row keys in grid order, which is what the merge rules work against.
  List<String> get rowKeys => _rows.map(rowKey).toList(growable: false);

  /// Applies a format to every cell in a range and marks the sheet dirty.
  void formatRange(
    CellRange range,
    CellFormat Function(CellFormat current) change,
  ) {
    for (var row = range.startRow; row <= range.endRow; row++) {
      if (row < 0 || row >= _rows.length) continue;
      for (
        var column = range.startColumn;
        column <= range.endColumn;
        column++
      ) {
        final target = _rows[row];
        final key = cellKey(target, column);
        final updated = change(formatAt(target, column));
        if (updated.isPlain) {
          _formats.remove(key);
        } else {
          _formats[key] = updated;
        }
        _stateDirty = true;
      }
    }
  }

  /// Stores a formula for a cell, or clears it when [expression] is null.
  void setFormula(SpreadsheetRow row, int column, String? expression) {
    final key = cellKey(row, column);
    if (expression == null || expression.trim().isEmpty) {
      _formulas.remove(key);
    } else {
      _formulas[key] = expression;
    }
    _stateDirty = true;
  }

  /// The result of a merge or unmerge.
  ///
  /// A successful merge or unmerge marks the sheet dirty so Save persists it. A
  /// refused one changes nothing and leaves the sheet clean.
  MergeResult mergeRange(CellRange range) {
    final result = _merges.merge(
      rowKeys: rowKeys,
      startRow: range.startRow,
      startColumn: range.startColumn,
      endRow: range.endRow,
      endColumn: range.endColumn,
    );
    if (result.isSuccess) _stateDirty = true;
    return result;
  }

  MergeResult unmergeRange(CellRange range) {
    final result = _merges.unmerge(
      rowKeys: rowKeys,
      row: range.startRow,
      column: range.startColumn,
    );
    if (result.isSuccess) _stateDirty = true;
    return result;
  }

  /// True when a cell is inside a merge but is not its anchor, so it must not be
  /// edited directly.
  bool isCoveredByMerge(SpreadsheetRow row, int column) {
    final index = _rows.indexOf(row);
    if (index < 0) return false;
    return _merges.isCoveredByMerge(rowKeys, index, column);
  }

  final List<SpreadsheetRow> _rows = <SpreadsheetRow>[];
  List<SpreadsheetRow> get rows => List.unmodifiable(_rows);

  DateTime _from = DateTime.now();
  DateTime _to = DateTime.now();
  DateTime get from => _from;
  DateTime get to => _to;

  bool _loading = false;
  bool get isLoading => _loading;

  String? _error;
  String? get error => _error;

  String _search = '';
  String get search => _search;

  /// When true only rows with a validation error are shown.
  bool _onlyInvalid = false;
  bool get onlyInvalid => _onlyInvalid;

  /// When true only rows the user has changed are shown.
  bool _onlyChanged = false;
  bool get onlyChanged => _onlyChanged;

  SpreadsheetSort _sort = SpreadsheetSort.none;
  SpreadsheetSort get sort => _sort;

  /// The rows actually shown, after filtering and sorting.
  List<SpreadsheetRow> get visibleRows {
    final term = _search.trim().toLowerCase();
    var result = _rows.where((row) {
      if (_onlyInvalid && !row.hasError) return false;
      if (_onlyChanged &&
          row.state != SpreadsheetRowState.edited &&
          row.state != SpreadsheetRowState.created) {
        return false;
      }
      if (term.isEmpty) return true;
      return row.supplierName.toLowerCase().contains(term) ||
          row.productName.toLowerCase().contains(term) ||
          row.date.toLowerCase().contains(term) ||
          row.recorderName.toLowerCase().contains(term) ||
          row.weights.toLowerCase().contains(term);
    }).toList();
    if (_sort != SpreadsheetSort.none) result = _applySort(result);
    return result;
  }

  List<SpreadsheetRow> _applySort(List<SpreadsheetRow> input) {
    final sorted = List<SpreadsheetRow>.of(input);
    sorted.sort(
      (left, right) => switch (_sort) {
        SpreadsheetSort.date => _compare(
          left.recordedAt?.millisecondsSinceEpoch,
          right.recordedAt?.millisecondsSinceEpoch,
        ),
        SpreadsheetSort.supplier => _compare(
          left.supplierName.toLowerCase(),
          right.supplierName.toLowerCase(),
        ),
        SpreadsheetSort.product => _compare(
          left.productName.toLowerCase(),
          right.productName.toLowerCase(),
        ),
        SpreadsheetSort.weight => _compare(left.totalWeight, right.totalWeight),
        SpreadsheetSort.none => 0,
      },
    );
    return sorted;
  }

  static int _compare(Object? left, Object? right) {
    if (left == null && right == null) return 0;
    if (left == null) return 1;
    if (right == null) return -1;
    if (left is num && right is num) return left.compareTo(right);
    return '$left'.compareTo('$right');
  }

  /// Sets the free text search across supplier, product, date and weight.
  void searchFor(String term) => _search = term;

  /// Shows only rows that failed validation.
  void showOnlyInvalid(bool value) => _onlyInvalid = value;

  /// Shows only rows the user has changed.
  void showOnlyChanged(bool value) => _onlyChanged = value;

  /// Sorts the grid; passing [SpreadsheetSort.none] restores the saved order.
  void sortBy(SpreadsheetSort value) => _sort = value;

  /// Clears the search and both filters.
  void clearFilters() {
    _search = '';
    _onlyInvalid = false;
    _onlyChanged = false;
  }

  // ---- cell access used by the grid, clipboard and formulas --------------

  /// The grid columns, in the order they appear.
  static const List<SpreadsheetColumn> gridColumns = [
    SpreadsheetColumn.date,
    SpreadsheetColumn.supplier,
    SpreadsheetColumn.product,
    SpreadsheetColumn.weight,
  ];

  /// The editable text of one cell in a row.
  String cellText(SpreadsheetRow row, int column) => switch (column) {
    0 => row.date,
    1 => row.supplierName,
    2 => row.productName,
    3 => row.weights,
    _ => '',
  };

  /// The cell as a number, which is what a formula reads.
  double? cellNumber(SpreadsheetRow row, int column) => switch (column) {
    3 => row.totalWeight,
    _ => double.tryParse(row.date.replaceAll(RegExp(r'[^0-9.]'), '')),
  };

  /// The whole grid as text, used to build and read a copy block.
  List<List<String>> gridValues() => _rows
      .map((row) => List.generate(4, (column) => cellText(row, column)))
      .toList();

  /// Writes one cell, marking the row as edited and revalidating it.
  void setCell(SpreadsheetRow row, int column, String value) {
    switch (column) {
      case 0:
        row.date = value;
      case 1:
        row.supplierName = value;
      case 2:
        row.productName = value;
      case 3:
        row.weights = value;
    }
    row.markEdited();
    applyRowValidation(row);
  }

  /// Copies a rectangle of the grid into the session clipboard.
  void copy(CellRange range) {
    clipboard.copy(range, gridValues());
  }

  /// Pastes the clipboard at [target].
  ///
  /// A single copied cell is repeated across the whole target range, which is
  /// what makes it practical to fill a supplier, date or product down many rows
  /// and then change only the weights. Every pasted row is revalidated, so a
  /// paste can never introduce an invalid value silently.
  int paste(CellRange target) {
    final block = clipboard.block;
    if (block == null) return 0;

    // Rows that do not exist yet are added, so a paste can fill new rows.
    while (_rows.length <= target.endRow) {
      addDraft();
    }

    var pasted = 0;
    for (var row = target.startRow; row <= target.endRow; row++) {
      for (
        var column = target.startColumn;
        column <= target.endColumn;
        column++
      ) {
        final offsetRow = (row - target.startRow) % block.rowCount;
        final offsetColumn = (column - target.startColumn) % block.columnCount;
        final sourceRow = block.values[offsetRow];
        final value = offsetColumn < sourceRow.length
            ? sourceRow[offsetColumn]
            : '';
        setCell(_rows[row], column, value);
        pasted++;
      }
    }
    return pasted;
  }

  // ---- formulas ---------------------------------------------------------

  /// Evaluates a formula against the current grid.
  ///
  /// The result is for display only. A formula is never written into a row, so
  /// it can never become an official weight, bag count or total: those always
  /// come from the entered bag weights and the existing business logic.
  FormulaResult evaluateFormula(String source) =>
      FormulaEvaluator(ControllerFormulaGrid(this)).evaluate(source);

  /// Evaluates a cell and returns the text to show, including a readable
  /// message when the formula cannot be evaluated.
  String formulaDisplay(String source) {
    final result = evaluateFormula(source);
    if (result.isFailure) return result.errorLabel;
    final value = result.value;
    if (value == null) return result.text ?? source;
    return formatImportNumber(value);
  }

  /// Rows the user has changed, which is what Save acts on.
  List<SpreadsheetRow> get changedRows => _rows
      .where(
        (row) =>
            row.state == SpreadsheetRowState.edited ||
            row.state == SpreadsheetRowState.created,
      )
      .toList(growable: false);

  bool get hasChanges => changedRows.isNotEmpty;

  /// Loads the existing rows for a range, discarding any unsaved edits.
  ///
  /// The company's saved formatting, formulas and merges are restored alongside
  /// the rows, so reopening the spreadsheet shows the same presentation it had
  /// when it was closed.
  Future<void> load({DateTime? from, DateTime? to}) async {
    _loading = true;
    _error = null;
    final start = from ?? _from;
    final end = to ?? _to;
    try {
      final loaded = await service.load(from: start, to: end);
      _rows
        ..clear()
        ..addAll(loaded);
      _from = start;
      _to = end;
      // A saved row's key is its delivery id, so a reloaded row picks up exactly
      // the presentation that was stored against that delivery.
      _rowKeys
        ..clear()
        ..addEntries(
          loaded
              .where((row) => row.deliveryId != null)
              .map((row) => MapEntry(row, row.deliveryId!)),
        );
      await _loadState();
    } on Object catch (error) {
      _error = error.toString();
    } finally {
      _loading = false;
    }
  }

  /// Restores the active company's saved presentation state.
  Future<void> _loadState() async {
    final store = stateStore;
    final companyId = companyIdProvider?.call();
    if (store == null || companyId == null || companyId.isEmpty) {
      _formats.clear();
      _formulas.clear();
      _merges.replaceAll(const []);
      _stateDirty = false;
      return;
    }
    final state = await store.load(companyId: companyId);
    _formats
      ..clear()
      ..addAll(state.formats);
    _formulas
      ..clear()
      ..addAll(state.formulas);
    _merges.replaceAll(state.merges);
    _stateDirty = false;
  }

  /// Saves the sheet's presentation state, but only when something changed.
  ///
  /// Nothing is written when the sheet is clean, so an unchanged spreadsheet does
  /// not rewrite the table on every save.
  Future<void> saveState() async {
    final store = stateStore;
    final companyId = companyIdProvider?.call();
    if (store == null || companyId == null || companyId.isEmpty) return;
    if (!_stateDirty) return;
    await store.save(
      companyId: companyId,
      state: SpreadsheetState(
        formats: _formats,
        formulas: _formulas,
        merges: _merges.merges,
      ),
    );
    _stateDirty = false;
  }

  /// Changes the range and reloads.
  Future<void> setRange(DateTime from, DateTime to) => load(from: from, to: to);

  /// Adds an empty draft row for the user to fill in.
  SpreadsheetRow addDraft({DateTime? date}) {
    final row = SpreadsheetRow.draft(date: date ?? _from);
    _rows.add(row);
    return row;
  }

  /// Marks a row that has not been saved yet as removed.
  ///
  /// The row stays in the grid, shown as removed, so the user can see exactly
  /// what will be discarded and undo it. A saved record is never removed here,
  /// so the screen cannot silently destroy history.
  ///
  /// A discarded row's presentation state is dropped, so its formatting,
  /// formulas and merges cannot linger and later reappear on another row.
  bool removeDraft(SpreadsheetRow row) {
    if (!row.isNew) return false;
    if (row.state == SpreadsheetRowState.deleted) return false;
    row.state = SpreadsheetRowState.deleted;
    row.error = null;
    _forgetRowState(row);
    return true;
  }

  /// Drops the presentation state belonging to a discarded draft.
  void _forgetRowState(SpreadsheetRow row) {
    final key = _rowKeys[row];
    if (key == null) return;
    for (var column = 0; column < 4; column++) {
      final cellKey = SpreadsheetState.cellKey(key, column);
      _formats.remove(cellKey);
      _formulas.remove(cellKey);
    }
    _rowKeys.remove(row);
    _stateDirty = true;
  }

  /// Brings a removed draft row back.
  bool restoreDraft(SpreadsheetRow row) {
    if (row.state != SpreadsheetRowState.deleted) return false;
    row.state = SpreadsheetRowState.created;
    applyRowValidation(row);
    return true;
  }

  /// Adds rows read from a spreadsheet into the grid as new drafts.
  ///
  /// Nothing is written to the database here: the rows are validated and shown
  /// like any other draft, and only saved when the user confirms.
  int addImportedRows(List<SpreadsheetRow> rows) {
    var added = 0;
    for (final row in rows) {
      if (row.isRemoved) continue;
      final copy = row.copy()..state = SpreadsheetRowState.created;
      applyRowValidation(copy);
      _rows.add(copy);
      added++;
    }
    return added;
  }

  /// Applies an edit to a field and revalidates the row.
  void edit(
    SpreadsheetRow row, {
    String? date,
    String? supplierName,
    String? productName,
    String? weights,
  }) {
    if (date != null) row.date = date;
    if (supplierName != null) row.supplierName = supplierName;
    if (productName != null) row.productName = productName;
    if (weights != null) row.weights = weights;
    row.markEdited();
    applyRowValidation(row);
  }

  /// Rechecks every row, so the errors shown always match the current values.
  void validateAll() {
    for (final row in _rows) {
      applyRowValidation(row);
    }
  }

  int get errorCount => _rows.where((row) => row.hasError).length;

  /// Discards every unsaved change by reloading from the database.
  Future<void> discard() => load();

  /// Saves the changed rows and the sheet's presentation state.
  Future<SpreadsheetSaveResult> save() async {
    validateAll();
    // Every row is handed to the service, including the untouched ones, so it
    // can report them as unchanged. The service decides what to write and skips
    // unchanged rows itself, which is what stops opening and saving the grid
    // from overwriting a stored record.
    final result = await service.save(rows);

    // A saved row now has a delivery id. Its presentation was keyed on a draft
    // key while it was new, so it is re-keyed onto the delivery id before the
    // state is written, otherwise a new row's formatting and formulas would be
    // lost on the save that created it.
    _rekeyAfterSave();

    // The sheet's own presentation state is written BEFORE the reload, because
    // reloading restores the saved state and would otherwise discard anything
    // this save has not yet persisted.
    await saveState();

    // Reload so the grid shows exactly what is stored, and any draft the
    // service rejected disappears rather than lingering. The reload then reads
    // back the state that was just written.
    _rows.removeWhere((row) => row.isRemoved);
    await load();
    return result;
  }

  /// Moves presentation state from a draft key onto the delivery id that a save
  /// has just assigned to that row.
  void _rekeyAfterSave() {
    final movedFormats = <String, CellFormat>{};
    final movedFormulas = <String, String>{};
    final movedMerges = <CellMerge>[];
    final remapped = <SpreadsheetRow, String>{};

    for (final entry in _rowKeys.entries) {
      final row = entry.key;
      final deliveryId = row.deliveryId;
      if (deliveryId == null || deliveryId == entry.value) {
        remapped[row] = entry.value;
        continue;
      }

      for (var column = 0; column < 4; column++) {
        final oldKey = SpreadsheetState.cellKey(entry.value, column);
        final format = _formats.remove(oldKey);
        if (format != null) {
          movedFormats[SpreadsheetState.cellKey(deliveryId, column)] = format;
        }
        final formula = _formulas.remove(oldKey);
        if (formula != null) {
          movedFormulas[SpreadsheetState.cellKey(deliveryId, column)] = formula;
        }
      }
      for (final merge in _merges.merges) {
        if (merge.anchorRowKey == entry.value &&
            merge.endRowKey == entry.value) {
          movedMerges.add(
            CellMerge(
              anchorRowKey: deliveryId,
              anchorColumn: merge.anchorColumn,
              endRowKey: deliveryId,
              endColumn: merge.endColumn,
            ),
          );
        }
      }
      remapped[row] = deliveryId;
    }

    _rowKeys
      ..clear()
      ..addAll(remapped);
    _formats.addAll(movedFormats);
    _formulas.addAll(movedFormulas);
    if (movedMerges.isNotEmpty) {
      _merges.replaceAll([..._merges.merges, ...movedMerges]);
      _stateDirty = true;
    }
    if (movedFormats.isNotEmpty || movedFormulas.isNotEmpty) {
      _stateDirty = true;
    }
  }
}

/// Lets a formula read cell values from the grid.
///
/// Only the editable cell text is exposed, so a formula is display-only and can
/// never read or write the official stored weight.
class ControllerFormulaGrid implements FormulaGrid {
  const ControllerFormulaGrid(this.controller);

  final SpreadsheetController controller;

  @override
  int get rowCount => controller.rows.length;

  @override
  int get columnCount => 4;

  @override
  double? numberAt(int row, int column) {
    if (row < 0 || row >= controller.rows.length) return null;
    return controller.cellNumber(controller.rows[row], column);
  }

  @override
  String textAt(int row, int column) {
    if (row < 0 || row >= controller.rows.length) return '';
    return controller.cellText(controller.rows[row], column);
  }
}
