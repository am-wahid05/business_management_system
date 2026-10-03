import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'sms_credit_pricing.dart';
import 'sms_credit_service.dart';

/// Top-up interface for SMS credits.
///
/// The quantity is validated here for fast feedback and the total is calculated
/// with integer minor units at the fixed price. This is display only: the server
/// recalculates and revalidates the amount, and credits are only ever added
/// after a verified payment.
Future<SmsTopUpOutcome?> showSmsTopUpDialog(
  BuildContext context, {
  required SmsCreditService service,
  required int currentBalance,
}) {
  return showDialog<SmsTopUpOutcome>(
    context: context,
    builder: (context) =>
        _SmsTopUpDialog(service: service, currentBalance: currentBalance),
  );
}

class _SmsTopUpDialog extends StatefulWidget {
  const _SmsTopUpDialog({required this.service, required this.currentBalance});

  final SmsCreditService service;
  final int currentBalance;

  @override
  State<_SmsTopUpDialog> createState() => _SmsTopUpDialogState();
}

class _SmsTopUpDialogState extends State<_SmsTopUpDialog> {
  late final TextEditingController _controller;
  bool _working = false;
  String? _message;
  bool _messageIsError = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: recommendedTopUpCredits.toString(),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  CreditQuantityResult get _result => validateCreditQuantity(_controller.text);

  Future<void> _useRecommended() async {
    _controller.text = recommendedTopUpCredits.toString();
    await _pay();
  }

  Future<void> _pay() async {
    final result = _result;
    if (!result.isValid) {
      setState(() {
        _message = result.message;
        _messageIsError = true;
      });
      return;
    }
    setState(() {
      _working = true;
      _message = null;
    });
    final outcome = await widget.service.startTopUp(credits: result.credits!);
    if (!mounted) return;
    setState(() {
      _working = false;
      _message = outcome.message;
      _messageIsError = !outcome.started;
    });
    if (outcome.started) Navigator.pop(context, outcome);
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Top Up SMS Credits'),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Current balance: ${widget.currentBalance} credits',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _controller,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: 'Credits',
                  errorText: result.isValid ? null : result.message,
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              _SummaryRow(
                label: 'Price per credit',
                value: formatCediMinor(pesewasPerCredit),
              ),
              _SummaryRow(
                label: 'Total',
                value: result.isValid
                    ? formatTopUpTotal(result.credits!)
                    : '--',
                emphasise: true,
              ),
              const SizedBox(height: 16),
              _RecommendedCard(working: _working, onUse: _useRecommended),
              if (_message != null) ...[
                const SizedBox(height: 12),
                Text(
                  _message!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: _messageIsError
                        ? theme.colorScheme.error
                        : theme.colorScheme.primary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _working ? null : () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        FilledButton(
          onPressed: _working ? null : _pay,
          child: _working
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Pay Now'),
        ),
      ],
    );
  }
}

class _RecommendedCard extends StatelessWidget {
  const _RecommendedCard({required this.working, required this.onUse});

  final bool working;
  final VoidCallback onUse;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.35),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            const Icon(Icons.star_rounded, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Recommended', style: theme.textTheme.labelLarge),
                  Text(
                    '$recommendedTopUpCredits credits = '
                    '${formatTopUpTotal(recommendedTopUpCredits)}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: working ? null : onUse,
              child: const Text('Use'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    this.emphasise = false,
  });

  final String label;
  final String value;
  final bool emphasise;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = emphasise
        ? theme.textTheme.titleMedium
        : theme.textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text(value, style: style),
        ],
      ),
    );
  }
}
