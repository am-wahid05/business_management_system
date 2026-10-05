import 'package:flutter/material.dart';

import '../../app/app_ui.dart';
import '../../domain/models/delivery.dart';
import '../../domain/models/product.dart';
import '../../domain/models/supplier.dart';
import 'supplier_form_screen.dart';
import 'supplier_repository.dart';
import 'supplier_statement.dart';
import 'supplier_statement_screen.dart';
import '../auth/active_company_context.dart';
import '../receiving/receipt_service.dart';
import '../receiving/print_settings_service.dart';

class SupplierProfileScreen extends StatefulWidget {
  const SupplierProfileScreen({
    required this.repository,
    required this.supplier,
    required this.statementService,
    required this.statementExporter,
    this.activeCompanyContext,
    super.key,
  });

  final SupplierRepository repository;
  final Supplier supplier;
  final SupplierStatementService statementService;
  final SupplierStatementExporter statementExporter;

  /// Active company context so the printed history carries the active
  /// company's name instead of a hardcoded brand.
  final ActiveCompanyContext? activeCompanyContext;

  @override
  State<SupplierProfileScreen> createState() => _SupplierProfileScreenState();
}

class _SupplierProfileScreenState extends State<SupplierProfileScreen> {
  final _receiptService = const ReceiptService();
  DateTime? _date;
  Product? _product;
  int? _year;

  /// Reloaded whenever a filter changes, so the whole history section rebuilds
  /// from the database together.
  late Future<List<Delivery>> _history;

  Supplier get supplier =>
      widget.repository.findById(widget.supplier.id) ?? widget.supplier;

  /// Active company name for the printed history, with a neutral fallback.
  String get _companyName {
    final name = widget.activeCompanyContext?.companyName?.trim();
    return (name == null || name.isEmpty) ? 'Company' : name;
  }

  @override
  void initState() {
    super.initState();
    _history = _loadHistory();
  }

  /// Loads the supplier's deliveries from the same company-scoped repository
  /// that already backs the supplier statement.
  ///
  /// The in-memory supplier cache is deliberately not used here: it is only
  /// populated by a delivery recorded in this same session, so relying on it
  /// made the history look empty for every supplier who had ever been
  /// delivered to. Reading the same rows the statement reads is what keeps the
  /// two views consistent, and it covers both individual and bulk records
  /// because both live in the same table.
  Future<List<Delivery>> _loadHistory() async {
    final all = await widget.statementService.deliveryRepository.forSupplier(
      supplier.id,
    );
    return all
        .where((delivery) {
          if (_date != null && !_isSameDate(delivery.recordedAt, _date!)) {
            return false;
          }
          if (_product != null && delivery.product.id != _product!.id) {
            return false;
          }
          if (_year != null && delivery.recordedAt.year != _year) return false;
          return true;
        })
        .toList(growable: false);
  }

  void _applyFilter(VoidCallback change) {
    setState(change);
    _history = _loadHistory();
  }

