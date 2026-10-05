import 'package:flutter/material.dart';

import '../../app/app_ui.dart';
import 'sms_credit_pricing.dart';
import 'sms_credit_service.dart';
import 'sms_top_up_dialog.dart';

/// Shows the company's SMS credit balance with a Top Up action.
///
/// The balance always belongs to the authenticated user's own company: it is
/// loaded through the read-only `sms-credits` Edge Function, which derives the
/// company from the caller's membership. There is deliberately no control here
/// to increase credits, because credits can only ever be added by the server
/// after a verified payment.
class SmsCreditsCard extends StatefulWidget {
  const SmsCreditsCard({
    required this.service,
    required this.companyId,
    this.canTopUp = true,
    this.onBalanceChanged,
    super.key,
  });
  final SmsCreditService service;

  /// The authenticated user's active company. Null hides the card.
  final String? companyId;

  /// Whether the viewer may buy credits.
  ///
  /// A secretary can see the company balance they spend from, but buying
  /// credits is a company payment decision and stays with an owner or admin.
  /// When false the top-up control is not rendered at all, so a secretary
  /// cannot reach a purchase screen through this card.
  final bool canTopUp;

  /// Called after a top-up attempt so the caller can refresh the balance.
  final VoidCallback? onBalanceChanged;
  @override
  State<SmsCreditsCard> createState() => _SmsCreditsCardState();
}

class _SmsCreditsCardState extends State<SmsCreditsCard> {
  SmsCreditSnapshot? _snapshot;
  bool _loading = true;
  String? _message;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void didUpdateWidget(SmsCreditsCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.companyId != widget.companyId) _refresh();
  }

  Future<void> _refresh() async {
    final companyId = widget.companyId;
    if (companyId == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    setState(() => _loading = true);
    try {
      final snapshot = await widget.service.load(companyId: companyId);
      if (mounted) setState(() => _snapshot = snapshot);
    } catch (_) {
      if (mounted) {
        setState(() => _message = 'Could not load SMS credits.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  int get _balance {
    final companyId = widget.companyId;
    if (companyId == null) return 0;
    return _snapshot?.balanceFor(companyId)?.balance ?? 0;
  }

  Future<void> _openTopUp() async {
    final outcome = await showSmsTopUpDialog(
      context,
      service: widget.service,
      currentBalance: _balance,
    );
    if (outcome == null) return;
    widget.onBalanceChanged?.call();
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final companyId = widget.companyId;
    if (companyId == null) return const SizedBox.shrink();

    final exhausted = !_loading && _balance <= 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(Icons.sms, size: 32, color: theme.colorScheme.primary),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('SMS Credits', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 4),
                  if (_loading)
                    const AppSkeleton(width: 110, height: 28)
                  else
                    Text(
                      _formatBalance(_balance),
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: exhausted ? theme.colorScheme.error : null,
                      ),
                    ),
                  if (_message != null)
                    Text(
                      _message!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  if (exhausted)
                    Text(
                      'Top up to send receipts by SMS.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                ],
              ),
            ),
            // The purchase control is omitted entirely for anyone who is not
            // allowed to buy credits, so there is no disabled button to press
            // and no route to a payment screen a secretary should not reach.
            if (widget.canTopUp)
              FilledButton.icon(
                onPressed: _loading ? null : _openTopUp,
                icon: const Icon(Icons.add_card_outlined),
                label: const Text('Top Up'),
              ),
          ],
        ),
      ),
    );
  }

  /// Thousands separators keep a large balance readable.
  static String _formatBalance(int balance) =>
      balance.toString().replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
        (match) => '${match[1]},',
      );
}

/// Formats the price of one credit, e.g. "GH₵0.05".
String formatUnitPrice() => formatCediMinor(pesewasPerCredit);
