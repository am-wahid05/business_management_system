import 'package:supabase_flutter/supabase_flutter.dart';

import '../receiving/sms_receipt_service.dart';
import 'sms_credit_pricing.dart';

/// Read-only view of one company's SMS credit balance.
class SmsCreditBalance {
  const SmsCreditBalance({
    required this.companyId,
    required this.companyName,
    required this.balance,
  });

  final String companyId;
  final String companyName;

  /// Credits available to this company. Never negative.
  final int balance;

  bool get isExhausted => balance <= 0;
}

/// One auditable credit ledger entry.
class SmsCreditTransaction {
  const SmsCreditTransaction({
    required this.id,
    required this.companyId,
    required this.type,
    required this.credits,
    required this.balanceAfter,
    required this.status,
    required this.createdAt,
    this.amountMinor,
    this.currency,
    this.paymentReference,
  });

  final String id;
  final String companyId;

  /// 'purchase', 'usage' or 'refund'.
  final String type;

  /// Signed: positive adds credits, negative spends them.
  final int credits;
  final int balanceAfter;

  /// 'pending', 'successful', 'failed' or 'cancelled'.
  final String status;
  final DateTime? createdAt;

  /// Integer minor units for a purchase; null for usage and refund rows.
  final int? amountMinor;
  final String? currency;
  final String? paymentReference;

  bool get isPurchase => type == 'purchase';
  bool get isUsage => type == 'usage';
  bool get isRefund => type == 'refund';

  factory SmsCreditTransaction.fromRow(Map<String, dynamic> row) =>
      SmsCreditTransaction(
        id: row['id'] as String,
        companyId: row['company_id'] as String,
        type: row['type'] as String,
        credits: (row['credits'] as num).toInt(),
        balanceAfter: (row['balance_after'] as num?)?.toInt() ?? 0,
        status: row['status'] as String,
        createdAt: row['created_at'] == null
            ? null
            : DateTime.tryParse(row['created_at'] as String),
        amountMinor: (row['amount_minor'] as num?)?.toInt(),
        currency: row['currency'] as String?,
        paymentReference: row['payment_reference'] as String?,
      );
}

/// Snapshot of balances and recent history.
class SmsCreditSnapshot {
  const SmsCreditSnapshot({required this.balances, required this.transactions});

  final List<SmsCreditBalance> balances;
  final List<SmsCreditTransaction> transactions;

  /// The balance for the active company, or null when it is not loaded.
  SmsCreditBalance? balanceFor(String companyId) {
    for (final balance in balances) {
      if (balance.companyId == companyId) return balance;
    }
    return null;
  }

  static const empty = SmsCreditSnapshot(balances: [], transactions: []);
}

/// Reads SMS credit balances and history.
///
/// This class is deliberately read-only. There is no method that can change a
/// balance: credits are added only by the server after a verified payment, or
/// refunded automatically when an SMS submission fails. There is no "add
/// credits" call available to any role, including owner and admin.
///
/// The company comes from [companyId], supplied by the caller from the
/// authenticated user's own active company. The Edge Function intersects it
/// with the caller's own memberships, so another company's balance can never be
/// read even if the caller asks for it.
class SmsCreditService implements SmsCreditBalanceReader {
  const SmsCreditService(this._client);

  final SupabaseClient? _client;

  /// True when credits can be shown. Offline mode has no server balance, and no
  /// balance is invented in that case.
  bool get isAvailable => _client != null;

  Future<SmsCreditSnapshot> load({String? companyId}) async {
    final client = _client;
    if (client == null) return SmsCreditSnapshot.empty;

    // The company filter is sent in the body. It is optional, and the Edge
    // Function intersects it with the caller's own memberships, so asking for
    // another company simply returns nothing.
    final response = await client.functions.invoke(
      'sms-credits',
      body: companyId == null
          ? const <String, dynamic>{}
          : {'company_id': companyId},
    );
    final data = response.data;
    if (data is! Map) return SmsCreditSnapshot.empty;

    final balances = <SmsCreditBalance>[];
    final rawBalances = data['balances'];
    if (rawBalances is List) {
      for (final item in rawBalances) {
        if (item is! Map) continue;
        balances.add(
          SmsCreditBalance(
            companyId: item['company_id'] as String? ?? '',
            companyName: item['company_name'] as String? ?? 'Company',
            balance: (item['balance'] as num?)?.toInt() ?? 0,
          ),
        );
      }
    }

    final transactions = <SmsCreditTransaction>[];
    final rawTransactions = data['transactions'];
    if (rawTransactions is List) {
      for (final item in rawTransactions) {
        if (item is Map) {
          transactions.add(
            SmsCreditTransaction.fromRow(Map<String, dynamic>.from(item)),
          );
        }
      }
    }

    return SmsCreditSnapshot(balances: balances, transactions: transactions);
  }

  /// Top-up is not yet available: no payment provider is integrated.
  ///
  /// This never pretends a payment succeeded and never adds credits. It exists
  /// so the UI can report the state honestly until a payment provider is
  /// connected.
  Future<SmsTopUpOutcome> startTopUp({required int credits}) async {
    if (!validateCreditQuantity(credits.toString()).isValid) {
      return const SmsTopUpOutcome.unavailable(
        'Enter a valid number of credits.',
      );
    }
    return const SmsTopUpOutcome.unavailable(
      'Payment is not available yet. SMS credit top up will be enabled once '
      'the payment provider is connected. No credits have been added.',
    );
  }

  /// Reads the balance for the pre-send credit check in a multi-recipient send.
  ///
  /// Returns null when the balance cannot be determined (offline, or the server
  /// is unreachable). A null is deliberately NOT treated as zero: the
  /// server-side atomic reservation remains the authority, so an unreadable
  /// balance must not block a send the company can actually afford.
  @override
  Future<int?> balanceFor(String companyId) async {
    final snapshot = await load(companyId: companyId);
    return snapshot.balanceFor(companyId)?.balance;
  }
}

/// Result of attempting to start a top-up.
class SmsTopUpOutcome {
  const SmsTopUpOutcome._({
    required this.started,
    required this.message,
    this.checkoutUrl,
    this.reference,
  });

  /// A payment could be started. Never true while no provider is configured.
  const SmsTopUpOutcome.unavailable(String message)
    : this._(started: false, message: message);

  const SmsTopUpOutcome.started({
    required String message,
    required String checkoutUrl,
    required String reference,
  }) : this._(
         started: true,
         message: message,
         checkoutUrl: checkoutUrl,
         reference: reference,
       );

  final bool started;
  final String message;
  final String? checkoutUrl;
  final String? reference;
}
