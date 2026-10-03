import 'package:flutter/material.dart';

import '../../domain/models/delivery.dart';
import '../../domain/models/product.dart';
import '../../domain/models/supplier.dart';
import 'supplier_form_screen.dart';
import 'supplier_repository.dart';
import 'supplier_statement.dart';
import 'supplier_statement_screen.dart';
import '../receiving/receipt_service.dart';
import '../company/company_branding.dart';

class SupplierProfileScreen extends StatefulWidget {
  const SupplierProfileScreen({
    required this.repository,
    required this.supplier,
    required this.statementService,
    required this.statementExporter,
    this.brandingService,
    this.recorderNamesProvider,
    super.key,
  });

  final SupplierRepository repository;
  final Supplier supplier;
  final SupplierStatementService statementService;
  final SupplierStatementExporter statementExporter;
  final CompanyBrandingService? brandingService;
  final Future<Map<String, String>> Function()? recorderNamesProvider;

  @override
  State<SupplierProfileScreen> createState() => _SupplierProfileScreenState();
}

class _SupplierProfileScreenState extends State<SupplierProfileScreen> {
  final _receiptService = const ReceiptService();
  DateTime? _date;
  Product? _product;
  int? _year;
  Map<String, String> _recorderNames = const {};

  Supplier get supplier =>
      widget.repository.findById(widget.supplier.id) ?? widget.supplier;

  @override
  void initState() {
    super.initState();
    _loadRecorderNames();
  }

  Future<void> _loadRecorderNames() async {
    try {
      final names = await widget.recorderNamesProvider?.call() ?? const {};
      if (mounted) setState(() => _recorderNames = names);
    } catch (_) {
      // Keep history available if the profile lookup is offline.
    }
  }

  @override
  Widget build(BuildContext context) {
    final history = widget.repository.deliveryHistory(
      supplier.id,
      date: _date,
      product: _product,
      year: _year,
    );
    final totals = widget.repository.totals(
      supplier.id,
      date: _date,
      product: _product,
      year: _year,
    );
    final years = {
      for (final delivery in widget.repository.deliveryHistory(supplier.id))
        delivery.recordedAt.year,
    }.toList()..sort((a, b) => b.compareTo(a));

    return Scaffold(
      appBar: AppBar(
        title: Text(supplier.name),
        actions: [
          IconButton(
            tooltip: 'Print supplier history',
            onPressed: () async {
              final history = widget.repository.deliveryHistory(supplier.id);
              if (history.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('No delivery history to print.'),
                  ),
                );
                return;
              }
              try {
                final branding = widget.brandingService?.currentBranding;
                final logo = branding?.logoPath == null
                    ? null
                    : await widget.brandingService!.downloadLogo(
                        branding!.logoPath!,
                      );
                await _receiptService.printSupplierHistory(
                  supplier,
                  history,
                  companyName: branding?.name ?? 'Company',
                  logoBytes: logo,
                  recorderNames: _recorderNames,
                );
              } catch (error) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Could not open print preview: $error'),
                  ),
                );
              }
            },
            icon: const Icon(Icons.print_outlined),
          ),
          IconButton(
            tooltip: 'Edit supplier',
            onPressed: () async {
              await Navigator.push<Supplier>(
                context,
                MaterialPageRoute(
                  builder: (_) => SupplierFormScreen(
                    repository: widget.repository,
                    supplier: supplier,
                  ),
                ),
              );
              if (!mounted) return;
              setState(() {});
            },
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          _ProfileHeader(supplier: supplier),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => SupplierStatementScreen(
                  supplier: supplier,
                  service: widget.statementService,
                  exporter: widget.statementExporter,
                ),
              ),
            ),
            icon: const Icon(Icons.description_outlined),
            label: const Text('Create supplier statement'),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _TotalCard(label: 'Deliveries', value: '${totals.deliveryCount}'),
              _TotalCard(label: 'Bags', value: '${totals.bagCount}'),
              _TotalCard(
                label: 'Total weight',
                value: '${totals.totalWeight.toStringAsFixed(1)} kg',
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text('Filter history', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              OutlinedButton.icon(
                onPressed: _chooseDate,
                icon: const Icon(Icons.calendar_today_outlined),
                label: Text(_date == null ? 'Date' : _formatDate(_date!)),
              ),
              DropdownButton<Product>(
                hint: const Text('Product'),
                value: _product,
                items: [
                  const DropdownMenuItem<Product>(
                    value: null,
                    child: Text('All products'),
                  ),
                  ...Product.initialProducts.map(
                    (product) => DropdownMenuItem(
                      value: product,
                      child: Text(product.name),
                    ),
                  ),
                ],
                onChanged: (value) => setState(() => _product = value),
              ),
              DropdownButton<int>(
                hint: const Text('Year'),
                value: _year,
                items: [
                  const DropdownMenuItem<int>(
                    value: null,
                    child: Text('All years'),
                  ),
                  ...years.map(
                    (year) =>
                        DropdownMenuItem(value: year, child: Text('$year')),
                  ),
                ],
                onChanged: (value) => setState(() => _year = value),
              ),
              if (_date != null || _product != null || _year != null)
                TextButton(
                  onPressed: () => setState(() {
                    _date = null;
                    _product = null;
                    _year = null;
                  }),
                  child: const Text('Clear filters'),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (history.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text('No delivery history matches these filters.'),
              ),
            )
          else
            ...history.map(
              (delivery) => Card(
                child: ListTile(
                  trailing: Text(
                    recorderDisplayName(
                      delivery.recordedByUserId,
                      _recorderNames,
                    ),
                  ),
                  title: Text(
                    '${delivery.product.name} · ${delivery.totalWeight.toStringAsFixed(1)} kg',
                  ),
                  subtitle: Text(
                    '${_formatDate(delivery.recordedAt)} · ${delivery.numberOfBags} bags',
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _chooseDate() async {
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDate: _date ?? DateTime.now(),
    );
    if (date != null) setState(() => _date = date);
  }

  static String _formatDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.supplier});

  final Supplier supplier;

  @override
  Widget build(BuildContext context) {
    final type = supplier.type == SupplierType.farmer ? 'Farmer' : 'Aggregator';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    supplier.name,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                Chip(label: Text(supplier.isActive ? 'Active' : 'Inactive')),
              ],
            ),
            const SizedBox(height: 8),
            Text('${supplier.id} · $type'),
            Text('${supplier.town}, ${supplier.district}, ${supplier.region}'),
            if (supplier.phone != null) Text(supplier.phone!),
            if (supplier.notes != null) Text(supplier.notes!),
          ],
        ),
      ),
    );
  }
}

class _TotalCard extends StatelessWidget {
  const _TotalCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label),
          const SizedBox(height: 4),
          Text(value, style: Theme.of(context).textTheme.titleLarge),
        ],
      ),
    ),
  );
}
