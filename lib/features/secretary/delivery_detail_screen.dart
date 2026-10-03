import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/models/delivery.dart';
import '../auth/active_company_context.dart';
import '../company/company_branding.dart';
import '../credits/sms_credit_service.dart';
import '../receiving/bulk_receiving_input.dart';
import '../receiving/delivery_repository.dart';
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

class _DeliveryDetailScreenState extends State<DeliveryDetailScreen> {
  late Delivery _delivery;
  final _receiptService = const ReceiptService();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _delivery = widget.delivery;
  }

  /// Active company name for receipts, with a neutral fallback when no
  /// company context is available (e.g. local single-company mode).
  String get _companyName {
    final companyContext =
        widget.activeCompanyContext ?? widget.brandingService?.activeCompanyContext;
    final name = companyContext?.companyName?.trim();
    return (name == null || name.isEmpty) ? 'Company' : name;
  }

  Future<void> _printReceipt() async {
    try {
      await _receiptService.print(_delivery, companyName: _companyName);
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not open print preview: $error')));
    }
  }

  Future<void> _sendReceipt() async {
    final client = widget.supabaseClient;
    final smsReceiptService = SmsReceiptService(
      database: widget.repository.database,
      transport: client == null ? null : SupabaseEdgeFunctionSmsTransport(client),
    );
    final phone = _delivery.supplier.phone;
    if (phone == null || phone.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No supplier phone number is saved for this delivery.')));
      return;
    }
    setState(() => _sending = true);
    try {
      await smsReceiptService.send(_delivery, companyName: _companyName);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Receipt sent successfully by SMS.')));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Receipt could not be sent: $error')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _editWeights() async {
    if (_delivery.isBulk) {
      await _editBulkTotals();
      return;
    }
    final controllers = _delivery.bagWeights.map((weight) => TextEditingController(text: weight.toString())).toList();
    final weights = await showDialog<List<double>>(
      context: context,
      builder: (context) => _EditWeightsDialog(controllers: controllers),
    );
    for (final controller in controllers) {
      controller.dispose();
    }
    if (weights == null || !mounted) return;
    try {
      final updated = await widget.repository.updateWeights(_delivery.id, weights);
      if (!mounted) return;
      setState(() => _delivery = updated);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Delivery corrected and saved offline.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not update delivery: $error')));
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
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: bags, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Number of bags')),
          TextField(controller: total, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Total weight (kg)')),
          TextField(controller: notes, decoration: const InputDecoration(labelText: 'Notes (optional)')),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, [bags.text, total.text, notes.text]), child: const Text('Save'))],
      ),
    );
    bags.dispose(); total.dispose(); notes.dispose();
    if (values == null || !mounted) return;
    try {
      final input = parseBulkReceivingInput(bags: values[0], totalWeight: values[1], notes: values[2]);
      final updated = await widget.repository.updateBulkTotals(
        _delivery.id,
        totalWeight: input.totalWeight,
        bagCount: input.bagCount,
        notes: input.notes,
      );
      if (!mounted) return;
      setState(() => _delivery = updated);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bulk delivery corrected and saved offline.')));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not update delivery: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Delivery Details'), actions: [IconButton(tooltip: 'Print receipt', onPressed: _printReceipt, icon: const Icon(Icons.print_outlined)), IconButton(tooltip: _delivery.isBulk ? 'Correct bulk totals' : 'Correct weights', onPressed: _delivery.isBulk ? _editBulkTotals : _editWeights, icon: const Icon(Icons.edit_outlined))]),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          if (widget.brandingService != null)
            CompanyBrandMark(
              context: widget.brandingService!.activeCompanyContext,
              service: widget.brandingService,
            ),
          if (widget.brandingService != null) const SizedBox(height: 16),
          Text(_delivery.supplier.name, style: Theme.of(context).textTheme.headlineSmall),
          Text('${_delivery.product.name} · ${_delivery.recordedAt.hour.toString().padLeft(2, '0')}:${_delivery.recordedAt.minute.toString().padLeft(2, '0')}'),
          Text('Delivery recorded by: ${recorderDisplayName(_delivery.recordedByUserId, widget.recorderNames)}'),
          const SizedBox(height: 20),
          Card(child: Padding(padding: const EdgeInsets.all(20), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('${_delivery.numberOfBags} bags'), Text('${_delivery.totalWeight.toStringAsFixed(1)} kg', style: Theme.of(context).textTheme.titleLarge)]))),
          const SizedBox(height: 12),
          Wrap(spacing: 10, runSpacing: 10, children: [OutlinedButton.icon(onPressed: _printReceipt, icon: const Icon(Icons.print_outlined), label: const Text('Print receipt')), FilledButton.icon(onPressed: _sending ? null : _sendReceipt, icon: _sending ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.sms_outlined), label: const Text('Send receipt'))]),
          const SizedBox(height: 20),
          if (_delivery.isBulk) ...[
            Text('Bulk / weighing-bridge record', style: Theme.of(context).textTheme.titleLarge),
            if (_delivery.notes?.isNotEmpty == true) Text('Notes: ${_delivery.notes}'),
          ] else ...[
            Text('Individual bag weights', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            ..._delivery.bagWeights.asMap().entries.map((entry) => Card(child: ListTile(leading: Text('${entry.key + 1}.'), title: Text('${entry.value.toStringAsFixed(1)} kg')))),
          ],
          const SizedBox(height: 12),
          Text('Status: ${_delivery.status.name} · Sync: ${_delivery.synchronizationStatus.name}'),
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
        setState(() => _error = 'All weights must be numbers greater than zero.');
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
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)), ...widget.controllers.asMap().entries.map((entry) => Padding(padding: const EdgeInsets.only(bottom: 12), child: TextField(controller: entry.value, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: 'Bag ${entry.key + 1}', suffixText: 'kg'))))])),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), FilledButton(onPressed: _save, child: const Text('Save correction'))],
    );
  }
}
