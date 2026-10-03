import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../imports/excel_import_service.dart';

class ExcelImportScreen extends StatefulWidget {
  const ExcelImportScreen({required this.service, super.key});

  final ExcelImportService service;

  @override
  State<ExcelImportScreen> createState() => _ExcelImportScreenState();
}

class _ExcelImportScreenState extends State<ExcelImportScreen> {
  ImportWorkbook? _workbook;
  ImportSheet? _sheet;
  ImportMapping? _mapping;
  ImportValidation? _validation;
  ImportSummary? _summary;
  bool _working = false;
  String? _error;

  Future<void> _selectFile() async {
    setState(() { _working = true; _error = null; _summary = null; });
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['xlsx'], withData: true);
      if (result == null) return;
      final file = result.files.single;
      final bytes = file.bytes;
      if (bytes == null) throw StateError('The selected file could not be read');
      final workbook = widget.service.readWorkbook(bytes, file.name);
      setState(() { _workbook = workbook; _sheet = workbook.sheets.values.first; _mapping = null; _validation = null; });
    } catch (error) {
      setState(() => _error = 'Could not read workbook: $error');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _mapAndValidate() async {
    final sheet = _sheet;
    if (sheet == null) return;
    final mapping = ImportMapping({
      ImportField.date: _guess(sheet, ['date', 'received date']),
      ImportField.supplierId: _guess(sheet, ['supplier id', 'supplier code', 'id']),
      ImportField.supplierName: _guess(sheet, ['supplier name', 'name', 'farmer']),
      ImportField.supplierType: _guess(sheet, ['supplier type', 'type']),
      ImportField.town: _guess(sheet, ['town', 'location']),
      ImportField.district: _guess(sheet, ['district']),
      ImportField.region: _guess(sheet, ['region']),
      ImportField.productId: _guess(sheet, ['product id', 'product code']),
      ImportField.productName: _guess(sheet, ['product', 'product name', 'commodity']),
      ImportField.totalWeight: _guess(sheet, ['total weight', 'weight', 'total kg']),
      ImportField.bagWeights: _guess(sheet, ['bag weights', 'weights', 'individual weights']),
      ImportField.recordedBy: _guess(sheet, ['recorded by', 'staff', 'secretary']),
    });
    setState(() => _mapping = mapping);
    final validation = await widget.service.validateAsync(sheet, mapping);
    if (mounted) setState(() => _validation = validation);
  }

  Future<void> _confirmImport() async {
    final validation = _validation;
    final workbook = _workbook;
    if (validation == null || workbook == null) return;
    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(title: const Text('Confirm import'), content: Text('Import ${validation.validCount} valid records? Warnings will be skipped and existing likely duplicates will not be overwritten.'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Import'))]));
    if (confirmed != true) return;
    setState(() { _working = true; _error = null; });
    try {
      final summary = await widget.service.importValid(workbook.filename, validation);
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
      appBar: AppBar(title: const Text('Historical Excel Import')),
      body: ListView(padding: const EdgeInsets.all(24), children: [
        Text('Controlled historical import', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 8),
        const Text('Historical files are previewed, mapped, validated, and confirmed before any records are written.'),
        const SizedBox(height: 20),
        FilledButton.icon(onPressed: _working ? null : _selectFile, icon: const Icon(Icons.folder_open_outlined), label: const Text('Select Excel file')),
        if (_workbook != null) ...[
          const SizedBox(height: 20),
          Text('Sheets', style: Theme.of(context).textTheme.titleLarge),
          DropdownButton<String>(value: _sheet?.name, items: _workbook!.sheets.keys.map((name) => DropdownMenuItem(value: name, child: Text(name))).toList(), onChanged: (name) => setState(() { _sheet = _workbook!.sheets[name]; _validation = null; })),
        ],
        if (sheet != null) ...[
          const SizedBox(height: 12),
          Text('Preview: ${sheet.rows.length} rows', style: Theme.of(context).textTheme.titleLarge),
          SingleChildScrollView(scrollDirection: Axis.horizontal, child: DataTable(columns: sheet.headers.map((header) => DataColumn(label: Text(header))).toList(), rows: sheet.rows.take(5).map((row) => DataRow(cells: List.generate(sheet.headers.length, (index) => DataCell(Text(index < row.length ? row[index] : ''))))).toList())),
          const SizedBox(height: 16),
          OutlinedButton.icon(onPressed: _mapAndValidate, icon: const Icon(Icons.rule_outlined), label: const Text('Map columns and validate')),
        ],
        if (_mapping != null) ...[
          const SizedBox(height: 16),
          Text('Column mapping', style: Theme.of(context).textTheme.titleLarge),
          const Text('Adjust the guessed mappings for this historical workbook, then validate again.'),
          if (sheet != null) ...ImportField.values.map((field) => _mappingDropdown(sheet, field)),
        ],
        if (validation != null) ...[
          const SizedBox(height: 16),
          Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Validation results', style: Theme.of(context).textTheme.titleLarge), Text('Valid: ${validation.validCount}'), Text('Warnings / likely duplicates: ${validation.warningCount}'), Text('Failed: ${validation.failedCount}'), const SizedBox(height: 8), ...validation.rows.where((row) => !row.isValid || row.warning != null).take(20).map((row) => Text('Row ${row.rowNumber}: ${row.error ?? row.warning}'))]))),
          const SizedBox(height: 12),
          FilledButton.icon(onPressed: _working || validation.validCount == 0 ? null : _confirmImport, icon: const Icon(Icons.file_upload_outlined), label: const Text('Confirm and import valid records')),
        ],
        if (_summary != null) ...[const SizedBox(height: 20), Card(child: Padding(padding: const EdgeInsets.all(16), child: Text('Import complete\nRows: ${_summary!.rowsTotal}\nImported: ${_summary!.imported}\nSkipped: ${_summary!.skipped}\nFailed: ${_summary!.failed}')))],
        if (_working) ...[const SizedBox(height: 20), const LinearProgressIndicator()],
        if (_error != null) ...[const SizedBox(height: 20), Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))],
      ]),
    );
  }

  static String? _guess(ImportSheet sheet, List<String> candidates) {
    for (final header in sheet.headers) {
      final normalized = header.trim().toLowerCase();
      if (candidates.any((candidate) => normalized == candidate || normalized.contains(candidate))) return header;
    }
    return null;
  }

  Widget _mappingDropdown(ImportSheet sheet, ImportField field) {
    final current = _mapping?.column(field);
    return DropdownButtonFormField<String?>(
      initialValue: current,
      decoration: InputDecoration(labelText: field.name),
      items: [
        const DropdownMenuItem<String?>(value: null, child: Text('Not mapped')),
        ...sheet.headers.map((header) => DropdownMenuItem(value: header, child: Text(header))),
      ],
      onChanged: (value) {
        final columns = Map<ImportField, String?>.from(_mapping?.columns ?? {});
        columns[field] = value;
        setState(() { _mapping = ImportMapping(columns); _validation = null; });
      },
    );
  }
}
