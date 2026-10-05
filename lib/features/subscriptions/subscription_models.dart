/// The lifecycle of a company's software subscription.
///
/// This is an explicit state machine, mirroring the `subscription_status` enum
/// in the database. The two are kept in step deliberately: the database is
/// authoritative, and this enum is how the app reads that state.
enum SubscriptionStatus {
  /// Free trial, running now.
  trial,

  /// Paid and current.
  active,

  /// Paid period has lapsed, but the courtesy window is still running.
  gracePeriod,

  /// The grace window is over. The admin side is locked; the company and all of
  /// its data are untouched.
  expired,

  /// Season ended. Everything is kept; the software is simply not running.
  paused,
}

/// The AI premium's own lifecycle, tracked separately from the software
/// subscription and with its own trial.
enum AiEntitlementStatus {
  /// Never had AI, and the trial is not running.
  none,

  /// In the free AI trial.
  trial,

  /// AI premium paid and current.
  active,

  /// AI premium lapsed. The assistant reports an upgrade message and makes no
  /// provider call.
  expired,
}

/// What a payment is for. Kept distinct so credits and subscriptions can never
/// be confused with one another.
enum PaymentPurpose {
  /// One-time onboarding charge.
  setupFee,

  /// The recurring monthly software subscription.
  softwareSubscription,

  /// Additional secretaries, sold only in fixed bundles.
  secretaryBundle,

  /// The AI premium, billed separately from the software.
  aiSubscription,

  /// SMS credits, which are NOT part of the software subscription.
  smsCredits,
}

extension PaymentPurposeWire on PaymentPurpose {
  String get wireName => switch (this) {
    PaymentPurpose.setupFee => 'SETUP_FEE',
    PaymentPurpose.softwareSubscription => 'SOFTWARE_SUBSCRIPTION',
    PaymentPurpose.secretaryBundle => 'SECRETARY_BUNDLE',
    PaymentPurpose.aiSubscription => 'AI_SUBSCRIPTION',
    PaymentPurpose.smsCredits => 'SMS_CREDITS',
  };

  static PaymentPurpose fromWire(String value) => switch (value) {
    'SETUP_FEE' => PaymentPurpose.setupFee,
    'SECRETARY_BUNDLE' => PaymentPurpose.secretaryBundle,
    'AI_SUBSCRIPTION' => PaymentPurpose.aiSubscription,
    'SMS_CREDITS' => PaymentPurpose.smsCredits,
    _ => PaymentPurpose.softwareSubscription,
  };
}

/// A payment's state. Only `successful` ever grants anything.
enum PaymentStatus {
  pending,
  processing,
  successful,
  failed,
  cancelled,
  expired,
  refunded,
}

extension PaymentStatusWire on PaymentStatus {
  String get wireName => wireNameFrom(this);

  static String wireNameFrom(PaymentStatus status) => switch (status) {
    PaymentStatus.pending => 'PENDING',
    PaymentStatus.processing => 'PROCESSING',
    PaymentStatus.successful => 'SUCCESSFUL',
    PaymentStatus.failed => 'FAILED',
    PaymentStatus.cancelled => 'CANCELLED',
    PaymentStatus.expired => 'EXPIRED',
    PaymentStatus.refunded => 'REFUNDED',
  };

  static PaymentStatus fromWire(String value) => switch (value) {
    'PROCESSING' => PaymentStatus.processing,
    'SUCCESSFUL' => PaymentStatus.successful,
    'FAILED' => PaymentStatus.failed,
    'CANCELLED' => PaymentStatus.cancelled,
    'EXPIRED' => PaymentStatus.expired,
    'REFUNDED' => PaymentStatus.refunded,
    _ => PaymentStatus.pending,
  };
}

/// Prices and durations, read from the server's `subscription_config`.
///
/// These are NEVER hardcoded as an authority in Dart. They are fetched from the
/// database, which is the single source of truth, so changing a price is one
/// database update rather than a code change and a redeploy. [fallback] exists
/// only for the moment before the first fetch completes; it is never used for
/// an authorization decision, and the server always has the final say.
class SubscriptionConfig {
  const SubscriptionConfig({
    required this.currency,
    required this.setupFeeMinor,
    required this.baseMonthlyMinor,
    required this.additionalSecretaryBundleMinor,
    required this.secretaryBundleSize,
    required this.baseSecretaryLimit,
    required this.aiMonthlyMinor,
    required this.softwareTrialDays,
    required this.aiTrialDays,
    required this.gracePeriodDays,
  });

