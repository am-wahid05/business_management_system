import 'package:flutter/material.dart';

import '../../app/app_navigation.dart';
import '../../app/app_ui.dart';
import '../credits/sms_credit_service.dart';
import 'billing_widgets.dart';
import 'entitlement_service.dart';
import 'entitlements.dart';
import 'subscription_messages.dart';
import 'subscription_models.dart';

/// The admin-only billing and subscription screen.
///
/// It is deliberately one screen with three clearly separated sections --
/// software, AI, and SMS credits -- because they are three different products
/// with three different balances. Nothing here adds an SMS credit balance into
/// a subscription total, and nothing here can complete a payment: online payment
/// is not connected yet, so every pay button explains that honestly instead of
/// pretending to charge anything.
class BillingScreen extends StatefulWidget {
  const BillingScreen({
    required this.entitlements,
    required this.creditService,
    this.companyId,
    super.key,
  });

  final EntitlementService entitlements;
  final SmsCreditService creditService;

  /// The active company, used only to look up this company's own SMS balance.
  /// The credit function still resolves the company server-side.
  final String? companyId;

  @override
  State<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends State<BillingScreen> {
  @override
  void initState() {
    super.initState();
    // Read the authoritative state. A failure keeps the last known state rather
    // than inventing one.
    widget.entitlements.refresh();
  }

  /// Online payment is not connected, so this is honest rather than a stub that
  /// pretends to work.
  void _explainNotConnected() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Online payment is not available yet. Nothing has been charged and '
          'no changes have been made to your subscription.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Billing & Subscription'),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1),
        ),
      ),
      drawer: adminDrawerFor(context),
      body: AnimatedBuilder(
        animation: widget.entitlements,
        builder: (context, _) {
          final service = widget.entitlements;
          final entitlements = service.entitlements;
          final config = entitlements.config;
          final notice = SubscriptionMessages.renewalNotice(entitlements);
          final urgency = SubscriptionMessages.urgency(entitlements);

          if (service.isLoading) {
            return ListView(
              padding: EdgeInsets.all(24),
              children: [
                AppSkeleton(width: 250, height: 28),
                SizedBox(height: 12),
                AppSkeleton(width: 360, height: 16),
                SizedBox(height: 24),
                AppBillingSkeleton(),
              ],
            );
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (notice != null && urgency != RenewalUrgency.none)
                Notice(
                  message: notice,
                  critical: urgency == RenewalUrgency.critical,
                ),
              if (service.isOffline)
                const Notice(
                  message:
                      'Showing your last known subscription status. '
                      'Connect to the internet to refresh it.',
                ),
              const SizedBox(height: 16),
              _softwareSection(service, entitlements, config),
              const SizedBox(height: 16),
              _aiSection(entitlements, config),
              const SizedBox(height: 16),
              _smsSection(),
              const SizedBox(height: 16),
              _seasonSection(service, entitlements),
            ],
          );
        },
      ),
    );
  }

  /// The software subscription, with an itemised monthly total.
  ///
  /// SMS credits are deliberately absent from every total in this section.
  Widget _softwareSection(
    EntitlementService service,
    Entitlements entitlements,
    SubscriptionConfig config,
  ) {
    final currency = config.currency;
    return Section(
      title: 'Software subscription',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const DetailRow('Plan', 'Business Management System'),
          DetailRow('Status', statusLabel(entitlements.status)),
          if (entitlements.trialEndsAt != null)
            DetailRow('Trial ends', formatDay(entitlements.trialEndsAt!)),
          if (entitlements.currentPeriodStart != null)
            DetailRow(
              'Current period starts',
              formatDay(entitlements.currentPeriodStart!),
            ),
          if (entitlements.currentPeriodEnd != null)
            DetailRow(
              'Current period ends',
              formatDay(entitlements.currentPeriodEnd!),
            ),
          const Divider(),
          DetailRow(
            'Secretaries',
            '${service.secretariesInUse} / ${entitlements.maxSecretaries}',
          ),
          if (service.isOverSecretaryAllowance)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'This company is over its current secretary allowance. Nothing '
                'has been removed: your secretaries can keep working. Add a '
                'bundle, or remove a secretary you no longer need.',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          DetailRow(
            'Additional secretary bundles',
            '${entitlements.secretaryBundles}',
          ),
          DetailRow(
            'Setup fee (one time)',
            formatCedi(config.setupFeeMinor, currency: currency),
          ),
          const Divider(),
          DetailRow(
            'Base subscription',
            '${formatCedi(config.baseMonthlyMinor, currency: currency)}/month',
          ),
          if (entitlements.secretaryBundles > 0)
            DetailRow(
              'Secretary bundle x${entitlements.secretaryBundles}',
              '${formatCedi(config.additionalSecretaryBundleMinor * entitlements.secretaryBundles, currency: currency)}/month',
            ),
          const Divider(),
          DetailRow(
            'Next payment',
            formatCedi(
              config.monthlySoftwareTotalMinor(entitlements.secretaryBundles),
              currency: currency,
            ),
            strong: true,
          ),
          const SizedBox(height: 12),
          PayButton(
            label: 'Renew software subscription',
            note:
                'Online payment is not available yet. Nothing will be charged '
                'until payment is connected.',
            onPressed: _explainNotConnected,
          ),
          if (!service.canAddSecretary)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'To add another secretary, buy an additional bundle of '
                '${config.secretaryBundleSize}.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }

  /// The AI premium, shown entirely separately from the software subscription.
  Widget _aiSection(Entitlements entitlements, SubscriptionConfig config) {
    return Section(
      title: 'AI Assistant',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DetailRow('Status', aiStatusLabel(entitlements.aiStatus)),
          if (entitlements.aiTrialEndsAt != null)
            DetailRow('AI trial ends', formatDay(entitlements.aiTrialEndsAt!)),
          if (entitlements.aiPeriodEnd != null)
            DetailRow('AI period ends', formatDay(entitlements.aiPeriodEnd!)),
          DetailRow(
            'AI subscription',
            '${formatCedi(config.aiMonthlyMinor, currency: config.currency)}/month',
          ),
          const SizedBox(height: 12),
          PayButton(
            label: 'Add the AI Assistant',
            note:
                'The AI Assistant is billed separately from your software '
                'subscription.',
            onPressed: _explainNotConnected,
          ),
        ],
      ),
    );
  }

  /// SMS credits, kept wholly apart from the subscription.
  ///
  /// A company's SMS balance is not part of its subscription status and is
  /// never included in any total above.
  Widget _smsSection() {
    return Section(
      title: 'SMS Credits',
      child: FutureBuilder<SmsCreditSnapshot>(
        future: widget.creditService.load(companyId: widget.companyId),
        builder: (context, snapshot) {
          final balance = snapshot.hasData
              ? snapshot.data!.balanceFor(widget.companyId ?? '')?.balance
              : null;
          final creditError = snapshot.hasError
              ? 'Could not load SMS credits: ${snapshot.error}'
              : null;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (creditError != null)
                Text(
                  creditError,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                )
              else if (snapshot.connectionState != ConnectionState.done)
                const Row(
                  children: [
                    AppSkeleton(width: 140, height: 16),
                    Spacer(),
                    AppSkeleton(width: 100, height: 16),
                  ],
                )
              else
                DetailRow(
                  'Current balance',
                  balance == null ? 'Unavailable' : '$balance credits',
                ),
              const SizedBox(height: 4),
              Text(
                'SMS credits are separate from your software subscription. Your '
                'subscription does not include them, and they are never '
                'affected by your renewal.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              PayButton(
                label: 'Buy SMS Credits',
                note:
                    'SMS credit top up is not available yet. No credits have '
                    'been added to your account.',
                onPressed: _explainNotConnected,
              ),
            ],
          );
        },
      ),
    );
  }

  /// Pause and reactivate, for seasonal businesses.
  Widget _seasonSection(EntitlementService service, Entitlements entitlements) {
    final paused = entitlements.isPaused;
    return Section(
      title: 'Seasonal pause',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            paused
                ? 'This subscription is paused for the season. Nothing has been '
                      'deleted: your users, records, suppliers, products and '
                      'reports are all safe.'
                : 'If your business stops for a season, you can pause your '
                      'subscription instead of letting it expire. Everything is '
                      'kept, and you can reactivate whenever you are ready.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () async {
              final message = paused
                  ? await service.resume()
                  : await service.pause(
                      reason:
                          'Season ended; subscription paused by the company',
                    );
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    message
                        ? (paused
                              ? 'Your subscription is active again.'
                              : 'Your subscription is paused. All your data is '
                                    'safe.')
                        : 'Could not update the subscription. Please try again '
                              'while connected to the internet.',
                  ),
                ),
              );
            },
            icon: Icon(paused ? Icons.play_arrow : Icons.pause),
            label: Text(
              paused ? 'Reactivate subscription' : 'Pause subscription',
            ),
          ),
        ],
      ),
    );
  }
}

