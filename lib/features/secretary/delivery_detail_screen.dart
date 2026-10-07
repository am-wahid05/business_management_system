import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/app_ui.dart';
import '../../domain/models/delivery.dart';
import '../auth/active_company_context.dart';
import '../auth/auth_models.dart';
import '../company/company_branding.dart';
import '../credits/sms_credit_service.dart';
import '../credits/sms_top_up_dialog.dart';
import '../receiving/bulk_receiving_input.dart';
import '../receiving/delivery_repository.dart';
import '../receiving/print_settings_service.dart';
import '../receiving/receipt_service.dart';
import '../receiving/sms_receipt_service.dart';
import '../receiving/sms_transport.dart';

class DeliveryDetailScreen extends StatefulWidget {
  const DeliveryDetailScreen({
    required this.repository,
    required this.delivery,
    this.brandingService,
    this.activeCompanyContext,
    this.recorderNames = const {},
    this.supabaseClient,
    this.creditService,
    super.key,
  });

  final DeliveryRepository repository;
  final Delivery delivery;
  final CompanyBrandingService? brandingService;

  /// The active company context, forwarded from the list screen so printed
  /// receipts and SMS messages show the active company's name instead of a
  /// hardcoded brand.
  final ActiveCompanyContext? activeCompanyContext;
  final Map<String, String> recorderNames;
  final SupabaseClient? supabaseClient;
  final SmsCreditService? creditService;

  @override
  State<DeliveryDetailScreen> createState() => _DeliveryDetailScreenState();
}

