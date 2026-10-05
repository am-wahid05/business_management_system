import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_navigation.dart';
import '../../app/app_ui.dart';
import '../auth/auth_models.dart';
import '../auth/no_access_screen.dart';
import '../imports/excel_import_service.dart';
import '../imports/workbook_grid_store.dart';
import '../imports/workbook_grid_view.dart';
import '../management/workbook_grid_screen.dart';
import 'spreadsheet_access.dart';
import 'spreadsheet_clipboard.dart';
import 'spreadsheet_grid_adapter.dart';
import 'spreadsheet_controller.dart';
import 'spreadsheet_formatting.dart';
import 'spreadsheet_import_export.dart';
import 'spreadsheet_row.dart';
import 'spreadsheet_validation.dart';

/// The Admin Spreadsheet, shown as an Excel-like worksheet.
///
/// The sheet itself is the existing [WorkbookGridView], with the controller's
/// delivery rows projected into it by `SpreadsheetGridAdapter`. The cells are
/// the interface: there is no fixed business table and no invented header row,
/// and the same grid is used on a desktop and on a phone.
class SpreadsheetScreen extends StatefulWidget {
  const SpreadsheetScreen({
    required this.controller,
    required this.excelImportService,
    required this.currentUser,
    this.onExport,
    this.workbookGridStore,
    super.key,
  });

  final SpreadsheetController controller;

  /// The Phase 1 import service, reused to read a workbook into the grid.
  final ExcelImportService excelImportService;

  /// The signed-in user, read on every build so a role change takes effect
  /// straight away. This is required, so the screen cannot be constructed
  /// without an access check.
  final AppUser? Function() currentUser;

  /// Exports the current grid. Supplied by the caller so the screen reuses the
  /// existing export service rather than writing files itself.
  final Future<String> Function(List<SpreadsheetRow> rows)? onExport;

  /// Where an opened workbook grid is saved. Injected so an imported workbook
  /// is stored by the same company-scoped store the workbook grid already uses.
  final WorkbookGridStore? workbookGridStore;

  @override
  State<SpreadsheetScreen> createState() => _SpreadsheetScreenState();
}

class _SpreadsheetScreenState extends State<SpreadsheetScreen> {
  SpreadsheetSaveResult? _result;
  bool _busy = false;
  bool _showRemoved = true;

  /// The spreadsheet is an admin/owner tool. A secretary is refused here even
  /// if the screen is somehow reached without passing the route guard.
  bool get _isAllowed => canUseSpreadsheet(widget.currentUser());

  // The current cell selection, used for copy, paste and formatting.
  CellPosition? _anchor;
  CellPosition? _focus;
  final TextEditingController _searchController = TextEditingController();

