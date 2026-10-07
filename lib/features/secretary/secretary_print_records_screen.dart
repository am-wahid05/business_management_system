import 'package:flutter/material.dart';

import '../../app/app_navigation.dart';
import '../../app/app_ui.dart';
import '../../domain/models/delivery.dart';
import '../auth/active_company_context.dart';
import '../company/company_branding.dart';
import '../receiving/delivery_repository.dart';
import '../receiving/receipt_service.dart';
import '../receiving/print_settings_service.dart';

/// Dedicated receipt-selection screen for the Secretary workspace.
///
/// It only reads existing, company-scoped deliveries and delegates PDF/print
/// generation to the existing [ReceiptService]. No records are created or
/// modified by this screen.
class SecretaryPrintRecordsScreen extends StatefulWidget {
  const SecretaryPrintRecordsScreen({
    required this.repository,
    this.brandingService,
    this.activeCompanyContext,
    super.key,
  });

  final DeliveryRepository repository;
  final CompanyBrandingService? brandingService;
  final ActiveCompanyContext? activeCompanyContext;

  @override
  State<SecretaryPrintRecordsScreen> createState() =>
      _SecretaryPrintRecordsScreenState();
}

class _SecretaryPrintRecordsScreenState
    extends State<SecretaryPrintRecordsScreen> {
  late DateTime _from;
  late DateTime _to;
  late Future<List<Delivery>> _records;
  final Set<String> _selectedIds = <String>{};
  bool _printing = false;

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    _from = DateTime(today.year, today.month, today.day);
    _to = _from.add(const Duration(days: 1));
    _reload();
  }

  void _reload() {
    _selectedIds.clear();
    _records = widget.repository.search(
      ReceiptSearchFilters(from: _from, to: _to),
    );
  }

  Future<void> _chooseRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: DateTimeRange(
        start: _from,
        end: _to.subtract(const Duration(days: 1)),
      ),
    );
    if (range == null || !mounted) return;
    setState(() {
      _from = DateTime(range.start.year, range.start.month, range.start.day);
      _to = DateTime(
        range.end.year,
        range.end.month,
        range.end.day,
      ).add(const Duration(days: 1));
      _reload();
    });
  }

  Future<void> _printSelected(List<Delivery> records) async {
    final selected = records
        .where((delivery) => _selectedIds.contains(delivery.id))
        .toList(growable: false);
    if (selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least one record to print.')),
      );
      return;
    }
    setState(() => _printing = true);
    try {
      final receiptService = const ReceiptService();
      final companyName = widget.activeCompanyContext?.companyName ?? 'Company';
      // Resolved once for the whole batch so every record in one job is
      // printed on the same paper, and so a company switch mid-batch cannot
      // split the batch across two layouts.
      final profile = await PrintPreferences.current(
        context: widget.activeCompanyContext,
      );
      // The printer is a device setting, resolved once for the batch: every
      // record in one job goes to the same printer on this machine.
      final device = await DevicePrintSettingsStore.forContext(
        widget.activeCompanyContext,
      );
      for (final delivery in selected) {
        // Each selected record is previewed in turn. When the preview closes,
        // the next one opens, so the Secretary confirms every document they
        // intend to print rather than firing a batch at the printer unseen.
        if (!mounted) return;
        if (!profile.showPreview) {
          await receiptService.print(
            delivery,
            companyName: companyName,
            paper: profile.receiptPaper,
            printer: device.receiptPrinter,
          );
          continue;
        }
        await receiptService.previewDelivery(
          context,
          delivery,
          companyName: companyName,
          paper: profile.receiptPaper,
          printer: device.receiptPrinter,
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open print preview: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  String get _rangeLabel {
    final last = _to.subtract(const Duration(days: 1));
    final start = _formatDate(_from);
    final end = _formatDate(last);
    return start == end ? start : '$start - $end';
  }

  static String _formatDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/${date.year}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Print Records'),
        actions: [
          IconButton(
            tooltip: 'Choose date range',
            onPressed: _printing ? null : _chooseRange,
            icon: const Icon(Icons.calendar_month_outlined),
          ),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1),
        ),
      ),
      drawer: secretaryDrawerFor(context),
      body: FutureBuilder<List<Delivery>>(
        future: _records,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return ListView(
              padding: EdgeInsets.all(24),
              children: [
                AppSkeleton(width: 220, height: 28),
                SizedBox(height: 12),
                AppSkeleton(width: 320, height: 16),
                SizedBox(height: 24),
                AppLoadingList(rows: 6),
              ],
            );
          }
          if (snapshot.hasError) {
            return _PrintStateCard(
              icon: Icons.error_outline,
              title: 'Records unavailable',
              message: 'We could not load saved receipts for printing.',
              action: OutlinedButton.icon(
                onPressed: () => setState(_reload),
                icon: const Icon(Icons.refresh),
                label: const Text('Try again'),
              ),
            );
          }
          final records = snapshot.data ?? const <Delivery>[];
          final allSelected =
              records.isNotEmpty && _selectedIds.length == records.length;
          return Column(
            children: [
              if (widget.activeCompanyContext != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: CompanyBrandMark(
                      context: widget.activeCompanyContext!,
                      service: widget.brandingService,
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Select receipts to print',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$_rangeLabel · ${records.length} saved record(s)',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: records.isEmpty || _printing
                          ? null
                          : () => setState(() {
                              if (allSelected) {
                                _selectedIds.clear();
                              } else {
                                _selectedIds
                                  ..clear()
                                  ..addAll(records.map((item) => item.id));
                              }
                            }),
                      child: Text(allSelected ? 'Clear all' : 'Select all'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: records.isEmpty
                    ? const _PrintStateCard(
                        icon: Icons.receipt_long_outlined,
                        title: 'No records to print',
                        message: 'Saved receiving records for this date range will appear here.',
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 120),
                        itemCount: records.length,
                        separatorBuilder: (_, index) =>
                            const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final delivery = records[index];
                          return Card(
                            child: CheckboxListTile(
                              value: _selectedIds.contains(delivery.id),
                              onChanged: _printing
                                  ? null
                                  : (selected) => setState(() {
                                      if (selected == true) {
                                        _selectedIds.add(delivery.id);
                                      } else {
                                        _selectedIds.remove(delivery.id);
                                      }
                                    }),
                              title: Text(delivery.supplier.name),
                              subtitle: Text(
                                '${delivery.product.name} · '
                                '${delivery.numberOfBags} bags · '
                                '${delivery.totalWeight.toStringAsFixed(1)} kg\n'
                                'Receipt ${delivery.id}',
                              ),
                              secondary: const Icon(Icons.print_outlined),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
      bottomSheet: FutureBuilder<List<Delivery>>(
        future: _records,
        builder: (context, snapshot) {
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const SizedBox.shrink();
          }
          return SafeArea(
            child: Material(
              elevation: 8,
              color: Theme.of(context).colorScheme.surface,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _printing
                        ? null
                        : () => _printSelected(snapshot.data!),
                    icon: _printing
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.print_outlined),
                    label: Text(
                      _printing
                          ? 'Opening print preview...'
                          : 'Print selected (${_selectedIds.length})',
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PrintStateCard extends StatelessWidget {
  const _PrintStateCard({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(message, textAlign: TextAlign.center),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}