class AppBillingSkeleton extends StatelessWidget {
  const AppBillingSkeleton({super.key});

  @override
  Widget build(BuildContext context) => const Column(
    children: [
      AppPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppSkeleton(width: 190, height: 18),
            SizedBox(height: 18),
            AppSkeleton(width: double.infinity, height: 16),
            SizedBox(height: 12),
            AppSkeleton(width: double.infinity, height: 16),
            SizedBox(height: 12),
            AppSkeleton(width: 230, height: 16),
            SizedBox(height: 20),
            AppSkeleton(width: 150, height: 46, radius: 10),
          ],
        ),
      ),
      SizedBox(height: 16),
      AppPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppSkeleton(width: 140, height: 18),
            SizedBox(height: 18),
            AppSkeleton(width: double.infinity, height: 16),
            SizedBox(height: 12),
            AppSkeleton(width: 210, height: 16),
          ],
        ),
      ),
      SizedBox(height: 16),
      AppPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppSkeleton(width: 120, height: 18),
            SizedBox(height: 18),
            AppSkeleton(width: double.infinity, height: 16),
            SizedBox(height: 12),
            AppSkeleton(width: 260, height: 16),
          ],
        ),
      ),
    ],
  );
}

String statusLabel(SubscriptionStatus status) {
  switch (status) {
    case SubscriptionStatus.trial:
      return 'Trial';
    case SubscriptionStatus.active:
      return 'Active';
    case SubscriptionStatus.gracePeriod:
      return 'Grace Period';
    case SubscriptionStatus.expired:
      return 'Expired';
    case SubscriptionStatus.paused:
      return 'Paused';
  }
}

String aiStatusLabel(AiEntitlementStatus status) {
  switch (status) {
    case AiEntitlementStatus.trial:
      return 'Trial';
    case AiEntitlementStatus.active:
      return 'Active';
    case AiEntitlementStatus.expired:
      return 'Expired';
    case AiEntitlementStatus.none:
      return 'Not included';
  }
}

String formatDay(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}/'
    '${value.month.toString().padLeft(2, '0')}/${value.year}';