  CellRange? get _selection {
    final anchor = _anchor;
    final focus = _focus;
    if (anchor == null || focus == null) return null;
    return CellRange.between(anchor, focus);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    await widget.controller.load();
    if (mounted) setState(() {});
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _notify(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _clearSelection() {
    setState(() {
      _anchor = null;
      _focus = null;
    });
  }

  /// Copies the selected cells, and also puts them on the system clipboard so
  /// copy and paste work between the grid and other applications.
  Future<void> _copySelection() async {
    if (!_guard()) return;
    final range = _selection;
    if (range == null) {
      _notify('Select a cell or a range first.');
      return;
    }
    // The clipboard carries plain text and cannot carry a merge structure, so
    // copying merged cells is refused rather than producing a copy that would
    // break the merge when pasted back.
    if (_selectionTouchesMerge()) {
      _notify(
        'Merged cells cannot be copied. Copy a range that is not merged.',
      );
      return;
    }
    widget.controller.copy(range);
    final block = widget.controller.clipboard.block;
    if (block == null) return;
    final text = block.values.map((row) => row.join('\t')).join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    _notify('Copied ${range.label}');
  }

  /// Pastes at the selected cell, repeating a single copied value across the
  /// whole selected range.
  Future<void> _pasteSelection() async {
    if (!_guard()) return;
    if (!widget.controller.clipboard.hasContent) {
      _notify('Nothing has been copied yet.');
      return;
    }
    final target = _selection;
    if (target == null) {
      _notify('Select the cell to paste into.');
      return;
    }
    // Pasting over merged cells would silently break the merge, so it is
    // refused with an explanation instead.
    if (_selectionTouchesMerge()) {
      _notify(
        'Cannot paste into merged cells. Unmerge them first, then paste.',
      );
      return;
    }
    final pasted = widget.controller.paste(target);
    setState(() {});
    _notify('Pasted into $pasted cells');
  }

  /// Applies a colour or style to the selected cells.
  ///
  /// This goes through the controller's persistent formatting, so the format is
  /// saved with the sheet and restored when the spreadsheet is reopened. It is
  /// still only written to the database on Save, never on every tap.
  void _formatSelection(CellFormat Function(CellFormat) change) {
    if (!_guard()) return;
    final range = _selection;
    if (range == null) {
      _notify('Select a cell or a range first.');
      return;
    }
    setState(() => widget.controller.formatRange(range, change));
  }

  /// True when the selection touches a merged range.
  ///
  /// Copy and paste carry plain text and cannot carry a merge structure, so an
  /// operation that would touch merged cells is refused rather than silently
  /// breaking the merge definition.
  bool _selectionTouchesMerge() {
    final range = _selection;
    if (range == null) return false;
    final keys = widget.controller.rowKeys;
    for (var row = range.startRow; row <= range.endRow; row++) {
      if (row < 0 || row >= keys.length) continue;
      for (
        var column = range.startColumn;
        column <= range.endColumn;
        column++
      ) {
        if (widget.controller.merges.mergeCovering(keys, row, column) != null) {
          return true;
        }
      }
    }
    return false;
  }

  /// True when the current selection could sensibly be merged: it must span more
  /// than one cell, exist in the grid, and not already touch a merge.
  bool get _canMergeSelection {
    final range = _selection;
    if (range == null) return false;
    if (range.startRow == range.endRow &&
        range.startColumn == range.endColumn) {
      return false;
    }
    if (range.endRow >= widget.controller.visibleRows.length) return false;
    return !_selectionTouchesMerge();
  }

  /// Merges the selected range, or reports why it cannot be merged.
  void _mergeSelection() {
    if (!_guard()) return;
    final range = _selection;
    if (range == null) {
      _notify('Select the cells to merge first.');
      return;
    }
    setState(() {
      final result = widget.controller.mergeRange(range);
      _notify(
        result.isSuccess
            ? 'Merged ${range.label}.'
            : result.message ?? 'Those cells cannot be merged.',
      );
    });
  }

  /// Removes the merge anchored on the selected cell.
  void _unmergeSelection() {
    if (!_guard()) return;
    final range = _selection;
    if (range == null) {
      _notify('Select a merged cell first.');
      return;
    }
    setState(() {
      final result = widget.controller.unmergeRange(range);
      _notify(
        result.isSuccess
            ? 'Unmerged.'
            : result.message ?? 'Those cells are not merged.',
      );
    });
  }

  /// Enters or clears a formula on the selected cell.
  ///
  /// A formula is spreadsheet state only. It is shown with its calculated result
  /// and is never written into a row's bag weights, so it can never become an
  /// official delivery weight.
  void _editFormula() {
    if (!_guard()) return;
    final range = _selection;
    if (range == null) {
      _notify('Select the cell to put the formula in.');
      return;
    }
    final controller = widget.controller;
    final rows = controller.visibleRows;
    if (range.startRow < 0 || range.startRow >= rows.length) {
      _notify('That cell is not part of the grid.');
      return;
    }
    final row = rows[range.startRow];
    final existing = controller.formulaAt(row, range.startColumn);

    showDialog<void>(
      context: context,
      builder: (dialogContext) => _FormulaDialog(
        initialExpression: existing,
        // The live preview uses the controller's own evaluator, so what the
        // secretary sees is exactly what the sheet will show and recalculate on
        // reopen.
        previewFor: controller.formulaDisplay,
        onSubmit: (expression) {
          final trimmed = expression.trim();
          // An empty entry clears the formula rather than storing a blank one.
          controller.setFormula(row, range.startColumn, trimmed);
          setState(() {});
          _notify(
            trimmed.isEmpty
                ? 'Formula removed.'
                : 'Formula saved. It stays a spreadsheet calculation and is '
                      'never a delivery weight.',
          );
        },
      ),
    );
  }

  void _showFormatMenu() {
    if (!_guard()) return;
    final range = _selection;
    if (range == null) {
      _notify('Select a cell or a range first.');
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text('Highlight'),
            ),
            for (final color in CellColor.values)
              ListTile(
                leading: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: color.argb == null
                        ? Theme.of(sheetContext)
                              .colorScheme
                              .surfaceContainerHighest
                        : Color(color.argb!),
                    border: Border.all(
                      color: Theme.of(sheetContext).dividerColor,
                    ),
                    shape: BoxShape.circle,
                  ),
                ),
                title: Text(color.label),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _formatSelection(
                    (current) => current.copyWith(background: color),
                  );
                },
              ),
            const Divider(),
            SwitchListTile(
              title: const Text('Bold'),
              value: widget.controller.clipboard
                  .formatAt(_focus ?? const CellPosition(0, 0))
                  .bold,
              onChanged: (value) =>
                  _formatSelection((current) => current.copyWith(bold: value)),
            ),
            SwitchListTile(
              title: const Text('Italic'),
              value: widget.controller.clipboard
                  .formatAt(_focus ?? const CellPosition(0, 0))
                  .italic,
              onChanged: (value) => _formatSelection(
                (current) => current.copyWith(italic: value),
              ),
            ),
            ListTile(
              title: const Text('Clear formatting'),
              onTap: () {
                Navigator.pop(sheetContext);
                setState(() {
                  widget.controller.formatRange(
                    range,
                    (_) => const CellFormat(),
                  );
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Refuses a spreadsheet action when the current user is not allowed.
  ///
  /// The build method already hides the whole grid, but every action checks too,
  /// so a secretary cannot drive the grid even by calling an action directly.
  bool _guard() {
    if (_isAllowed) return true;
    _notify('You do not have permission to use the spreadsheet.');
    return false;
  }

  void _addRow() {
    if (!_guard()) return;
    widget.controller.addDraft();
    setState(() {});
  }

  /// True when the sheet has anything unsaved: row data, formatting, a formula or
  /// a merge. The Save and Discard actions use this, so a presentation-only
  /// change is still saveable and still discardable.
  bool get _hasUnsavedChanges =>
      widget.controller.hasChanges || widget.controller.hasStateChanges;

  Future<void> _save() async {
    if (!_guard()) return;
    final controller = widget.controller;
    if (!_hasUnsavedChanges) {
      _notify('There is nothing to save.');
      return;
    }
    final summary = summariseRows(controller.rows);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Save spreadsheet changes'),
        content: Text(
          '${summary.created} new, ${summary.edited} edited, '
          '${summary.unchanged} unchanged.\n\n'
          'Unchanged rows are left exactly as they are, and rows with errors '
          'are skipped.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _run(() async {
      final result = await controller.save();
      if (!mounted) return;
      setState(() => _result = result);
      await _showResult(result);
    });
  }

  Future<void> _showResult(SpreadsheetSaveResult result) => showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Save complete'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${result.created} added'),
          Text('${result.updated} updated'),
          Text('${result.unchanged} unchanged'),
          if (result.suppliersCreated > 0)
            Text('${result.suppliersCreated} suppliers created'),
          if (result.skippedDuplicates > 0)
            Text('${result.skippedDuplicates} duplicates skipped'),
          if (result.failed > 0) Text('${result.failed} rows rejected'),
          if (result.errors.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...result.errors
                .take(10)
                .map(
                  (error) => Text(
                    error,
                    style: TextStyle(
                      color: Theme.of(dialogContext).colorScheme.error,
                    ),
                  ),
                ),
          ],
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Close'),
        ),
      ],
    ),
  );

  Future<void> _discard() async {
    if (!_guard()) return;
    if (!_hasUnsavedChanges) {
      _notify('There are no changes.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text(
          'All unsaved edits, new rows and removed rows will be discarded.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(() async {
      _result = null;
      await widget.controller.discard();
    });
  }

  /// Opens an Excel workbook in the Excel-like grid.
  ///
  /// This is the import the user asked for: the workbook is read as a grid, so
  /// its cells appear in their own positions with no column mapping and no
  /// "Map Out" step. The legacy business import below is still available for a
  /// file that really is a list of deliveries.
  Future<void> _importExcel() async {
    if (!_guard()) return;
    await _run(() async {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        // .xlsm is the same OOXML package as .xlsx; its macro part is ignored
        // and the worksheet data is imported normally.
        allowedExtensions: const ['xlsx', 'xlsm', 'csv'],
        withData: true,
      );
      if (picked == null) return;
      final file = picked.files.single;
      final bytes = file.bytes;
      if (bytes == null) {
        throw StateError('The selected file could not be read');
      }
      // The grid reader keeps the workbook's own cells, formulas, formatting
      // and merges, so nothing is forced into the delivery schema.
      final book = widget.excelImportService.readWorkbookGrids(
        bytes,
        file.name,
      );
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => WorkbookGridScreen(
            service: widget.excelImportService,
            store: widget.workbookGridStore ?? const WorkbookGridStore(null),
            currentUser: widget.currentUser,
            initialBook: book,
          ),
        ),
      );
      if (mounted) setState(() {});
    });
  }

  /// The legacy business import, kept for a file that really is a list of
  /// deliveries.
  ///
  /// This is the old "Map Out" behaviour: the header row is detected, the
  /// columns are mapped onto Date/Supplier/Product/Weight, and each row is
  /// validated as a delivery. It is no longer what "Import Excel" does.
  Future<void> _importBusinessRows() async {
    if (!_guard()) return;
    await _run(() async {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['xlsx', 'xlsm', 'csv'],
        withData: true,
      );
      if (picked == null) return;
      final bytes = picked.files.single.bytes;
      if (bytes == null) {
        throw StateError('The selected file could not be read');
      }
      // The Phase 1 reader does the parsing, header detection and mapping.
      final workbook = widget.excelImportService.readWorkbook(
        bytes,
        picked.files.single.name,
      );
      final imported = spreadsheetRowsFromSheet(workbook.sheets.values.first);
      if (imported.isEmpty) {
        throw StateError('No usable rows were found in that file');
      }
      // The rows are only added to the grid; nothing is saved yet.
      final added = widget.controller.addImportedRows(imported);
      setState(() {});
      _notify('$added rows added to the grid. Review them, then save.');
    });
  }

  Future<void> _export() async {
    if (!_guard()) return;
    final exporter = widget.onExport;
    if (exporter == null) return;
    await _run(() async {
      final message = await exporter(widget.controller.rows);
      _notify(message);
    });
  }

  @override
  Widget build(BuildContext context) {
    // The grid is never built for a user who is not allowed to use it, so no
    // action inside it can be reached.
    if (!_isAllowed) return const NoAccessScreen();

    final controller = widget.controller;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Spreadsheet'),
        actions: [
          IconButton(
            tooltip: 'Reload',
            onPressed: _busy ? null : _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1),
        ),
      ),
      drawer: shellDrawerFor(context),
      body: Column(
        children: [
          _buildToolbar(),
          _buildSelectionBar(),
          const SizedBox(height: 8),
          if (controller.isLoading) const LinearProgressIndicator(),
          if (controller.error != null)
            AppErrorState(
              title: 'Spreadsheet unavailable',
              message: 'We could not load the saved delivery sheet.',
              onRetry: _reload,
            ),
          if (_result != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Text('Last save: ${_result!.summary}'),
            ),
          Expanded(
            child: controller.isLoading
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: AppGridSkeleton(rows: 8, columns: 6),
                  )
                : controller.rows.isEmpty
                ? const AppEmptyState(
                    title: 'No spreadsheet rows',
                    message:
                        'There are no delivery rows for the selected period.',
                    icon: Icons.grid_on_outlined,
                  )
                // The workbook grid is the spreadsheet. It is the only sheet
                // UI, on a desktop and on a phone alike, so the same cells are
                // what every user sees. The old fixed business table and the
                // narrow card list are gone.
                : _buildWorkbookGrid(),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          FilledButton.icon(
            onPressed: _busy ? null : _addRow,
            icon: const Icon(Icons.add),
            label: const Text('Add row'),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: _busy ? null : _save,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Save'),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : _discard,
            icon: const Icon(Icons.undo),
            label: const Text('Discard changes'),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : _importExcel,
            icon: const Icon(Icons.file_upload_outlined),
            label: const Text('Import Excel'),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : _importBusinessRows,
            icon: const Icon(Icons.table_view_outlined),
            label: const Text('Import delivery rows'),
          ),
          if (widget.onExport != null) ...[
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: _busy ? null : _export,
              icon: const Icon(Icons.file_download_outlined),
              label: const Text('Export'),
            ),
          ],
          const SizedBox(width: 16),
          FilterChip(
            label: const Text('Show removed'),
            selected: _showRemoved,
            onSelected: (value) => setState(() => _showRemoved = value),
          ),
        ],
      ),
    );
  }

  /// The search, filter and sort controls, plus the clipboard and formatting
  /// actions that act on the current selection.
  Widget _buildSelectionBar() {
    final controller = widget.controller;
    final selection = _selection;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 220,
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                isDense: true,
                prefixIcon: Icon(Icons.search),
                hintText: 'Search supplier or product',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => setState(() => controller.searchFor(value)),
            ),
          ),
          FilterChip(
            label: const Text('Edited only'),
            selected: controller.onlyChanged,
            onSelected: (value) =>
                setState(() => controller.showOnlyChanged(value)),
          ),
          FilterChip(
            label: const Text('Invalid only'),
            selected: controller.onlyInvalid,
            onSelected: (value) =>
                setState(() => controller.showOnlyInvalid(value)),
          ),
          DropdownButton<SpreadsheetSort>(
            value: controller.sort,
            underline: const SizedBox.shrink(),
            items: const [
              DropdownMenuItem(
                value: SpreadsheetSort.none,
                child: Text('Sort: saved order'),
              ),
              DropdownMenuItem(
                value: SpreadsheetSort.date,
                child: Text('Sort: date'),
              ),
              DropdownMenuItem(
                value: SpreadsheetSort.supplier,
                child: Text('Sort: supplier'),
              ),
              DropdownMenuItem(
                value: SpreadsheetSort.product,
                child: Text('Sort: product'),
              ),
              DropdownMenuItem(
                value: SpreadsheetSort.weight,
                child: Text('Sort: weight'),
              ),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() => controller.sortBy(value));
            },
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : _copySelection,
            icon: const Icon(Icons.copy_all_outlined, size: 18),
            label: Text(selection == null ? 'Copy' : 'Copy ${selection.label}'),
          ),
          OutlinedButton.icon(
            onPressed: _busy ? null : _pasteSelection,
            icon: const Icon(Icons.content_paste_go_outlined, size: 18),
            label: const Text('Paste'),
          ),
          OutlinedButton.icon(
            onPressed: _busy ? null : _showFormatMenu,
            icon: const Icon(Icons.format_color_fill_outlined, size: 18),
            label: const Text('Format'),
          ),
          OutlinedButton.icon(
            onPressed: _busy ? null : _editFormula,
            icon: const Icon(Icons.functions_outlined, size: 18),
            label: const Text('Formula'),
          ),
          OutlinedButton.icon(
            // Only offered when the current selection actually makes a merge
            // sense, so the control never offers an action the manager will
            // refuse.
            onPressed: _busy || !_canMergeSelection ? null : _mergeSelection,
            icon: const Icon(Icons.table_rows_outlined, size: 18),
            label: const Text('Merge'),
          ),
          OutlinedButton.icon(
            onPressed: _busy || !_selectionTouchesMerge()
                ? null
                : _unmergeSelection,
            icon: const Icon(Icons.table_rows_outlined, size: 18),
            label: const Text('Unmerge'),
          ),
          TextButton(
            onPressed: () => setState(() {
              _searchController.clear();
              controller.clearFilters();
              _clearSelection();
            }),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  /// The spreadsheet itself: the existing Excel-like workbook grid.
  ///
  /// [SpreadsheetGridAdapter] projects the controller's delivery rows into the
  /// grid, and every edit is routed straight back through
  /// [SpreadsheetController.setCell], so validation, dirty tracking, save,
  /// discard and the delivery persistence all stay exactly as they were.
  ///
  /// There is deliberately no header row: the first grid row is the first
  /// record, and the cells hold that record's real values.
  Widget _buildWorkbookGrid() {
    final adapter = SpreadsheetGridAdapter(
      widget.controller,
      showRemoved: _showRemoved,
    );
    return WorkbookGridView(
      grid: adapter.build(),
      selectedRow: _anchor?.row ?? 0,
      selectedColumn: _anchor?.column ?? 0,
      selectionAnchor: _anchor,
      onSelectCell: (anchor, cell) => setState(() {
        _anchor = anchor;
        _focus = cell;
      }),
      onEdit: (rowIndex, column, value) {
        // Straight back into the controller: no parallel copy of the data.
        adapter.setCell(rowIndex, column, value);
        setState(() {});
      },
      onSelectionChanged: () => setState(() {}),
    );
  }
}

