import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../auth/auth_models.dart';
import '../imports/excel_import_service.dart';
import '../imports/import_header_detector.dart';
import '../imports/workbook_grid_store.dart';
import 'workbook_grid_screen.dart';

class ExcelImportScreen extends StatefulWidget {
  const ExcelImportScreen({
    required this.service,
    this.currentUser,
    this.gridStore,
    super.key,
  });

  final ExcelImportService service;

  /// The signed-in user, so the spreadsheet view keeps the same admin-only rule
  /// as the import screen itself.
  final AppUser? Function()? currentUser;

  /// Where an opened grid is saved. Injected so saving stays testable and so
  /// the store keeps using the application's existing database.
  final WorkbookGridStore? gridStore;

  @override
  State<ExcelImportScreen> createState() => _ExcelImportScreenState();
}

class _ExcelImportScreenState extends State<ExcelImportScreen> {
  ImportWorkbook? _workbook;
  ImportSheet? _sheet;
  ImportMapping? _mapping;
  List<ImportDraft> _drafts = const [];
  ImportValidation? _validation;
  ImportSummary? _summary;
  bool _working = false;
  String? _error;

  /// The bytes of the file that was opened, kept so the same file can also be
  /// shown as a plain spreadsheet instead of being mapped to delivery fields.
  ///
  /// The file on disk is never written to; this only remembers what was read.
  List<int>? _loadedBytes;
  String? _loadedName;

