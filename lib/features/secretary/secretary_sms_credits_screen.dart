import 'package:flutter/material.dart';

import '../../app/app_navigation.dart';
import '../../app/app_ui.dart';
import '../auth/active_company_context.dart';
import '../company/company_branding.dart';
import '../credits/sms_credit_service.dart';

/// Read-only SMS balance and permissions screen for a secretary.
///
/// There is intentionally no top-up control here. Company payment and credit
/// administration remain outside the Secretary role, while the existing receipt
/// screen remains responsible for the final server-authoritative send check.
class SecretarySmsCreditsScreen extends StatefulWidget {
  const SecretarySmsCreditsScreen({
    required this.service,
    required this.activeCompanyContext,
    this.brandingService,
    super.key,
  });

  final SmsCreditService? service;
  final ActiveCompanyContext activeCompanyContext;
  final CompanyBrandingService? brandingService;

  @override
  State<SecretarySmsCreditsScreen> createState() =>
      _SecretarySmsCreditsScreenState();
}

class _SecretarySmsCreditsScreenState extends State<SecretarySmsCreditsScreen> {
  late Future<SmsCreditSnapshot> _snapshot;

  @override
  void initState() {
    super.initState();
    _snapshot = _load();
  }

  Future<SmsCreditSnapshot> _load() {
    final service = widget.service;
    final companyId = widget.activeCompanyContext.companyId;
    if (service == null || companyId == null) {
      return Future.value(SmsCreditSnapshot.empty);
    }
    return service.load(companyId: companyId);
  }

  void _refresh() => setState(() => _snapshot = _load());

  @override
  Widget build(BuildContext context) {
    final companyId = widget.activeCompanyContext.companyId;
    return Scaffold(
      appBar: AppBar(
        title: const Text('SMS Credits'),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1),
        ),
      ),
      drawer: secretaryDrawerFor(context),
      body: FutureBuilder<SmsCreditSnapshot>(
        future: _snapshot,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return ListView(
              padding: const EdgeInsets.all(24),
              children: const [
                AppProfileSkeleton(),
                SizedBox(height: 20),
                AppKpiSkeleton(),
                SizedBox(height: 20),
                AppLoadingList(rows: 4),
              ],
            );
          }
          if (snapshot.hasError) {
            return _SmsCreditsState(
              icon: Icons.cloud_off_outlined,
              title: 'Balance unavailable',
              message: 'We could not load the company SMS balance. Check the connection and try again.',
              action: OutlinedButton.icon(
                onPressed: _refresh,
                icon: const Icon(Icons.refresh),
                label: const Text('Try again'),
              ),
            );
          }
          if (companyId == null || widget.service == null) {
            return const _SmsCreditsState(
              icon: Icons.sms_failed_outlined,
              title: 'SMS credits unavailable',
              message: 'SMS sending is not configured for this installation. Contact the administrator.',
            );
          }
          final balance = snapshot.data?.balanceFor(companyId);
          final amount = balance?.balance ?? 0;
          final exhausted = amount <= 0;
          final transactions =
              snapshot.data?.transactions
                  .where((item) => item.companyId == companyId)
                  .take(8)
                  .toList(growable: false) ??
              const <SmsCreditTransaction>[];
          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                CompanyBrandMark(
                  context: widget.activeCompanyContext,
                  service: widget.brandingService,
                ),
                const SizedBox(height: 24),
                Text(
                  'Company SMS balance',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 6),
                Text(
                  'This balance is shared by your company and is used when a receipt is sent by SMS.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 20),
                Card(
                  color: exhausted
                      ? Theme.of(context).colorScheme.errorContainer
                      : Theme.of(context).colorScheme.primaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Row(
                      children: [
                        Icon(
                          exhausted
                              ? Icons.sms_failed_outlined
                              : Icons.sms_outlined,
                          size: 36,
                        ),
                        const SizedBox(width: 16),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$amount',
                              style: Theme.of(context).textTheme.displaySmall,
                            ),
                            Text(
                              amount == 1
                                  ? 'SMS credit remaining'
                                  : 'SMS credits remaining',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Your permitted actions',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        const _PermissionRow(
                          icon: Icons.check_circle_outline,
                          text: 'Send receipt SMS messages when sufficient credits are available.',
                        ),
                        const _PermissionRow(
                          icon: Icons.visibility_outlined,
                          text: 'View the company SMS balance and receipt sending status.',
                        ),
                        const _PermissionRow(
                          icon: Icons.admin_panel_settings_outlined,
                          text: 'Top-ups and payment actions are managed by an administrator.',
                        ),
                      ],
                    ),
                  ),
                ),
                if (exhausted) ...[
                  const SizedBox(height: 16),
                  Card(
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'Your company has no SMS credits. Send Receipt is unavailable until an administrator adds credits. Please contact the administrator.',
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                Text(
                  'Recent credit activity',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                if (transactions.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(18),
                      child: Text('No credit activity is available yet.'),
                    ),
                  )
                else
                  ...transactions.map(
                    (transaction) => Card(
                      child: ListTile(
                        leading: Icon(
                          transaction.isUsage
                              ? Icons.sms_outlined
                              : transaction.isPurchase
                              ? Icons.add_circle_outline
                              : Icons.replay_outlined,
                        ),
                        title: Text(_activityTitle(transaction)),
                        subtitle: Text(
                          transaction.createdAt == null
                              ? 'Date unavailable'
                              : _formatDate(transaction.createdAt!),
                        ),
                        trailing: Text(
                          '${transaction.credits > 0 ? '+' : ''}${transaction.credits}',
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  static String _activityTitle(SmsCreditTransaction transaction) =>
      switch (transaction.type) {
        'usage' => 'Receipt SMS used',
        'purchase' => 'Credits added',
        'refund' => 'SMS credit refunded',
        _ => 'Credit activity',
      };

  static String _formatDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/${date.year}';
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 10),
        Expanded(child: Text(text)),
      ],
    ),
  );
}

class _SmsCreditsState extends StatelessWidget {
  const _SmsCreditsState({
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
  Widget build(BuildContext context) => Center(
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