/// Lets the secretary enter or clear the formula for one cell.
///
/// The live preview is produced by the controller's own evaluator, so the value
/// shown here is exactly the value the grid will show and recalculate after the
/// sheet is reopened. Nothing here writes a weight: a formula stays a
/// spreadsheet calculation.
class _FormulaDialog extends StatefulWidget {
  const _FormulaDialog({
    required this.initialExpression,
    required this.previewFor,
    required this.onSubmit,
  });

  /// The formula already saved for this cell, if any.
  final String? initialExpression;

  /// Evaluates a draft expression and returns the text to show.
  final String Function(String source) previewFor;

  /// Called with the entered expression, or an empty string to clear it.
  final void Function(String expression) onSubmit;

  @override
  State<_FormulaDialog> createState() => _FormulaDialogState();
}

class _FormulaDialogState extends State<_FormulaDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialExpression ?? '',
  );
  String? _preview;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _refresh() {
    final draft = _controller.text.trim();
    setState(() => _preview = draft.isEmpty ? null : widget.previewFor(draft));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Cell formula'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Formula',
                hintText: '=SUM(D1:D10)',
              ),
              onChanged: (_) => _refresh(),
            ),
            const SizedBox(height: 12),
            // The calculated result, updated as the secretary types.
            Text(
              _preview == null ? 'Result: —' : 'Result: $_preview',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Supports SUM, AVERAGE, COUNT, MIN, MAX, cell references, ranges '
              'and + - * /. A formula is a spreadsheet calculation and is never '
              'stored as a delivery bag weight.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        // Clearing removes the stored formula rather than saving a blank one.
        TextButton(
          onPressed: () {
            widget.onSubmit('');
            Navigator.of(context).pop();
          },
          child: const Text('Clear'),
        ),
        FilledButton(
          onPressed: () {
            widget.onSubmit(_controller.text);
            Navigator.of(context).pop();
          },
          child: const Text('Apply'),
        ),
      ],
    );
  }
}
