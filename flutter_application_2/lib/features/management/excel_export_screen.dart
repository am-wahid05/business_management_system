import 'package:flutter/material.dart';

import '../exports/excel_export_service.dart';
import '../../app/app_routes.dart';

class ExcelExportScreen extends StatefulWidget {
  const ExcelExportScreen({required this.service, super.key});

  final ExcelExportService service;

  @override
  State<ExcelExportScreen> createState() => _ExcelExportScreenState();
}

class _ExcelExportScreenState extends State<ExcelExportScreen> {
  final _supplierId = TextEditingController();
  final _supplierName = TextEditingController();
  final _productId = TextEditingController();
  final _productName = TextEditingController();
  final _selectedIds = TextEditingController();
  DateTime _date = DateTime.now();
  bool _working = false;
  String? _message;

  @override
  void dispose() {
    _supplierId.dispose();
    _supplierName.dispose();
    _productId.dispose();
    _productName.dispose();
    _selectedIds.dispose();
    super.dispose();
  }

  Future<void> _export(Future<dynamic> Function() action) async {
    setState(() {
      _working = true;
      _message = null;
    });
    try {
      final file = await action();
      if (mounted) setState(() => _message = 'Exported: ${file.path}');
    } catch (error) {
      if (mounted) setState(() => _message = 'Export failed: $error');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Excel Export')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'Export database records',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          const Text(
            'Excel files are generated from SQLite and saved outside the database.',
          ),
          const SizedBox(height: 12),
          _compactButton(context, OutlinedButton.icon(
            onPressed: () => Navigator.pushNamed(context, AppRoutes.excelImport),
            icon: const Icon(Icons.file_upload_outlined),
            label: const Text('Import historical Excel records'),
          )),
          const SizedBox(height: 24),
          _compactButton(context, OutlinedButton.icon(
            onPressed: _working ? null : _chooseDate,
            icon: const Icon(Icons.calendar_month_outlined),
            label: Text('Daily report: ${_formatDate(_date)}'),
          )),
          const SizedBox(height: 8),
          _compactButton(context, FilledButton.icon(
            onPressed: _working
                ? null
                : () => _export(() => widget.service.exportDaily(_date)),
            icon: const Icon(Icons.file_download_outlined),
            label: const Text('Export daily report'),
          )),
          const SizedBox(height: 24),
          _sectionTitle(context, 'Period reports'),
          const SizedBox(height: 8),
          Row(
            children: [
                Expanded(
                child: _compactButton(context, FilledButton.icon(
                  onPressed: _working
                      ? null
                      : () => _export(
                          () => widget.service.exportMonthly(
                            _date.year,
                            _date.month,
                          ),
                        ),
                  icon: const Icon(Icons.calendar_view_month_outlined),
                  label: const Text('Monthly'),
                )),
              ),
              const SizedBox(width: 12),
                Expanded(
                child: _compactButton(context, FilledButton.icon(
                  onPressed: _working
                      ? null
                      : () => _export(
                          () => widget.service.exportYearly(_date.year),
                        ),
                  icon: const Icon(Icons.calendar_today_outlined),
                  label: const Text('Yearly'),
                )),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _sectionTitle(context, 'Supplier history'),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _supplierId,
                  decoration: const InputDecoration(labelText: 'Supplier ID'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _supplierName,
                  decoration: const InputDecoration(labelText: 'Supplier name'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _compactButton(context, FilledButton.icon(
            onPressed: _working
                ? null
                : () => _export(
                    () => widget.service.exportSupplierHistory(
                      _supplierId.text.trim(),
                      _supplierName.text.trim(),
                    ),
                  ),
            icon: const Icon(Icons.people_outline),
            label: const Text('Export supplier history'),
          )),
          const SizedBox(height: 24),
          _sectionTitle(context, 'Product report'),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _productId,
                  decoration: const InputDecoration(labelText: 'Product ID'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _productName,
                  decoration: const InputDecoration(labelText: 'Product name'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _compactButton(context, FilledButton.icon(
            onPressed: _working
                ? null
                : () => _export(
                    () => widget.service.exportProductReport(
                      _productId.text.trim(),
                      _productName.text.trim(),
                    ),
                  ),
            icon: const Icon(Icons.inventory_2_outlined),
            label: const Text('Export product report'),
          )),
          const SizedBox(height: 24),
          _sectionTitle(context, 'Selected deliveries'),
          const SizedBox(height: 8),
          TextField(
            controller: _selectedIds,
            decoration: const InputDecoration(
              labelText: 'Delivery IDs, separated by commas',
            ),
            maxLines: 2,
          ),
          const SizedBox(height: 8),
          _compactButton(context, FilledButton.icon(
            onPressed: _working
                ? null
                : () => _export(
                    () => widget.service.exportSelected(
                      _selectedIds.text
                          .split(',')
                          .map((id) => id.trim())
                          .where((id) => id.isNotEmpty)
                          .toList(),
                    ),
                  ),
            icon: const Icon(Icons.checklist_outlined),
            label: const Text('Export selected deliveries'),
          )),
          if (_working) ...[
            const SizedBox(height: 20),
            const LinearProgressIndicator(),
          ],
          if (_message != null) ...[
            const SizedBox(height: 20),
            SelectableText(_message!),
          ],
        ],
      ),
    );
  }

  Widget _compactButton(BuildContext context, Widget button) => Align(alignment: Alignment.centerLeft, child: button);

  Future<void> _chooseDate() async {
    final selected = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDate: _date,
    );
    if (selected != null) setState(() => _date = selected);
  }

  static Widget _sectionTitle(BuildContext context, String text) =>
      Text(text, style: Theme.of(context).textTheme.titleLarge);
  static String _formatDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}
