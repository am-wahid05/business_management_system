import 'package:flutter/material.dart';

import '../../domain/models/delivery.dart';
import '../receiving/delivery_repository.dart';
import '../receiving/receipt_service.dart';
import '../receiving/sms_receipt_service.dart';
import '../company/company_branding.dart';

class DeliveryDetailScreen extends StatefulWidget {
  const DeliveryDetailScreen({
    required this.repository,
    required this.delivery,
    this.brandingService,
    this.recorderNames = const {},
    super.key,
  });

  final DeliveryRepository repository;
  final Delivery delivery;
  final CompanyBrandingService? brandingService;
  final Map<String, String> recorderNames;

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

  Future<void> _printReceipt() async {
    try {
      final branding = widget.brandingService?.currentBranding;
      final logo = branding?.logoPath == null
          ? null
          : await widget.brandingService!.downloadLogo(branding!.logoPath!);
      await _receiptService.print(
        _delivery,
        companyName: branding?.name ?? 'Company',
        logoBytes: logo,
        recorderNames: widget.recorderNames,
      );
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open print preview: $error')),
        );
    }
  }

  Future<void> _sendReceipt() async {
    final smsReceiptService = SmsReceiptService(
      database: widget.repository.database,
      companyIdProvider: () => widget.delivery.companyId,
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
      await smsReceiptService.send(
        _delivery,
        companyName: widget.brandingService?.currentBranding?.name ?? 'Company',
        recorderNames: widget.recorderNames,
      );
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Receipt sent successfully by SMS.')),
        );
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Receipt could not be sent: $error')),
        );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _editWeights() async {
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
            tooltip: 'Correct weights',
            onPressed: _editWeights,
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            _delivery.supplier.name,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          Text(
            '${_delivery.product.name} · ${_delivery.recordedAt.hour.toString().padLeft(2, '0')}:${_delivery.recordedAt.minute.toString().padLeft(2, '0')}',
          ),
          const SizedBox(height: 20),
          Text(
            'Delivery recorded by: ${recorderDisplayName(_delivery.recordedByUserId, widget.recorderNames)}',
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('${_delivery.numberOfBags} bags'),
                  Text(
                    '${_delivery.totalWeight.toStringAsFixed(1)} kg',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ],
              ),
            ),
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
              FilledButton.icon(
                onPressed: _sending ? null : _sendReceipt,
                icon: _sending
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sms_outlined),
                label: const Text('Send receipt'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            'Individual bag weights',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          ..._delivery.bagWeights.asMap().entries.map(
            (entry) => Card(
              child: ListTile(
                leading: Text('${entry.key + 1}.'),
                title: Text('${entry.value.toStringAsFixed(1)} kg'),
                subtitle: Text(
                  'Weight taken by: ${recorderDisplayName(_delivery.recorderForBag(entry.key), widget.recorderNames)}',
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Status: ${_delivery.status.name} · Sync: ${_delivery.synchronizationStatus.name}',
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
