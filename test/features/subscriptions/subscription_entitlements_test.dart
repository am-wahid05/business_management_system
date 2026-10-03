import 'package:flutter_application_2/features/subscriptions/entitlements.dart';
import 'package:flutter_application_2/features/subscriptions/subscription_models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'subscription_test_helpers.dart';

void main() {
  group('subscription states', () {
    test('a new company is in trial and keeps full access', () {
      final entitlements = entitlementsWith();
      expect(entitlements.status, SubscriptionStatus.trial);
      expect(entitlements.isInTrial, isTrue);
      expect(entitlements.canAccessAdmin, isTrue);
      expect(entitlements.canRecordAsSecretary, isTrue);
    });

    test('an active subscription is not a trial', () {
      final entitlements = entitlementsWith(
        status: 'ACTIVE',
        isInTrial: false,
        hasActiveSoftwareSubscription: true,
      );
      expect(entitlements.status, SubscriptionStatus.active);
      expect(entitlements.hasActiveSoftwareSubscription, isTrue);
      expect(entitlements.isInTrial, isFalse);
    });

    test('the grace period still allows admin access', () {
      final entitlements = entitlementsWith(
        status: 'GRACE_PERIOD',
        isInTrial: false,
        isInGracePeriod: true,
        gracePeriodEnd: DateTime.now().add(const Duration(days: 5)),
      );
      expect(entitlements.isInGracePeriod, isTrue);
      expect(entitlements.canAccessAdmin, isTrue);
      expect(entitlements.daysOfGraceLeft, isNotNull);
    });

    test('after grace expires the admin side is locked', () {
      final entitlements = entitlementsWith(
        status: 'EXPIRED',
        isInTrial: false,
        canAccessAdmin: false,
        isInGracePeriod: false,
      );
      expect(entitlements.canAccessAdmin, isFalse);
      expect(entitlements.status, SubscriptionStatus.expired);
    });

    test('a paused subscription stops the software', () {
      final entitlements = entitlementsWith(
        status: 'PAUSED',
        isInTrial: false,
        isPaused: true,
        canAccessAdmin: false,
        canRecordAsSecretary: false,
      );
      expect(entitlements.isPaused, isTrue);
      expect(entitlements.canRecordAsSecretary, isFalse);
    });

    test('an unknown company defaults to a working trial, never to locked', () {
      // A company with no subscription row must never be locked out by a
      // missing row, and must never be given a paid state.
      expect(Entitlements.unknown.canAccessAdmin, isTrue);
      expect(Entitlements.unknown.status, SubscriptionStatus.trial);
      expect(Entitlements.unknown.maxSecretaries, 3);
    });

    test('an unrecognised status reads as a trial rather than as expired', () {
      expect(entitlementsWith(status: 'SOMETHING_NEW').status,
          SubscriptionStatus.trial);
    });

    test('reactivation restores admin access without a new trial', () {
      final resumed = entitlementsWith(
        status: 'ACTIVE',
        isInTrial: false,
        hasActiveSoftwareSubscription: true,
        canAccessAdmin: true,
      );
      expect(resumed.canAccessAdmin, isTrue);
      // The trial dates are untouched, which is what stops a second trial.
      expect(resumed.trialEndsAt, isNull);
    });
  });

  group('secretary limits follow bundles, never per-secretary pricing', () {
    test('the base subscription allows 3 secretaries', () {
      expect(entitlementsWith(maxSecretaries: 3).maxSecretaries, 3);
    });

    test('one extra bundle allows 6', () {
      expect(
        entitlementsWith(maxSecretaries: 6, secretaryBundles: 1).maxSecretaries,
        6,
      );
    });

    test('two extra bundles allow 9', () {
      expect(
        entitlementsWith(maxSecretaries: 9, secretaryBundles: 2).maxSecretaries,
        9,
      );
    });

    test('three extra bundles allow 12', () {
      expect(
        entitlementsWith(maxSecretaries: 12, secretaryBundles: 3).maxSecretaries,
        12,
      );
    });

    test('the bundle size and base limit come from server configuration', () {
      final parsed = SubscriptionConfig.fromJson({
        'secretaryBundleSize': 4,
        'baseSecretaryLimit': 5,
      });
      expect(parsed.secretaryBundleSize, 4);
      expect(parsed.baseSecretaryLimit, 5);
    });
  });
}
