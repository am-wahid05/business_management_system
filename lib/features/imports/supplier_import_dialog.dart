import 'package:flutter/material.dart';

import '../suppliers/supplier_repository.dart';
import 'supplier_name_detector.dart';
import 'workbook_grid_model.dart';

/// Confirms a supplier-name import from the workbook grid before any write.
class SupplierImportDialog extends StatefulWidget {
  const SupplierImportDialog({
    required this.book,
    required this.repository,
    super.key,
  });

  final WorkbookGridBook book;
  final SupplierRepository repository;

  @override
  State<SupplierImportDialog> createState() => _SupplierImportDialogState();
}

class _SupplierImportDialogState extends State<SupplierImportDialog> {
  static const _detector = SupplierNameDetector();

  int _sheetIndex = 0;
  int? _columnIndex;
  Set<String> _selectedNames = {};
  bool _loading = true;
  bool _importing = false;
  String? _error;

  WorkbookGrid get _grid => widget.book.sheets[_sheetIndex];

  SupplierDetection? get _detection {
    final column = _columnIndex;
    if (column == null) return null;
    return _detector.detect(
      grid: _grid,
      column: column,
      existingNames: widget.repository.suppliers.map(
        (supplier) => supplier.name,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    if (widget.book.sheets.isNotEmpty) {
      _columnIndex = _detector.suggestColumn(_grid);
    }
    _loadSuppliers();
  }

  Future<void> _loadSuppliers() async {
    final repository = widget.repository;
    if (repository.usesCompanyScope &&
        (repository.activeCompanyId == null ||
            repository.activeCompanyId!.trim().isEmpty)) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Supplier import requires an active company.';
        });
      }
      return;
    }
    try {
      await repository.initialize();
      if (!mounted) return;
      setState(() {
        _loading = false;
        _selectAllNew();
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load suppliers: $error';
      });
    }
  }

  void _selectAllNew() {
    _selectedNames = {
      for (final entry in _detection?.toCreate ?? const <DetectedSupplier>[])
        SupplierNameDetector.key(entry.name),
    };
  }

  void _selectSheet(int index) {
    setState(() {
      _sheetIndex = index;
      _columnIndex = _detector.suggestColumn(_grid);
      _selectAllNew();
    });
  }

  void _selectColumn(int? column) {
    setState(() {
      _columnIndex = column;
      _selectAllNew();
    });
  }

  Future<void> _importSelected() async {
    final detection = _detection;
    if (detection == null) return;
    final selected = detection.toCreate
        .where(
          (entry) =>
              _selectedNames.contains(SupplierNameDetector.key(entry.name)),
        )
        .map((entry) => entry.name)
        .toList(growable: false);
    if (selected.isEmpty) return;

    setState(() {
      _importing = true;
      _error = null;
    });
    try {
      final result = await widget.repository.importNames(selected);
      if (!mounted) return;
      Navigator.of(context).pop(result);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _importing = false;
        _error = 'Could not import suppliers: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final detection = _detection;
    final newEntries = detection?.toCreate ?? const <DetectedSupplier>[];
    final existingEntries = detection?.existing ?? const <DetectedSupplier>[];
    final duplicateCount =
        detection?.ignored
            .where((entry) => entry.reason == 'Repeated in this file')
            .length ??
        0;
    final ignoredCount =
        detection?.ignored
            .where((entry) => entry.reason != 'Repeated in this file')
            .length ??
        0;

    return AlertDialog(
      title: const Text('Import Suppliers'),
      content: SizedBox(
        width: 520,
        height: 520,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.book.sheets.length > 1) ...[
              const Text('Worksheet'),
              DropdownButton<int>(
                key: const ValueKey('supplier-import-sheet'),
                isExpanded: true,
                value: _sheetIndex,
                onChanged: _loading || _importing
                    ? null
                    : (value) {
                        if (value != null) _selectSheet(value);
                      },
                items: [
                  for (
                    var index = 0;
                    index < widget.book.sheets.length;
                    index++
                  )
                    DropdownMenuItem(
                      value: index,
                      child: Text(widget.book.sheets[index].name),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            const Text('Supplier column'),
            DropdownButton<int>(
              key: const ValueKey('supplier-import-column'),
              isExpanded: true,
              value: _columnIndex,
              hint: const Text('Select a column'),
              onChanged: _loading || _importing ? null : _selectColumn,
              items: [
                for (var column = 0; column < _grid.columnCount; column++)
                  DropdownMenuItem(
                    value: column,
                    child: Text(_columnLabel(column)),
                  ),
              ],
            ),
            if (_columnIndex == null && !_loading)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text('Choose the column containing supplier names.'),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  _error!,
                  key: const ValueKey('supplier-import-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (_loading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (detection == null)
              const Expanded(child: SizedBox.shrink())
            else ...[
              Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  Text('New suppliers: ${newEntries.length}'),
                  Text('Already existing: ${existingEntries.length}'),
                  Text('Duplicates in workbook: $duplicateCount'),
                  Text('Ignored rows: $ignoredCount'),
                ],
              ),
              Row(
                children: [
                  TextButton(
                    onPressed: _importing
                        ? null
                        : () => setState(_selectAllNew),
                    child: const Text('Select All'),
                  ),
                  TextButton(
                    onPressed: _importing
                        ? null
                        : () => setState(() => _selectedNames.clear()),
                    child: const Text('Clear All'),
                  ),
                ],
              ),
              Expanded(
                child: ListView(
                  key: const ValueKey('supplier-import-preview'),
                  children: [
                    if (newEntries.isNotEmpty)
                      const ListTile(dense: true, title: Text('New suppliers')),
                    for (final entry in newEntries)
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(entry.name),
                        value: _selectedNames.contains(
                          SupplierNameDetector.key(entry.name),
                        ),
                        onChanged: _importing
                            ? null
                            : (checked) => setState(() {
                                final key = SupplierNameDetector.key(
                                  entry.name,
                                );
                                if (checked == true) {
                                  _selectedNames.add(key);
                                } else {
                                  _selectedNames.remove(key);
                                }
                              }),
                      ),
                    if (existingEntries.isNotEmpty)
                      const ListTile(
                        dense: true,
                        title: Text('Already in this company'),
                      ),
                    for (final entry in existingEntries)
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.check_circle_outline),
                        title: Text(entry.name),
                        subtitle: const Text(
                          'Already exists; it will not be created again.',
                        ),
                      ),
                    if (newEntries.isEmpty && existingEntries.isEmpty)
                      const ListTile(
                        title: Text('No supplier names found in this column.'),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _importing ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed:
              _loading || _importing || _selectedNames.isEmpty || _error != null
              ? null
              : _importSelected,
          child: _importing
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Import Selected'),
        ),
      ],
    );
  }

  String _columnLabel(int column) {
    final heading = _grid.rowCount == 0
        ? ''
        : _grid.displayAt(0, column).label.trim();
    return heading.isEmpty
        ? 'Column ${columnLetter(column)}'
        : '${columnLetter(column)} · $heading';
  }
}
