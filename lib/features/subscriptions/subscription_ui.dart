import 'package:flutter/material.dart';

import '../auth/auth_models.dart';
import 'billing_widgets.dart';
import 'entitlement_service.dart';
import 'subscription_messages.dart';
import 'subscription_models.dart';

/// The renewal / grace / lock banner shown at the top of the admin dashboard.
///
/// It is a banner rather than a dialog or a redirect, because a company whose
/// admin access has lapsed must not be logged out, must not lose its screen,
/// and must never be left unsure whether their data is safe.
class SubscriptionBanner extends StatelessWidget {
  const SubscriptionBanner({
    required this.entitlements,
    required this.onRenew,
    super.key,
  });

  final EntitlementService entitlements;
  final VoidCallback onRenew;

  @override
  Widget build(BuildContext context) {
    final status = entitlements.entitlements;
    final notice = SubscriptionMessages.renewalNotice(status);
    if (notice == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Notice(
            message: notice,
            critical:
                SubscriptionMessages.urgency(status) == RenewalUrgency.critical,
          ),
          const SizedBox(height: 8),
          if (status.status == SubscriptionStatus.expired)
            Text(
              SubscriptionMessages.dataSafe,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: onRenew,
            icon: const Icon(Icons.credit_card),
            label: const Text('Go to Billing'),
          ),
        ],
      ),
    );
  }
}

/// The screen an admin sees when their subscription has fully expired.
///
/// It is deliberately NOT a dead end and NOT a logout: it says what happened,
/// reassures them that nothing was deleted, and offers the billing screen and a
/// way to re-check. The company's own data is untouched and returns on renewal.
class SubscriptionLockedScreen extends StatelessWidget {
  const SubscriptionLockedScreen({
    required this.entitlements,
    required this.onRenew,
    super.key,
  });

  final EntitlementService entitlements;
  final VoidCallback onRenew;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Subscription expired')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Icon(
                Icons.lock_outline,
                size: 48,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                SubscriptionMessages.adminLocked,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              Text(
                SubscriptionMessages.dataSafe,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                SubscriptionMessages.secretaryStillWorking,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: onRenew,
                child: const Text('Go to Billing'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: entitlements.refresh,
                child: const Text('Check again'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Gates an admin-only screen on the subscription's admin access.
///
/// The ROLE check is unchanged and still comes first: a subscription never
/// grants a role. Only after the caller is already an admin does the
/// subscription decide whether the management screen opens.
class AdminSubscriptionGate extends StatelessWidget {
  const AdminSubscriptionGate({
    required this.entitlements,
    required this.user,
    required this.builder,
    this.onRenew,
    super.key,
  });

  final EntitlementService entitlements;
  final AppUser? user;
  final Widget Function(BuildContext context) builder;
  final VoidCallback? onRenew;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: entitlements,
      builder: (context, _) {
        // A signed-out or non-admin user never reaches the subscription rules
        // at all, so the role gate keeps its existing behaviour.
        if (user == null || user!.role != UserRole.admin) {
          return builder(context);
        }
        if (entitlements.entitlements.canAccessAdmin) {
          return builder(context);
        }
        return SubscriptionLockedScreen(
          entitlements: entitlements,
          onRenew: onRenew ?? () {},
        );
      },
    );
  }
}

