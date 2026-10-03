import 'package:flutter_application_2/features/subscriptions/entitlements.dart';
import 'package:flutter_application_2/features/subscriptions/subscription_models.dart';

/// Builds an [Entitlements] exactly the way the server projection would, so the
/// tests exercise the real JSON parsing and the real derived getters rather
/// than hand-constructed objects.
Entitlements entitlementsWith({
  String status = 'TRIAL',
  bool isInTrial = true,
  bool canAccessAdmin = true,
  bool canRecordAsSecretary = true,
  bool hasActiveSoftwareSubscription = false,
  bool isInGracePeriod = false,
  bool isPaused = false,
  bool canUseAI = true,
  String aiStatus = 'TRIAL',
  int maxSecretaries = 3,
  int secretaryBundles = 0,
  DateTime? trialEndsAt,
  DateTime? currentPeriodEnd,
  DateTime? gracePeriodEnd,
  DateTime? aiTrialEndsAt,
  DateTime? aiPeriodEnd,
  SubscriptionConfig config = SubscriptionConfig.fallback,
}) =>
    Entitlements.fromJson({
      'status': status,
      'isInTrial': isInTrial,
      'canAccessAdmin': canAccessAdmin,
      'canRecordAsSecretary': canRecordAsSecretary,
      'hasActiveSoftwareSubscription': hasActiveSoftwareSubscription,
      'isInGracePeriod': isInGracePeriod,
      'isPaused': isPaused,
      'canUseAI': canUseAI,
      'aiStatus': aiStatus,
      'maxSecretaries': maxSecretaries,
      'secretaryBundles': secretaryBundles,
      'trialEndsAt': trialEndsAt?.toIso8601String(),
      'currentPeriodEnd': currentPeriodEnd?.toIso8601String(),
      'gracePeriodEnd': gracePeriodEnd?.toIso8601String(),
      'aiTrialEndsAt': aiTrialEndsAt?.toIso8601String(),
      'aiPeriodEnd': aiPeriodEnd?.toIso8601String(),
      'currency': config.currency,
      'setupFeeMinor': config.setupFeeMinor,
      'baseMonthlyMinor': config.baseMonthlyMinor,
      'additionalSecretaryBundleMinor':
          config.additionalSecretaryBundleMinor,
      'secretaryBundleSize': config.secretaryBundleSize,
      'baseSecretaryLimit': config.baseSecretaryLimit,
      'aiMonthlyMinor': config.aiMonthlyMinor,
      'softwareTrialDays': config.softwareTrialDays,
      'aiTrialDays': config.aiTrialDays,
      'gracePeriodDays': config.gracePeriodDays,
    });
