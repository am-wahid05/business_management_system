import 'subscription_models.dart';

/// What a company is currently allowed to do.
///
/// This mirrors the `company_entitlements` projection in the database. The
/// SERVER is authoritative: these values are read from the `subscription-status`
/// Edge Function, which derives them from the database. Flutter caches them for
/// display and for keeping the UI sensible, but a client value is never the
/// final authority for any security decision.
class Entitlements {
  const Entitlements({
    required this.status,
    required this.isInTrial,
    required this.canAccessAdmin,
    required this.canRecordAsSecretary,
    required this.hasActiveSoftwareSubscription,
    required this.isInGracePeriod,
    required this.isPaused,
    required this.canUseAI,
    required this.aiStatus,
    required this.maxSecretaries,
    required this.secretaryBundles,
    required this.config,
    this.trialEndsAt,
    this.currentPeriodStart,
    this.currentPeriodEnd,
    this.gracePeriodEnd,
    this.aiTrialEndsAt,
    this.aiPeriodEnd,
  });

  final SubscriptionStatus status;
  final bool isInTrial;

  /// Whether the admin/owner management side is available. This is the one
  /// thing a lapsed subscription actually locks.
  final bool canAccessAdmin;

  /// Whether a secretary may keep recording deliveries. This deliberately does
  /// NOT depend on the admin gate, so a company can always finish the work in
  /// progress even when its admin access has lapsed.
  final bool canRecordAsSecretary;

  final bool hasActiveSoftwareSubscription;
  final bool isInGracePeriod;
  final bool isPaused;

  /// Whether the AI assistant may be used at all.
  final bool canUseAI;
  final AiEntitlementStatus aiStatus;

  /// The paid secretary allowance: base plus bundles times the bundle size.
  final int maxSecretaries;
  final int secretaryBundles;

  final SubscriptionConfig config;

  final DateTime? trialEndsAt;
  final DateTime? currentPeriodStart;
  final DateTime? currentPeriodEnd;
  final DateTime? gracePeriodEnd;
  final DateTime? aiTrialEndsAt;
  final DateTime? aiPeriodEnd;

  /// A company with no subscription row at all still gets the free trial, so a
  /// missing row must never read as "locked". This is the safe default used
  /// before the first fetch completes, and while offline.
  static const unknown = Entitlements(
    status: SubscriptionStatus.trial,
    isInTrial: true,
    canAccessAdmin: true,
    canRecordAsSecretary: true,
    hasActiveSoftwareSubscription: false,
    isInGracePeriod: false,
    isPaused: false,
    canUseAI: true,
    aiStatus: AiEntitlementStatus.trial,
    maxSecretaries: 3,
    secretaryBundles: 0,
    config: SubscriptionConfig.fallback,
  );

  factory Entitlements.fromJson(Map<String, dynamic> json) => Entitlements(
    status: _statusFromWire(json['status'] as String?),
    isInTrial: json['isInTrial'] == true,
    canAccessAdmin: json['canAccessAdmin'] == true,
    canRecordAsSecretary: json['canRecordAsSecretary'] == true,
    hasActiveSoftwareSubscription:
        json['hasActiveSoftwareSubscription'] == true,
    isInGracePeriod: json['isInGracePeriod'] == true,
    isPaused: json['isPaused'] == true,
    canUseAI: json['canUseAI'] == true,
    aiStatus: _aiStatusFromWire(json['aiStatus'] as String?),
    maxSecretaries: (json['maxSecretaries'] as num?)?.toInt() ?? 0,
    secretaryBundles: (json['secretaryBundles'] as num?)?.toInt() ?? 0,
    config: SubscriptionConfig.fromJson(json),
    trialEndsAt: _date(json['trialEndsAt']),
    currentPeriodStart: _date(json['currentPeriodStart']),
    currentPeriodEnd: _date(json['currentPeriodEnd']),
    gracePeriodEnd: _date(json['gracePeriodEnd']),
    aiTrialEndsAt: _date(json['aiTrialEndsAt']),
    aiPeriodEnd: _date(json['aiPeriodEnd']),
  );

  static SubscriptionStatus _statusFromWire(String? value) => switch (value) {
    'ACTIVE' => SubscriptionStatus.active,
    'GRACE_PERIOD' => SubscriptionStatus.gracePeriod,
    'EXPIRED' => SubscriptionStatus.expired,
    'PAUSED' => SubscriptionStatus.paused,
    _ => SubscriptionStatus.trial,
  };

  static AiEntitlementStatus _aiStatusFromWire(String? value) =>
      switch (value) {
        'ACTIVE' => AiEntitlementStatus.active,
        'TRIAL' => AiEntitlementStatus.trial,
        'EXPIRED' => AiEntitlementStatus.expired,
        _ => AiEntitlementStatus.none,
      };

  static DateTime? _date(Object? value) =>
      value is String ? DateTime.tryParse(value)?.toLocal() : null;

  /// Whole days until the current period ends, or null when there is no period.
  int? get daysUntilRenewal => _daysUntil(currentPeriodEnd);

  /// Whole days of grace left, or null when no grace period is running.
  int? get daysOfGraceLeft =>
      isInGracePeriod ? _daysUntil(gracePeriodEnd) : null;

  /// Whole days of trial left, or null when no trial is running.
  int? get daysOfTrialLeft => isInTrial ? _daysUntil(trialEndsAt) : null;

  int? _daysUntil(DateTime? end) {
    if (end == null) return null;
    final difference = end.difference(DateTime.now()).inDays;
    return difference < 0 ? 0 : difference;
  }
}
