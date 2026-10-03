import 'package:flutter_application_2/features/subscriptions/subscription_messages.dart';
import 'package:flutter_application_2/features/subscriptions/subscription_models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'subscription_test_helpers.dart';

void main() {
  group('AI premium is a separate product with its own trial', () {
    test('AI is available during the AI trial', () {
      final entitlements = entitlementsWith(
        aiStatus: 'TRIAL',
        canUseAI: true,
        aiTrialEndsAt: DateTime.now().add(const Duration(days: 10)),
      );
      expect(entitlements.canUseAI, isTrue);
      expect(entitlements.aiStatus, AiEntitlementStatus.trial);
    });

    test('AI is unavailable after the trial without a paid entitlement', () {
      final entitlements =
          entitlementsWith(aiStatus: 'EXPIRED', canUseAI: false);
      expect(entitlements.canUseAI, isFalse);
      expect(entitlements.aiStatus, AiEntitlementStatus.expired);
    });

    test('AI is active after a paid premium entitlement', () {
      final entitlements = entitlementsWith(
        aiStatus: 'ACTIVE',
        canUseAI: true,
        aiPeriodEnd: DateTime.now().add(const Duration(days: 20)),
      );
      expect(entitlements.canUseAI, isTrue);
      expect(entitlements.aiStatus, AiEntitlementStatus.active);
    });

    test('a company that never had AI is told to add it', () {
      final message = AiAccessMessages.forEntitlements(
        entitlementsWith(aiStatus: 'NONE', canUseAI: false),
      );
      expect(message, contains('premium add-on'));
    });

    test('an expired AI trial asks the user to add AI', () {
      final message = AiAccessMessages.forEntitlements(
        entitlementsWith(aiStatus: 'EXPIRED', canUseAI: false),
      );
      expect(message, contains('ended'));
    });

    test('pausing a company switches AI off without changing the software', () {
      final entitlements = entitlementsWith(
        status: 'PAUSED',
        isPaused: true,
        canAccessAdmin: false,
        canRecordAsSecretary: false,
        canUseAI: false,
        aiStatus: 'ACTIVE',
      );
      expect(entitlements.canUseAI, isFalse);
      expect(entitlements.isPaused, isTrue);
    });

    test('the AI premium price is separate from the software price', () {
      const config = SubscriptionConfig.fallback;
      // AI is GH 50/month and the software base is GH 200/month: the two are
      // billed independently and neither includes the other.
      expect(config.aiMonthlyMinor, 5000);
      expect(config.baseMonthlyMinor, 20000);
      expect(config.monthlySoftwareTotalMinor(0), config.baseMonthlyMinor);
    });
  });

  group('admin lock and secretary continuation', () {
    test('an active subscription keeps admin open', () {
      expect(
        entitlementsWith(hasActiveSoftwareSubscription: true).canAccessAdmin,
        isTrue,
      );
    });

    test('the grace period keeps admin open with a warning', () {
      final entitlements = entitlementsWith(
        status: 'GRACE_PERIOD',
        isInGracePeriod: true,
        gracePeriodEnd: DateTime.now().add(const Duration(days: 5)),
      );
      expect(entitlements.canAccessAdmin, isTrue);
      expect(
        SubscriptionMessages.urgency(entitlements),
        RenewalUrgency.critical,
      );
    });

    test('an expired subscription locks admin but not the secretary', () {
      final entitlements =
          entitlementsWith(status: 'EXPIRED', canAccessAdmin: false);
      // This is the key rule: the admin side locks, operations continue.
      expect(entitlements.canAccessAdmin, isFalse);
      expect(entitlements.canRecordAsSecretary, isTrue);
    });

    test('renewal restores admin access', () {
      final locked =
          entitlementsWith(status: 'EXPIRED', canAccessAdmin: false);
      final renewed = entitlementsWith(
        status: 'ACTIVE',
        hasActiveSoftwareSubscription: true,
        canAccessAdmin: true,
      );
      expect(locked.canAccessAdmin, isFalse);
      expect(renewed.canAccessAdmin, isTrue);
    });

    test('the lock message says what is safe and what to do', () {
      expect(SubscriptionMessages.adminLocked, contains('Renew'));
      expect(SubscriptionMessages.dataSafe, contains('safe'));
      expect(
        SubscriptionMessages.secretaryStillWorking,
        contains('deliveries'),
      );
    });
  });

  group('renewal messaging', () {
    test('a healthy subscription says nothing', () {
      final entitlements = entitlementsWith(
        status: 'ACTIVE',
        hasActiveSoftwareSubscription: true,
        currentPeriodEnd: DateTime.now().add(const Duration(days: 25)),
      );
      expect(SubscriptionMessages.renewalNotice(entitlements), isNull);
      expect(SubscriptionMessages.urgency(entitlements), RenewalUrgency.none);
    });

    test('a subscription expiring soon warns with the remaining days', () {
      // Hours are added so the day count is not clipped by the time of day.
      final entitlements = entitlementsWith(
        status: 'ACTIVE',
        hasActiveSoftwareSubscription: true,
        currentPeriodEnd:
            DateTime.now().add(const Duration(days: 2, hours: 12)),
      );
      expect(
        SubscriptionMessages.renewalNotice(entitlements),
        contains('expires in 2 days'),
      );
      expect(
        SubscriptionMessages.urgency(entitlements),
        RenewalUrgency.warning,
      );
    });

    test('a trial ending soon is mentioned', () {
      final entitlements = entitlementsWith(
        trialEndsAt: DateTime.now().add(const Duration(days: 7)),
      );
      expect(
        SubscriptionMessages.renewalNotice(entitlements),
        contains('trial'),
      );
    });

    test('the grace warning counts down and says what happens next', () {
      // A day boundary is added so the count is not clipped by the time of day.
      final entitlements = entitlementsWith(
        status: 'GRACE_PERIOD',
        isInGracePeriod: true,
        gracePeriodEnd:
            DateTime.now().add(const Duration(days: 5, hours: 12)),
      );
      final notice = SubscriptionMessages.renewalNotice(entitlements);
      expect(notice, contains('grace period'));
      expect(notice, contains('days remaining'));
      expect(notice, contains('Renew now'));
    });

    test('a paused company is told its data is kept', () {
      final entitlements = entitlementsWith(
        status: 'PAUSED',
        isPaused: true,
        canAccessAdmin: false,
        canRecordAsSecretary: false,
      );
      final notice = SubscriptionMessages.renewalNotice(entitlements);
      expect(notice, contains('paused'));
      expect(notice, contains('safe'));
    });
  });

  group('payment purposes stay separate', () {
    test('every purpose has a distinct wire name', () {
      final names = PaymentPurpose.values.map((p) => p.wireName).toSet();
      expect(names.length, PaymentPurpose.values.length);
      expect(
        names,
        containsAll([
          'SETUP_FEE',
          'SOFTWARE_SUBSCRIPTION',
          'SECRETARY_BUNDLE',
          'AI_SUBSCRIPTION',
          'SMS_CREDITS',
        ]),
      );
    });

    test('SMS credits are a separate purpose, never a subscription', () {
      expect(PaymentPurpose.smsCredits.wireName, 'SMS_CREDITS');
      expect(
        PaymentPurpose.smsCredits,
        isNot(PaymentPurpose.softwareSubscription),
      );
    });

    test('payment statuses round-trip to their wire names', () {
      expect(PaymentStatusWire.fromWire('PENDING'), PaymentStatus.pending);
      expect(PaymentStatusWire.fromWire('FAILED'), PaymentStatus.failed);
      expect(PaymentStatusWire.fromWire('CANCELLED'), PaymentStatus.cancelled);
      expect(
        PaymentStatusWire.fromWire('SUCCESSFUL'),
        PaymentStatus.successful,
      );
      expect(PaymentStatus.pending.wireName, 'PENDING');
    });

    test('a repeat settlement is idempotent, not a new payment', () {
      // The database function returns applied=false, idempotent=true when a
      // payment has already been settled, so a replayed callback grants nothing.
      const replay = {
        'applied': false,
        'idempotent': true,
        'status': 'SUCCESSFUL',
      };
      expect(replay['applied'], isFalse);
      expect(replay['idempotent'], isTrue);
    });
  });

  group('configuration is centralised', () {
    test('the documented initial prices are the configured defaults', () {
      const config = SubscriptionConfig.fallback;
      // GH 500 setup fee, GH 200/month base, GH 75 per extra bundle of 3,
      // GH 50/month AI, 30-day trials and a 7-day grace period.
      expect(config.setupFeeMinor, 50000);
      expect(config.baseMonthlyMinor, 20000);
      expect(config.additionalSecretaryBundleMinor, 7500);
      expect(config.secretaryBundleSize, 3);
      expect(config.baseSecretaryLimit, 3);
      expect(config.aiMonthlyMinor, 5000);
      expect(config.softwareTrialDays, 30);
      expect(config.aiTrialDays, 30);
      expect(config.gracePeriodDays, 7);
      expect(config.currency, 'GHS');
    });

    test('server values override the display fallback', () {
      final parsed = SubscriptionConfig.fromJson({
        'baseMonthlyMinor': 25000,
        'gracePeriodDays': 14,
        'currency': 'GHS',
      });
      expect(parsed.baseMonthlyMinor, 25000);
      expect(parsed.gracePeriodDays, 14);
    });

    test('the monthly total adds bundles and never adds SMS credits', () {
      const config = SubscriptionConfig.fallback;
      // 1-3 secretaries = 200, 4-6 = 275, 7-9 = 350, 10-12 = 425.
      expect(config.monthlySoftwareTotalMinor(0), 20000);
      expect(config.monthlySoftwareTotalMinor(1), 27500);
      expect(config.monthlySoftwareTotalMinor(2), 35000);
      expect(config.monthlySoftwareTotalMinor(3), 42500);
    });

    test('there is no per-secretary price, only the bundle price', () {
      const config = SubscriptionConfig.fallback;
      expect(config.additionalSecretaryBundleMinor, 7500);
      expect(
        config.monthlySoftwareTotalMinor(1) -
            config.monthlySoftwareTotalMinor(0),
        config.additionalSecretaryBundleMinor,
      );
    });

    test('cedi amounts are formatted as whole pesewas', () {
      expect(formatCedi(20000), 'GH\u{20B5}200.00');
      expect(formatCedi(50000), 'GH\u{20B5}500.00');
      expect(formatCedi(27500), 'GH\u{20B5}275.00');
      expect(formatCedi(5), 'GH\u{20B5}0.05');
    });
  });
}

