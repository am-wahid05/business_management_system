import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_navigation.dart';
import '../../app/app_ui.dart';
import '../auth/auth_models.dart';
import '../auth/no_access_screen.dart';
import '../imports/excel_import_service.dart';
import '../imports/supplier_import_dialog.dart';
import '../imports/workbook_grid_model.dart';
import '../imports/workbook_grid_store.dart';
import '../imports/workbook_grid_view.dart';
import '../spreadsheet/spreadsheet_clipboard.dart';
import '../suppliers/supplier_repository.dart';

/// Opens the platform file picker and returns the bytes and file name.
///
/// Injected so a test can drive the screen without a real dialog.
typedef WorkbookPicker = Future<(Uint8List bytes, String name)?> Function();

Future<(Uint8List, String)?> pickWorkbookFile() async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    // .xlsm is the same OOXML package as .xlsx; its macro part is ignored and
    // the worksheet data is read exactly as for any other workbook.
    allowedExtensions: const ['xlsx', 'xlsm', 'csv'],
    withData: true,
  );
  if (result == null) return null;
  final file = result.files.single;
  final bytes = file.bytes;
  if (bytes == null) throw StateError('The selected file could not be read');
  return (bytes, file.name);
}

/// The admin/owner rule, kept in one place so a grid can never be opened by a
/// secretary even if the route guard were bypassed.
///
/// This reuses the same role the existing Admin Spreadsheet requires, rather
/// than introducing a second notion of who may see company data.
bool canUseWorkbookGrid(AppUser? user) =>
    user != null && user.role == UserRole.admin;

/// Shows an imported workbook as a spreadsheet.
///
/// This is the "open the file and look at it" path. It deliberately has no
/// column mapping, no delivery validation and no business fields: an imported
/// workbook is not assumed to be a delivery sheet, so a row with no date simply
/// has no date and is never reported as "Invalid date: (empty)".
///
/// The interface is the grid. There is an open button, a worksheet dropdown
/// and a save button, and otherwise the user is looking at cells.
class WorkbookGridScreen extends StatefulWidget {
  const WorkbookGridScreen({
    required this.service,
    required this.store,
    required this.currentUser,
    this.pickFile,
    this.initialBook,
    this.supplierRepository,
    super.key,
  });

  final ExcelImportService service;
  final WorkbookGridStore store;

  /// Read on every build so a role change takes effect straight away. The grid
  /// is an admin tool, so the screen cannot be built without this check.
  final AppUser? Function() currentUser;

  final WorkbookPicker? pickFile;

  /// Opens straight into a workbook, skipping the file picker.
  final WorkbookGridBook? initialBook;

  /// The same repository used by the Suppliers section and ReceivingService.
  /// When omitted, the grid reuses the repository from its existing receiving
  /// service rather than opening another supplier store.
  final SupplierRepository? supplierRepository;

  @override
  State<WorkbookGridScreen> createState() => _WorkbookGridScreenState();
}

class _WorkbookGridScreenState extends State<WorkbookGridScreen> {
  WorkbookGridBook? _book;
  int _sheetIndex = 0;
  int _selectedRow = 0;
  int _selectedColumn = 0;
  bool _busy = false;
  bool _dirty = false;
  String? _message;

  /// The cell the selection was anchored on, so a range can be extended.
  CellPosition? _anchor;

  /// What is waiting on the clipboard, with its types intact.
  WorkbookClipboard? _clipboard;

  String _searchQuery = '';
  List<CellPosition> _searchHits = const [];
  int _searchIndex = 0;

  /// The column the filter is applied to; null means every row is shown.
  ///
  /// This is a view concern only. Filtering never removes a row from the grid.
  int? _filterColumn;
  bool _sortDescending = false;

  /// The currently selected rectangle, always at least one cell.
  CellRange get _selection => _anchor == null
      ? CellRange.single(_selectedColumn, _selectedRow)
      : CellRange.between(
          _anchor!,
          CellPosition(_selectedRow, _selectedColumn),
        );

  /// The grid is an admin/owner tool, as the Admin Spreadsheet already is.
  bool get _isAllowed => canUseWorkbookGrid(widget.currentUser());

