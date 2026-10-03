import 'package:flutter/material.dart';

import '../../domain/models/supplier.dart';
import 'supplier_statement.dart';

class SupplierStatementScreen extends StatefulWidget {
  const SupplierStatementScreen({
    required this.supplier,
    required this.service,
    required this.exporter,
    super.key,
  });

  final Supplier supplier;
  final SupplierStatementService service;
  final SupplierStatementExporter exporter;

  @override
  State<SupplierStatementScreen> createState() => _SupplierStatementScreenState();
}

class _SupplierStatementScreenState extends State<SupplierStatementScreen> {
  late DateTime _from;
  late DateTime _to;
  late Future<SupplierStatement> _statement;
  bool _exporting = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    _from = DateTime(today.year, 1, 1);
    _to = DateTime(today.year, today.month, today.day);
    _load();
  }

  void _load() {
    _statement = widget.service.build(
      supplier: widget.supplier,
      from: _from,
      to: _to,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${widget.supplier.name} Statement')),
      body: FutureBuilder<SupplierStatement>(
        future: _statement,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Could not load statement: ${snapshot.error}'));
          }
          final statement = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text('Supplier statement', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 8),
              Text(statement.supplier.name, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 20),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  OutlinedButton.icon(
                    onPressed: _exporting ? null : () => _chooseDate(isFrom: true),
                    icon: const Icon(Icons.calendar_month_outlined),
                    label: Text('From: ${_formatDate(_from)}'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _exporting ? null : () => _chooseDate(isFrom: false),
                    icon: const Icon(Icons.calendar_month_outlined),
                    label: Text('To: ${_formatDate(_to)}'),
                  ),
                  FilledButton.icon(
                    onPressed: _exporting ? null : _export,
                    icon: _exporting
                        ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.file_download_outlined),
                    label: const Text('Export Excel'),
                  ),
                ],
              ),
              if (_message != null) ...[
                const SizedBox(height: 12),
                SelectableText(_message!),
              ],
              const SizedBox(height: 24),
              if (statement.deliveries.isEmpty)
                const Card(child: Padding(padding: EdgeInsets.all(20), child: Text('No deliveries in this date range.')))
              else
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('Date')),
                        DataColumn(label: Text('Product')),
                        DataColumn(label: Text('Number of Bags')),
                        DataColumn(label: Text('Total Weight')),
                      ],
                      rows: statement.deliveries.map((delivery) {
                        return DataRow(
                          cells: [
                            DataCell(Text(_formatDate(delivery.recordedAt))),
                            DataCell(Text(delivery.product.name)),
                            DataCell(Text('${delivery.numberOfBags}')),
                            DataCell(Text('${delivery.totalWeight.toStringAsFixed(1)} kg')),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                ),
              const SizedBox(height: 20),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _Total(label: 'TOTAL BAGS', value: '${statement.totalBags}'),
                      _Total(label: 'TOTAL WEIGHT', value: '${statement.totalWeight.toStringAsFixed(1)} kg'),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _chooseDate({required bool isFrom}) async {
    final selected = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDate: isFrom ? _from : _to,
    );
    if (selected == null) return;
    final nextFrom = isFrom ? selected : _from;
    final nextTo = isFrom ? _to : selected;
    if (nextTo.isBefore(nextFrom)) {
      setState(() => _message = 'The To date must not be before the From date.');
      return;
    }
    setState(() {
      if (isFrom) {
        _from = selected;
      } else {
        _to = selected;
      }
      _message = null;
      _load();
    });
  }

  Future<void> _export() async {
    final statement = await _statement;
    setState(() {
      _exporting = true;
      _message = null;
    });
    try {
      final file = await widget.exporter.export(statement);
      if (mounted) setState(() => _message = 'Exported: $file');
    } catch (error) {
      if (mounted) setState(() => _message = 'Export failed: $error');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  static String _formatDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}

class _Total extends StatelessWidget {
  const _Total({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text(label, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 4),
          Text(value, style: Theme.of(context).textTheme.titleLarge),
        ],
      );
}