  /// Mirrors the migration's defaults. Display only; the server decides.
  static const fallback = SubscriptionConfig(
    currency: 'GHS',
    setupFeeMinor: 50000,
    baseMonthlyMinor: 20000,
    additionalSecretaryBundleMinor: 7500,
    secretaryBundleSize: 3,
    baseSecretaryLimit: 3,
    aiMonthlyMinor: 5000,
    softwareTrialDays: 30,
    aiTrialDays: 30,
    gracePeriodDays: 7,
  );

  final String currency;

  /// One-time onboarding charge, in pesewas. Separate from the subscription.
  final int setupFeeMinor;

  /// The recurring monthly software subscription, in pesewas.
  final int baseMonthlyMinor;

  /// One additional bundle of secretaries, in pesewas. There is no per-secretary
  /// price anywhere in this system.
  final int additionalSecretaryBundleMinor;

  /// How many secretaries one bundle adds.
  final int secretaryBundleSize;

  /// How many secretaries the base subscription includes.
  final int baseSecretaryLimit;

  /// The AI premium's monthly price, billed separately.
  final int aiMonthlyMinor;

  final int softwareTrialDays;
  final int aiTrialDays;
  final int gracePeriodDays;

  factory SubscriptionConfig.fromJson(
    Map<String, dynamic> json,
  ) => SubscriptionConfig(
    currency: (json['currency'] as String?) ?? fallback.currency,
    setupFeeMinor:
        (json['setupFeeMinor'] as num?)?.toInt() ?? fallback.setupFeeMinor,
    baseMonthlyMinor:
        (json['baseMonthlyMinor'] as num?)?.toInt() ??
        fallback.baseMonthlyMinor,
    additionalSecretaryBundleMinor:
        (json['additionalSecretaryBundleMinor'] as num?)?.toInt() ??
        fallback.additionalSecretaryBundleMinor,
    secretaryBundleSize:
        (json['secretaryBundleSize'] as num?)?.toInt() ??
        fallback.secretaryBundleSize,
    baseSecretaryLimit:
        (json['baseSecretaryLimit'] as num?)?.toInt() ??
        fallback.baseSecretaryLimit,
    aiMonthlyMinor:
        (json['aiMonthlyMinor'] as num?)?.toInt() ?? fallback.aiMonthlyMinor,
    softwareTrialDays:
        (json['softwareTrialDays'] as num?)?.toInt() ??
        fallback.softwareTrialDays,
    aiTrialDays: (json['aiTrialDays'] as num?)?.toInt() ?? fallback.aiTrialDays,
    gracePeriodDays:
        (json['gracePeriodDays'] as num?)?.toInt() ?? fallback.gracePeriodDays,
  );

  /// The total monthly software cost for a given number of extra bundles.
  ///
  /// SMS credits are deliberately absent: they are a separate product with a
  /// separate balance, and are never folded into a subscription total.
  int monthlySoftwareTotalMinor(int bundles) =>
      baseMonthlyMinor + additionalSecretaryBundleMinor * bundles;
}

/// The cedi symbol used for display, written as an escape so this source file
/// stays plain ASCII.
const String cediSign = 'GH\u{20B5}';

/// Formats an integer pesewa amount for display, e.g. 20000 -> "GH 200.00".
///
/// Money is always integer minor units; this is the only place it becomes a
/// decimal, and it is display only.
String formatCedi(int amountMinor, {String currency = 'GHS'}) {
  final symbol = currency.toUpperCase() == 'GHS' ? cediSign : '$currency ';
  final negative = amountMinor < 0;
  final absolute = amountMinor.abs();
  final whole = absolute ~/ 100;
  final pesewas = absolute % 100;
  final grouped = whole.toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (match) => '${match[1]},',
  );
  final text = '$symbol$grouped.${pesewas.toString().padLeft(2, '0')}';
  return negative ? '-$text' : text;
}