  static bool _isSameDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(supplier.name),
        actions: [
          IconButton(
            tooltip: 'Print supplier history',
            onPressed: () async {
              final history = await widget.statementService.deliveryRepository
                  .forSupplier(supplier.id);
              if (!context.mounted) return;
              if (history.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('No delivery history to print.'),
                  ),
                );
                return;
              }
              try {
                // The active company's statement paper, read at print time so
                // switching company switches the paper with no stale cache in
                // this screen.
                final profile = await PrintPreferences.current(
                  context: widget.activeCompanyContext,
                );
                if (!context.mounted) return;
                if (!profile.showPreview) {
                  await _receiptService.printSupplierHistory(
                    supplier,
                    history,
                    companyName: _companyName,
                    paper: profile.statementPaper,
                  );
                  return;
                }
                await _receiptService.previewSupplierHistory(
                  context,
                  supplier,
                  history,
                  companyName: _companyName,
                  paper: profile.statementPaper,
                );
              } catch (error) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Could not open print preview: $error'),
                    ),
                  );
                }
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
          // Totals and history come from one load, so the summary can never
          // disagree with the rows listed underneath it.
          FutureBuilder<List<Delivery>>(
            future: _history,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Column(
                  children: [
                    Row(
                      children: [
                        Expanded(child: AppKpiSkeleton()),
                        SizedBox(width: 12),
                        Expanded(child: AppKpiSkeleton()),
                        SizedBox(width: 12),
                        Expanded(child: AppKpiSkeleton()),
                      ],
                    ),
                    SizedBox(height: 20),
                    AppLoadingList(rows: 5),
                  ],
                );
              }
              if (snapshot.hasError) {
                return AppErrorState(
                  title: 'Delivery history unavailable',
                  message:
                      'We could not load this supplier\'s delivery history.',
                  onRetry: () => setState(() => _history = _loadHistory()),
                );
              }
              final history = snapshot.data ?? const <Delivery>[];
              final years = {
                for (final delivery in history) delivery.recordedAt.year,
              }.toList()..sort((a, b) => b.compareTo(a));
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _TotalCard(
                        label: 'Deliveries',
                        value: '${history.length}',
                      ),
                      _TotalCard(
                        label: 'Bags',
                        value:
                            '${history.fold<int>(0, (total, d) => total + d.numberOfBags)}',
                      ),
                      _TotalCard(
                        label: 'Total weight',
                        value:
                            '${history.fold<double>(0, (total, d) => total + d.totalWeight).toStringAsFixed(1)} kg',
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Filter history',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _chooseDate,
                        icon: const Icon(Icons.calendar_today_outlined),
                        label: Text(
                          _date == null ? 'Date' : _formatDate(_date!),
                        ),
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
                        onChanged: (value) =>
                            _applyFilter(() => _product = value),
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
                            (year) => DropdownMenuItem(
                              value: year,
                              child: Text('$year'),
                            ),
                          ),
                        ],
                        onChanged: (value) => _applyFilter(() => _year = value),
                      ),
                      if (_date != null || _product != null || _year != null)
                        TextButton(
                          onPressed: () => _applyFilter(() {
                            _date = null;
                            _product = null;
                            _year = null;
                          }),
                          child: const Text('Clear filters'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Delivery History',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  if (history.isEmpty)
                    const AppEmptyState(
                      title: 'No matching deliveries',
                      message:
                          'No delivery history matches the selected filters.',
                      icon: Icons.receipt_long_outlined,
                    )
                  else
                    ...history.map(
                      (delivery) => _DeliveryHistoryTile(delivery: delivery),
                    ),
                ],
              );
            },
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
    if (date != null) _applyFilter(() => _date = date);
  }

  static String _formatDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}

/// One row of the supplier's delivery history.
///
/// Individual and bulk records are labelled distinctly, because a bulk
/// weighing-bridge record has no per-bag weights and presenting it as though it
/// did would misrepresent how it was measured.
class _DeliveryHistoryTile extends StatelessWidget {
  const _DeliveryHistoryTile({required this.delivery});

  final Delivery delivery;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: ListTile(
        leading: Icon(
          delivery.isBulk
              ? Icons.scale_outlined
              : Icons.shopping_basket_outlined,
          color: theme.colorScheme.primary,
        ),
        title: Text(
          '${delivery.product.name} · ${delivery.totalWeight.toStringAsFixed(1)} kg',
        ),
        subtitle: Text(
          '${_date(delivery.recordedAt)} · ${delivery.numberOfBags} bags · '
          '${delivery.isBulk ? 'Bulk' : 'Individual'}',
        ),
        // The reference is the delivery id the rest of the app, including the
        // printed receipt, uses to identify this record.
        trailing: Text(
          delivery.id.length > 12
              ? delivery.id.substring(delivery.id.length - 12)
              : delivery.id,
          style: theme.textTheme.bodySmall,
        ),
      ),
    );
  }

  static String _date(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/${date.year}';
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