  /// Opens the file that is already loaded as a spreadsheet grid.
  ///
  /// A real workbook is not a delivery sheet, so the mapping flow above is not
  /// always what the user wants. This offers the same file as a grid, with its
  /// own rows, columns and cells, and no business fields imposed on it.
  void _openAsSpreadsheet() {
    final bytes = _loadedBytes;
    final name = _loadedName;
    if (bytes == null || name == null) return;
    final book = widget.service.readWorkbookGrids(
      Uint8List.fromList(bytes),
      name,
    );
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => WorkbookGridScreen(
          service: widget.service,
          store: widget.gridStore ?? const WorkbookGridStore(null),
          currentUser: widget.currentUser ?? () => null,
          initialBook: book,
        ),
      ),
    );
  }

  Future<void> _selectFile() async {
    setState(() {
      _working = true;
      _error = null;
      _summary = null;
    });
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        // .xlsm is the same OOXML package as .xlsx; its macro part is ignored
        // and the worksheet data is imported normally.
        allowedExtensions: const ['xlsx', 'xlsm', 'csv'],
        withData: true,
      );
      if (result == null) return;
      final file = result.files.single;
      final bytes = file.bytes;
      if (bytes == null) {
        throw StateError('The selected file could not be read');
      }
      final workbook = widget.service.readWorkbook(bytes, file.name);
      setState(() {
        // Remembered so the same file can also be shown as a grid.
        _loadedBytes = bytes;
        _loadedName = file.name;
        _workbook = workbook;
        _sheet = workbook.sheets.values.first;
        _mapping = null;
        _validation = null;
        _drafts = const [];
      });
    } catch (error) {
      setState(() => _error = 'Could not read workbook: $error');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  /// Builds drafts from the detected mapping and validates them.
  Future<void> _mapAndValidate() async {
    final sheet = _sheet;
    if (sheet == null) return;
    final mapping = guessMapping(sheet.headers);
    setState(() {
      _mapping = mapping;
      _drafts = widget.service.buildDrafts(sheet, mapping);
    });
    await _revalidate();
  }

  /// Re-runs validation, so an edit in the preview is reflected immediately.
  Future<void> _revalidate() async {
    final sheet = _sheet;
    final mapping = _mapping;
    if (sheet == null || mapping == null) return;
    final validation = await widget.service.validateDrafts(
      _drafts,
      sheet,
      mapping,
    );
    if (!mounted) return;
    setState(() => _validation = validation);
  }

  Future<void> _confirmImport() async {
    final validation = _validation;
    final workbook = _workbook;
    if (validation == null || workbook == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm import'),
        content: Text(
          'Import ${validation.validCount} valid records? '
          'Rows with errors are skipped and existing records are not overwritten.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Import'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final summary = await widget.service.importValid(
        workbook.filename,
        validation,
      );
      setState(() => _summary = summary);
    } catch (error) {
      setState(() => _error = 'Import failed: $error');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sheet = _sheet;
    final validation = _validation;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Historical Excel Import'),
        actions: [
          // The loaded file can be shown as a plain spreadsheet. A real
          // workbook is not a delivery sheet, so this is the path for a file
          // the user only wants to see and edit.
          IconButton(
            tooltip: 'Open as a spreadsheet',
            onPressed: _loadedBytes == null || _working
                ? null
                : _openAsSpreadsheet,
            icon: const Icon(Icons.grid_on_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'Controlled historical import',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          const Text(
            'Files are previewed, mapped and validated before anything is '
            'saved. Nothing is written until you confirm.',
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _working ? null : _selectFile,
            icon: const Icon(Icons.folder_open_outlined),
            label: const Text('Select Excel file'),
          ),
          if (_workbook != null) ...[
            const SizedBox(height: 20),
            Text('Sheets', style: Theme.of(context).textTheme.titleLarge),
            DropdownButton<String>(
              value: _sheet?.name,
              items: _workbook!.sheets.keys
                  .map(
                    (name) => DropdownMenuItem(value: name, child: Text(name)),
                  )
                  .toList(),
              onChanged: (name) => setState(() {
                _sheet = _workbook!.sheets[name];
                _validation = null;
                _drafts = const [];
              }),
            ),
          ],
          if (sheet != null) ...[
            const SizedBox(height: 12),
            Text(
              'File preview: ${sheet.rows.length} rows',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            _rawPreview(sheet),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _mapAndValidate,
              icon: const Icon(Icons.rule_outlined),
              label: const Text('Map columns and build import preview'),
            ),
          ],
          if (sheet != null && _mapping != null) ...[
            const SizedBox(height: 24),
            Text(
              'Column mapping',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              'Check the detected columns. Product ID is optional; it is '
              'inferred from the product name when it is not supplied.',
            ),
            ...ImportField.values.map(
              (field) => _mappingDropdown(sheet, field),
            ),
          ],
          if (_drafts.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text(
              'Import preview',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              'These rows are not saved yet. You can correct a value inline; '
              'rows with errors are highlighted and will be skipped.',
            ),
            const SizedBox(height: 12),
            _draftPreview(),
          ],
          if (validation != null) ...[
            const SizedBox(height: 16),
            _validationCard(validation),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _working || validation.validCount == 0
                  ? null
                  : _confirmImport,
              icon: const Icon(Icons.file_upload_outlined),
              label: const Text('Save and import valid records'),
            ),
          ],
          if (_summary != null) ...[const SizedBox(height: 20), _summaryCard()],
          if (_working) ...[
            const SizedBox(height: 20),
            const LinearProgressIndicator(),
          ],
          if (_error != null) ...[
            const SizedBox(height: 20),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }

  /// A read-only view of the file exactly as it was read.
  Widget _rawPreview(ImportSheet sheet) {
    final rows = sheet.rows.take(5).toList();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: sheet.headers
            .map((header) => DataColumn(label: Text(header)))
            .toList(),
        rows: rows
            .map(
              (row) => DataRow(
                cells: List.generate(
                  sheet.headers.length,
                  (index) =>
                      DataCell(Text(index < row.length ? row[index].text : '')),
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  /// The editable import preview, built with a plain DataTable so that no extra
  /// spreadsheet package is required.
  Widget _draftPreview() {
    final theme = Theme.of(context);
    final preview = _drafts.take(50).toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowHeight: 44,
            dataRowMinHeight: 48,
            dataRowMaxHeight: 60,
            columns: const [
              DataColumn(label: Text('Row')),
              DataColumn(label: Text('Date')),
              DataColumn(label: Text('Supplier')),
              DataColumn(label: Text('Product')),
              DataColumn(label: Text('Total Weight')),
              DataColumn(label: Text('Bag Weights')),
              DataColumn(label: Text('Status')),
            ],
            rows: preview
                .map(
                  (draft) => DataRow(
                    color: draft.hasError
                        ? WidgetStatePropertyAll(
                            theme.colorScheme.errorContainer.withValues(
                              alpha: 0.35,
                            ),
                          )
                        : null,
                    cells: [
                      DataCell(Text('${draft.rowNumber}')),
                      _editCell(
                        draft,
                        draft.date,
                        (value) => draft.date = value,
                      ),
                      _editCell(
                        draft,
                        draft.supplierName,
                        (value) => draft.supplierName = value,
                      ),
                      _editCell(
                        draft,
                        draft.productName,
                        (value) => draft.productName = value,
                      ),
                      _editCell(
                        draft,
                        draft.totalWeight,
                        (value) => draft.totalWeight = value,
                      ),
                      _editCell(
                        draft,
                        draft.bagWeights,
                        (value) => draft.bagWeights = value,
                      ),
                      DataCell(
                        Text(
                          draft.error ?? 'Ready',
                          style: TextStyle(
                            color: draft.hasError
                                ? theme.colorScheme.error
                                : null,
                            fontWeight: draft.hasError
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
                .toList(),
          ),
        ),
      ),
    );
  }

  /// An editable preview cell. Every edit re-runs validation, so the status
  /// shown always reflects the value that would actually be imported.
  DataCell _editCell(
    ImportDraft draft,
    String value,
    ValueChanged<String> onChanged,
  ) => DataCell(
    SizedBox(
      width: 150,
      child: TextFormField(
        initialValue: value,
        decoration: const InputDecoration(
          isDense: true,
          border: OutlineInputBorder(),
        ),
        onChanged: (text) {
          onChanged(text);
          _revalidate();
        },
      ),
    ),
  );

  Widget _validationCard(ImportValidation validation) {
    final problems = validation.rows
        .where((row) => !row.isValid || row.warning != null)
        .toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Validation results',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text('Ready to import: ${validation.validCount}'),
            Text('Likely duplicates: ${validation.warningCount}'),
            Text('Rejected: ${validation.failedCount}'),
            if (problems.isNotEmpty) ...[
              const SizedBox(height: 12),
              ...problems
                  .take(20)
                  .map(
                    (row) => Text(
                      'Row ${row.rowNumber}: ${row.error ?? row.warning}',
                      style: TextStyle(
                        color: row.isValid
                            ? null
                            : Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _summaryCard() {
    final summary = _summary!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Import complete',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text('${summary.imported} records imported'),
            Text('${summary.suppliersCreated} suppliers created'),
            Text('${summary.skipped} rows skipped'),
            Text('${summary.failed} rows rejected'),
          ],
        ),
      ),
    );
  }

  Widget _mappingDropdown(ImportSheet sheet, ImportField field) {
    final current = _mapping?.column(field);
    // Header labels are used as mapping values. Workbooks sometimes repeat a
    // label (for example two columns both named "DATE"), which would create
    // multiple DropdownMenuItems with the same value and trigger Flutter's
    // DropdownButton assertion. Keep one item per distinct label; the importer
    // also resolves these labels to the first matching source column.
    final uniqueHeaders = sheet.headers.toSet().toList(growable: false);
    final availableValue = current != null && uniqueHeaders.contains(current)
        ? current
        : null;
    return DropdownButtonFormField<String?>(
      initialValue: availableValue,
      decoration: InputDecoration(labelText: field.name),
      items: [
        const DropdownMenuItem<String?>(value: null, child: Text('Not mapped')),
        ...uniqueHeaders.map(
          (header) => DropdownMenuItem(value: header, child: Text(header)),
        ),
      ],
      onChanged: (value) {
        final columns = Map<ImportField, String?>.from(_mapping?.columns ?? {});
        columns[field] = value;
        final mapping = ImportMapping(columns);
        // Drafts are rebuilt from the file so the edited values are not lost.
        setState(() {
          _mapping = mapping;
          _drafts = widget.service.buildDrafts(sheet, mapping);
        });
        _revalidate();
      },
    );
  }
}