class _DeliveryDetailScreenState extends State<DeliveryDetailScreen>
    with WidgetsBindingObserver {
  late Delivery _delivery;
  final _receiptService = const ReceiptService();
  bool _sending = false;
  bool _loadingSmsBalance = true;
  int? _smsBalance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.activeCompanyContext?.addListener(_onActiveCompanyChanged);
    _delivery = widget.delivery;
    _refreshSmsBalance();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.activeCompanyContext?.removeListener(_onActiveCompanyChanged);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant DeliveryDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeCompanyContext != widget.activeCompanyContext) {
      oldWidget.activeCompanyContext?.removeListener(_onActiveCompanyChanged);
      widget.activeCompanyContext?.addListener(_onActiveCompanyChanged);
      _onActiveCompanyChanged();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshSmsBalance();
  }

  void _onActiveCompanyChanged() {
    if (!mounted) return;
    setState(() {
      _smsBalance = null;
      _loadingSmsBalance = true;
    });
    _refreshSmsBalance();
  }

  String? get _companyId =>
      widget.activeCompanyContext?.companyId ?? _delivery.companyId;

  bool get _canTopUp =>
      widget.activeCompanyContext?.value?.role == UserRole.admin;

  Future<void> _refreshSmsBalance() async {
    final service = widget.creditService;
    final companyId = _companyId;
    if (service == null || companyId == null) {
      if (mounted) setState(() => _loadingSmsBalance = false);
      return;
    }
    try {
      final snapshot = await service.load(companyId: companyId);
      if (!mounted || _companyId != companyId) return;
      setState(() {
        _smsBalance = snapshot.balanceFor(companyId)?.balance;
        _loadingSmsBalance = false;
      });
    } catch (_) {
      if (mounted && _companyId == companyId) {
        setState(() => _loadingSmsBalance = false);
      }
    }
  }

  Future<void> _openSmsTopUp() async {
    final service = widget.creditService;
    final companyId = _companyId;
    if (service == null || companyId == null) return;
    var balance = _smsBalance ?? 0;
    try {
      final snapshot = await service.load(companyId: companyId);
      balance = snapshot.balanceFor(companyId)?.balance ?? balance;
    } catch (_) {
      // Keep the last known balance. The dialog remains honest about payment.
    }
    if (!mounted) return;
    await showSmsTopUpDialog(
      context,
      service: service,
      currentBalance: balance,
    );
    await _refreshSmsBalance();
  }

  /// Active company name for receipts, with a neutral fallback when no
  /// company context is available (e.g. local single-company mode).
  String get _companyName {
    final companyContext =
        widget.activeCompanyContext ??
        widget.brandingService?.activeCompanyContext;
    final name = companyContext?.companyName?.trim();
    return (name == null || name.isEmpty) ? 'Company' : name;
  }

  Future<void> _printReceipt() async {
    try {
      // Reload the authoritative saved row immediately before printing. This
      // prevents a stale list/detail object from producing a PDF with old
      // weights, product, supplier, or bulk totals after an edit/sync.
      final latest = await widget.repository.findById(_delivery.id);
      if (latest == null) {
        throw StateError('The saved receipt could not be found.');
      }
      if (mounted) setState(() => _delivery = latest);
      // Guarded because the await above can outlive this screen: pushing the
      // preview with a dead context would throw instead of showing anything.
      if (!mounted) return;
      // Read the active company's paper choice at print time, so switching
      // company switches the paper without any screen holding stale settings.
      final profile = await PrintPreferences.current(
        context: widget.activeCompanyContext,
      );
      // The printer is a device setting: remembered per company on this
      // machine only, never through the company profile or Supabase.
      final device = await DevicePrintSettingsStore.forContext(
        widget.activeCompanyContext,
      );
      if (!mounted) return;
      if (!profile.showPreview) {
        await _receiptService.print(
          latest,
          companyName: _companyName,
          paper: profile.receiptPaper,
          printer: device.receiptPrinter,
        );
        return;
      }
      await _receiptService.previewDelivery(
        context,
        latest,
        companyName: _companyName,
        paper: profile.receiptPaper,
        printer: device.receiptPrinter,
      );
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open print preview: $error')),
        );
    }
  }

  Future<void> _sendReceipt() async {
    if (widget.creditService != null &&
        (_loadingSmsBalance || _smsBalance == null || _smsBalance! <= 0)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'SMS credits are exhausted or unavailable. Please refresh the balance before sending.',
            ),
          ),
        );
      }
      return;
    }
    final client = widget.supabaseClient;
    final smsReceiptService = SmsReceiptService(
      database: widget.repository.database,
      transport: client == null
          ? null
          : SupabaseEdgeFunctionSmsTransport(client),
      companyIdProvider: () => _companyId,
      creditReader: widget.creditService,
      senderLabel: _companyName,
    );
    final phone = _delivery.supplier.phone;
    if (phone == null || phone.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No supplier phone number is saved for this delivery.'),
        ),
      );
      return;
    }
    setState(() => _sending = true);
    try {
      await smsReceiptService.send(_delivery, companyName: _companyName);
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Receipt sent successfully by SMS.')),
        );
    } catch (error) {
      if (error is SmsReceiptException &&
          (error.code == 'SMS_CREDITS_EXHAUSTED' ||
              error.code == 'SMS_CREDITS_INSUFFICIENT')) {
        if (mounted) {
          if (_canTopUp) {
            await _openSmsTopUp();
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'SMS credits are exhausted. Ask an administrator to top up.',
                ),
              ),
            );
          }
        }
        return;
      }
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Receipt could not be sent: $error')),
        );
    } finally {
      if (mounted) {
        setState(() => _sending = false);
        await _refreshSmsBalance();
      }
    }
  }

  Future<void> _editWeights() async {
    if (_delivery.isBulk) {
      await _editBulkTotals();
      return;
    }
    final controllers = _delivery.bagWeights
        .map((weight) => TextEditingController(text: weight.toString()))
        .toList();
    final weights = await showDialog<List<double>>(
      context: context,
      builder: (context) => _EditWeightsDialog(controllers: controllers),
    );
    for (final controller in controllers) {
      controller.dispose();
    }
    if (weights == null || !mounted) return;
    try {
      final updated = await widget.repository.updateWeights(
        _delivery.id,
        weights,
      );
      if (!mounted) return;
      setState(() => _delivery = updated);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Delivery corrected and saved offline.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update delivery: $error')),
      );
    }
  }

  Future<void> _editBulkTotals() async {
    final bags = TextEditingController(text: '${_delivery.numberOfBags}');
    final total = TextEditingController(text: _delivery.totalWeight.toString());
    final notes = TextEditingController(text: _delivery.notes ?? '');
    final values = await showDialog<List<String>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Correct bulk delivery'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: bags,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Number of bags'),
            ),
            TextField(
              controller: total,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: 'Total weight (kg)'),
            ),
            TextField(
              controller: notes,
              decoration: const InputDecoration(labelText: 'Notes (optional)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, [bags.text, total.text, notes.text]),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    bags.dispose();
    total.dispose();
    notes.dispose();
    if (values == null || !mounted) return;
    try {
      final input = parseBulkReceivingInput(
        bags: values[0],
        totalWeight: values[1],
        notes: values[2],
      );
      final updated = await widget.repository.updateBulkTotals(
        _delivery.id,
        totalWeight: input.totalWeight,
        bagCount: input.bagCount,
        notes: input.notes,
      );
      if (!mounted) return;
      setState(() => _delivery = updated);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bulk delivery corrected and saved offline.'),
        ),
      );
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update delivery: $error')),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Delivery Details'),
        actions: [
          IconButton(
            tooltip: 'Print receipt',
            onPressed: _printReceipt,
            icon: const Icon(Icons.print_outlined),
          ),
          IconButton(
            tooltip: _delivery.isBulk
                ? 'Correct bulk totals'
                : 'Correct weights',
            onPressed: _delivery.isBulk ? _editBulkTotals : _editWeights,
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          if (widget.brandingService != null)
            CompanyBrandMark(
              context: widget.brandingService!.activeCompanyContext,
              service: widget.brandingService,
            ),
          if (widget.brandingService != null) const SizedBox(height: 16),
          AppPageHeader(
            title: _delivery.supplier.name,
            subtitle:
                '${_delivery.product.name} · ${_delivery.recordedAt.hour.toString().padLeft(2, '0')}:${_delivery.recordedAt.minute.toString().padLeft(2, '0')} · ${recorderDisplayName(_delivery.recordedByUserId, widget.recorderNames)}',
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: AppKpiCard(
                  label: 'Bags',
                  value: '${_delivery.numberOfBags}',
                  icon: Icons.inventory_2_outlined,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AppKpiCard(
                  label: 'Total weight',
                  value: '${_delivery.totalWeight.toStringAsFixed(1)} kg',
                  icon: Icons.scale_outlined,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: _printReceipt,
                icon: const Icon(Icons.print_outlined),
                label: const Text('Print receipt'),
              ),
              Opacity(
                opacity: (!_loadingSmsBalance && (_smsBalance ?? 0) <= 0)
                    ? 0.45
                    : 1,
                child: FilledButton.icon(
                  onPressed:
                      _sending ||
                          (widget.creditService != null &&
                              (_loadingSmsBalance ||
                                  _smsBalance == null ||
                                  _smsBalance! <= 0))
                      ? null
                      : _sendReceipt,
                  icon: _sending
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sms_outlined),
                  label: const Text('Send receipt'),
                ),
              ),
              if (!_loadingSmsBalance && (_smsBalance ?? 0) <= 0 && _canTopUp)
                OutlinedButton.icon(
                  onPressed: _sending ? null : _openSmsTopUp,
                  icon: const Icon(Icons.add_card_outlined),
                  label: const Text('Top Up SMS credits'),
                ),
              if (!_loadingSmsBalance && (_smsBalance ?? 0) <= 0 && !_canTopUp)
                const Text(
                  'SMS credits are exhausted. Ask an administrator to top up.',
                ),
            ],
          ),
          const SizedBox(height: 20),
          AppPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _delivery.isBulk
                      ? 'Bulk / weighing-bridge record'
                      : 'Individual bag weights',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 10),
                if (_delivery.isBulk && _delivery.notes?.isNotEmpty == true)
                  Text('Notes: ${_delivery.notes}')
                else if (!_delivery.isBulk)
                  ..._delivery.bagWeights.asMap().entries.map(
                    (entry) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        radius: 14,
                        child: Text('${entry.key + 1}'),
                      ),
                      title: Text('${entry.value.toStringAsFixed(1)} kg'),
                    ),
                  )
                else
                  const Text('No notes were recorded for this bulk delivery.'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          AppPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Record status',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text('Delivery: ${_delivery.status.name}'),
                Text(
                  'Synchronization: ${_delivery.synchronizationStatus.name}',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EditWeightsDialog extends StatefulWidget {
  const _EditWeightsDialog({required this.controllers});

  final List<TextEditingController> controllers;

  @override
  State<_EditWeightsDialog> createState() => _EditWeightsDialogState();
}

class _EditWeightsDialogState extends State<_EditWeightsDialog> {
  String? _error;

  void _save() {
    final weights = <double>[];
    for (final controller in widget.controllers) {
      final value = double.tryParse(controller.text.trim());
      if (value == null || !value.isFinite || value <= 0) {
        setState(
          () => _error = 'All weights must be numbers greater than zero.',
        );
        return;
      }
      weights.add(value);
    }
    Navigator.pop(context, weights);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Correct bag weights'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ...widget.controllers.asMap().entries.map(
              (entry) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextField(
                  controller: entry.value,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Bag ${entry.key + 1}',
                    suffixText: 'kg',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save correction')),
      ],
    );
  }
}
