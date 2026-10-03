import 'entitlements.dart';
import 'subscription_models.dart';

/// The user-facing wording for a company's subscription state.
///
/// All of this lives here so the same company is never told two different
/// things in two different screens. The wording is deliberately plain and
/// actionable: it says what happened, what still works, and what to do next.
class SubscriptionMessages {
  const SubscriptionMessages._();

  /// Shown to an admin whose access has been locked by an expired subscription.
  ///
  /// It is explicit that the company's records are safe, because the most
  /// frightening thing an admin can be told is that their work has gone.
  static const adminLocked =
      'Your subscription has expired. Renew your subscription to restore admin access.';

  /// Shown next to the admin lock, to reassure rather than alarm.
  static const dataSafe =
      'All of your records, suppliers, products and reports are safe and will be '
      'here when you renew.';

  /// Shown to a secretary, so an admin lock never looks like the whole app has
  /// broken. Secretaries keep working; this is not a way to manage billing.
  static const secretaryStillWorking =
      'Your company\'s admin subscription has expired. You can still record '
      'deliveries and weights as normal.';

  /// A neutral banner, or null when nothing needs saying.
  ///
  /// Returns null for a healthy subscription so the UI stays quiet rather than
  /// showing a permanent "everything is fine" notice.
  static String? renewalNotice(Entitlements entitlements) {
    switch (entitlements.status) {
      case SubscriptionStatus.paused:
        return 'This company\'s subscription is paused for the season. '
            'All records are safe. Reactivate to start using the software again.';

      case SubscriptionStatus.expired:
        return adminLocked;

      case SubscriptionStatus.gracePeriod:
        final days = entitlements.daysOfGraceLeft ?? 0;
        return 'Your subscription has expired. You have $days '
            '${days == 1 ? 'day' : 'days'} remaining in your grace period. '
            'Renew now to avoid admin access being locked.';

      case SubscriptionStatus.trial:
        final days = entitlements.daysOfTrialLeft ?? 0;
        if (days <= 7) {
          return days == 0
              ? 'Your free trial ends today.'
              : 'Your free trial ends in $days '
                  '${days == 1 ? 'day' : 'days'}.';
        }
        return null;

      case SubscriptionStatus.active:
        final days = entitlements.daysUntilRenewal;
        if (days != null && days <= 7) {
          return days == 0
              ? 'Your subscription expires today.'
              : 'Your subscription expires in $days '
                  '${days == 1 ? 'day' : 'days'}.';
        }
        return null;
    }
  }

  /// How urgent a notice is, so the UI can colour it correctly.
  static RenewalUrgency urgency(Entitlements entitlements) =>
      switch (entitlements.status) {
        SubscriptionStatus.expired => RenewalUrgency.critical,
        SubscriptionStatus.paused => RenewalUrgency.critical,
        SubscriptionStatus.gracePeriod => RenewalUrgency.critical,
        SubscriptionStatus.trial => RenewalUrgency.warning,
        SubscriptionStatus.active =>
          (entitlements.daysUntilRenewal ?? 99) <= 7
              ? RenewalUrgency.warning
              : RenewalUrgency.none,
      };
}

/// How prominently a renewal notice should be shown.
enum RenewalUrgency { none, warning, critical }

/// The message an entitled-or-not AI user sees.
///
/// Returned instead of a provider call, so a company that has not paid for the
/// AI premium never spends OpenAI money.
class AiAccessMessages {
  const AiAccessMessages._();

  static String forEntitlements(Entitlements entitlements) =>
      switch (entitlements.aiStatus) {
        AiEntitlementStatus.none =>
          'The AI Assistant is a premium add-on. Ask your administrator to '
              'add AI to your subscription to use it.',
        AiEntitlementStatus.expired =>
          'Your AI Assistant trial has ended. Add the AI Assistant to your '
              'subscription to keep using it.',
        _ => 'The AI Assistant is not available right now. Please try again later.',
      };
}