  WorkbookGrid? get _grid {
    final book = _book;
    if (book == null || _sheetIndex >= book.sheets.length) return null;
    return book.sheets[_sheetIndex];
  }

  String? get _companyId => widget.currentUser()?.companyId;

  SupplierRepository? get _supplierRepository =>
      widget.supplierRepository ??
      widget.service.receivingService?.supplierRepository;

  @override
  void initState() {
    super.initState();
    if (widget.initialBook != null) _book = widget.initialBook;
  }

  void _notify(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openFile() async {
    if (!_isAllowed) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final picked = await (widget.pickFile ?? pickWorkbookFile)();
      if (picked == null) return;
      final book = widget.service.readWorkbookGrids(picked.$1, picked.$2);
      setState(() {
        _book = book;
        _sheetIndex = 0;
        _selectedRow = 0;
        _selectedColumn = 0;
        _dirty = false;
      });
    } catch (error) {
      setState(() => _message = 'Could not read workbook: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Records an edit on the live grid.
  void _onEdit(int row, int column, String value) {
    final grid = _grid;
    if (grid == null) return;
    grid.setCell(row, column, classifyTypedCell(value));
    setState(() => _dirty = true);
  }

  /// Saves the current worksheet locally, scoped to the signed-in company.
  Future<void> _save() async {
    final grid = _grid;
    final companyId = _companyId;
    if (grid == null) return;
    if (companyId == null) {
      _notify('Select an active company before saving.');
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.store.save(companyId: companyId, grid: grid);
      if (!mounted) return;
      setState(() {
        _dirty = false;
        _message = 'Saved ${grid.name}';
      });
    } catch (error) {
      if (!mounted) return;
      _notify('Could not save: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importSuppliers() async {
    if (!_isAllowed) return;
    final book = _book;
    final repository = _supplierRepository;
    if (book == null || book.sheets.isEmpty) return;
    if (repository == null) {
      _notify(
        'Supplier import is unavailable because no supplier repository is connected.',
      );
      return;
    }
    if (repository.usesCompanyScope &&
        (repository.activeCompanyId == null ||
            repository.activeCompanyId!.trim().isEmpty)) {
      _notify('Supplier import requires an active company.');
      return;
    }

    final result = await showDialog<SupplierBulkImportResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => SupplierImportDialog(book: book, repository: repository),
    );
    if (!mounted || result == null) return;
    final summary =
        'Supplier import complete\n'
        'Created: ${result.createdCount}\n'
        'Already existed: ${result.alreadyExisted}\n'
        'Skipped: ${result.skipped}';
    setState(() => _message = summary);
    _notify(summary);
  }

  /// Reopens a previously saved copy of the current worksheet, if there is one.
  ///
  /// The original file on disk is never touched; this only replaces what is on
  /// screen with the local saved copy.
  Future<void> _reopenSaved() async {
    final book = _book;
    final companyId = _companyId;
    final grid = _grid;
    if (book == null || companyId == null || grid == null) return;
    final saved = await widget.store.load(
      companyId: companyId,
      filename: book.filename,
      sheetName: grid.name,
    );
    if (saved == null) {
      _notify('No saved copy of ${grid.name} yet.');
      return;
    }
    setState(() {
      book.sheets[_sheetIndex] = saved;
      _dirty = false;
      _message = 'Reopened saved ${saved.name}';
    });
  }

  void _selectSheet(int index) {
    setState(() {
      _sheetIndex = index;
      _selectedRow = 0;
      _selectedColumn = 0;
      _filterColumn = null;
      _searchHits = const [];
      _searchIndex = 0;
    });
  }

  // ---- search -------------------------------------------------------------

  void _onSearch(String query) {
    final grid = _grid;
    if (grid == null) return;
    setState(() {
      _searchQuery = query;
      _searchHits = grid.search(query);
      _searchIndex = 0;
      if (_searchHits.isNotEmpty) {
        _selectedRow = _searchHits.first.row;
        _selectedColumn = _searchHits.first.column;
      }
    });
  }

  /// Steps to the next match, wrapping to the first one at the end.
  void _nextMatch() {
    if (_searchHits.isEmpty) return;
    setState(() {
      _searchIndex = (_searchIndex + 1) % _searchHits.length;
      _selectedRow = _searchHits[_searchIndex].row;
      _selectedColumn = _searchHits[_searchIndex].column;
    });
  }

  // ---- filter -------------------------------------------------------------

  void _setFilterColumn(int? column) {
    setState(() => _filterColumn = column);
  }

  // ---- sort ---------------------------------------------------------------

  void _sortBy(int column) {
    final grid = _grid;
    if (grid == null) return;
    final blocked = grid.sortBlockedReason;
    if (blocked != null) {
      _notify(blocked);
      return;
    }
    setState(() {
      if (grid.sortByColumn(column, ascending: !_sortDescending)) {
        _sortDescending = !_sortDescending;
        _notify(
          'Sorted by ${columnLetter(column)}'
          '${_sortDescending ? ' (descending)' : ' (ascending)'}',
        );
      }
    });
  }

  // ---- copy and paste -----------------------------------------------------

  Future<void> _copy() async {
    final grid = _grid;
    if (grid == null) return;
    _clipboard = grid.copyRange(_selection);
    // The plain text also goes to the system clipboard so the block can be
    // pasted into another application.
    await Clipboard.setData(ClipboardData(text: _clipboard!.toText));
    _notify('Copied ${_selection.label}');
  }

  void _paste() {
    final grid = _grid;
    final clipboard = _clipboard;
    if (grid == null || clipboard == null) {
      _notify('Copy some cells first.');
      return;
    }
    setState(() {
      final written = grid.pasteClipboard(
        clipboard,
        _selectedRow,
        _selectedColumn,
      );
      _dirty = true;
      _notify('Pasted into $written cells');
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_isAllowed) return const NoAccessScreen();
    final book = _book;
    final grid = _grid;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Excel Import'),
        actions: [
          IconButton(
            tooltip: 'Open a workbook',
            onPressed: _busy ? null : _openFile,
            icon: const Icon(Icons.folder_open_outlined),
          ),
          IconButton(
            tooltip: 'Reopen the last saved copy',
            onPressed: _busy || book == null ? null : _reopenSaved,
            icon: const Icon(Icons.history),
          ),
          IconButton(
            tooltip: 'Save',
            onPressed: _busy || grid == null ? null : _save,
            icon: const Icon(Icons.save_outlined),
          ),
          IconButton(
            tooltip: 'Copy the selected cells',
            onPressed: grid == null ? null : _copy,
            icon: const Icon(Icons.content_copy_outlined),
          ),
          IconButton(
            tooltip: 'Paste into the selected cell',
            onPressed: grid == null ? null : _paste,
            icon: const Icon(Icons.content_paste_outlined),
          ),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1),
        ),
      ),
      drawer: shellDrawerFor(context),
      body: _busy && (book == null || grid == null)
          ? const Padding(
              padding: EdgeInsets.all(24),
              child: AppGridSkeleton(rows: 8, columns: 6),
            )
          : book == null || grid == null
          ? AppEmptyState(
              title: 'No workbook open',
              message: 'Open an Excel workbook to review and edit its sheets.',
              icon: Icons.table_chart_outlined,
              action: FilledButton.icon(
                onPressed: _busy ? null : _openFile,
                icon: const Icon(Icons.folder_open_outlined),
                label: const Text('Open workbook'),
              ),
            )
          : Column(
              children: [
                // A worksheet is chosen explicitly. The first tab is never
                // treated as "the" data sheet just because it came first.
                // The control bar scrolls sideways on a narrow screen rather than
                // overflowing it. Scrolling hands the Row an unbounded width,
                // which is safe here only because both DropdownButtons below
                // are given a fixed width of their own.
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    child: Row(
                      children: [
                        // The worksheet is always chosen explicitly. The first
                        // tab is never treated as "the" data sheet.
                        SizedBox(
                          width: 200,
                          child: DropdownButton<int>(
                            isExpanded: true,
                            value: _sheetIndex,
                            onChanged: (value) {
                              if (value != null) _selectSheet(value);
                            },
                            items: [
                              for (
                                var index = 0;
                                index < book.sheets.length;
                                index++
                              )
                                DropdownMenuItem(
                                  value: index,
                                  child: Text(book.sheets[index].name),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        // A fixed width, not Expanded: this Row scrolls
                        // horizontally, which makes its width unbounded, and an
                        // Expanded inside an unbounded Row is exactly what throws
                        // "RenderFlex children have non-zero flex but incoming
                        // width constraints are unbounded".
                        SizedBox(
                          width: 240,
                          child: TextField(
                            onChanged: _onSearch,
                            decoration: InputDecoration(
                              isDense: true,
                              prefixIcon: const Icon(Icons.search, size: 18),
                              hintText: 'Search this sheet',
                              border: const OutlineInputBorder(),
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Next match',
                          onPressed: _searchHits.isEmpty ? null : _nextMatch,
                          icon: const Icon(Icons.navigate_next),
                        ),
                        if (_searchHits.isNotEmpty)
                          Text(
                            '${_searchIndex + 1}/${_searchHits.length}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        const SizedBox(width: 16),
                        // Filtering and sorting work on any column the sheet
                        // actually has; nothing here assumes a business column.
                        //
                        // The width is fixed deliberately. A DropdownButton lays
                        // its label out with a Row that has a Flexible child, so
                        // it needs a bounded width. This toolbar is a Row inside a
                        // horizontally scrolling area, which can hand its children
                        // unbounded width, and an unbounded width made the button
                        // throw "RenderFlex children have non-zero flex but
                        // incoming width constraints are unbounded".
                        SizedBox(
                          width: 170,
                          child: DropdownButton<int?>(
                            isExpanded: true,
                            value: _filterColumn,
                            hint: const Text('Filter by column'),
                            onChanged: _setFilterColumn,
                            items: [
                              const DropdownMenuItem<int?>(
                                value: null,
                                child: Text('No filter'),
                              ),
                              for (
                                var column = 0;
                                column < grid.columnCount;
                                column++
                              )
                                DropdownMenuItem<int?>(
                                  value: column,
                                  child: Text('Filter ${columnLetter(column)}'),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Tells the user there are edits that are only in memory.
                        if (_dirty)
                          const Text(
                            'Unsaved changes',
                            style: TextStyle(fontSize: 11),
                          ),
                        const SizedBox(width: 8),
                        PopupMenuButton<int>(
                          tooltip: 'Sort by column',
                          onSelected: _sortBy,
                          itemBuilder: (context) => [
                            for (
                              var column = 0;
                              column < grid.columnCount;
                              column++
                            )
                              PopupMenuItem(
                                value: column,
                                child: Text('Sort by ${columnLetter(column)}'),
                              ),
                          ],
                          icon: const Icon(Icons.sort),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          key: const ValueKey('import-suppliers-action'),
                          onPressed: _busy ? null : _importSuppliers,
                          icon: const Icon(Icons.person_add_alt_1),
                          label: const Text('Import Suppliers'),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_filterColumn != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Showing ${grid.visibleRows(query: _searchQuery, column: _filterColumn).length}'
                        ' of ${grid.rowCount} rows — filtering only hides rows, '
                        'nothing is deleted.',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                  ),
                Expanded(
                  child: WorkbookGridView(
                    key: ValueKey('${book.filename}:${grid.name}'),
                    grid: grid,
                    selectedRow: _selectedRow,
                    selectedColumn: _selectedColumn,
                    selectionAnchor: _anchor,
                    onSelectCell: (anchor, cell) {
                      setState(() {
                        _anchor = anchor;
                        _selectedRow = cell.row;
                        _selectedColumn = cell.column;
                      });
                    },
                    onEdit: _onEdit,
                    onSelectionChanged: () => setState(() {}),
                    visibleRows: _filterColumn == null
                        ? null
                        : grid.visibleRows(
                            query: _searchQuery,
                            column: _filterColumn,
                          ),
                  ),
                ),
                if (_message != null)
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      _message!,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
              ],
            ),
    );
  }
}
