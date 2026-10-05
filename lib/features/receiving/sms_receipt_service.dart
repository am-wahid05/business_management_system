import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';

import '../../domain/models/delivery.dart';
import 'sms_transport.dart';

String _companyLabel(String? companyName) {
  final name = companyName?.trim();
  return (name == null || name.isEmpty) ? 'Company' : name;
}

class SmsReceiptException implements Exception {
  const SmsReceiptException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => message;
}

/// Read-only access to the authenticated company's server-managed SMS balance.
abstract interface class SmsCreditBalanceReader {
  Future<int?> balanceFor(String companyId);
}

class SmsRecipient {
  const SmsRecipient({required this.raw, required this.normalized});

  final String raw;
  final String normalized;
}

/// Normalizes, de-duplicates, and preserves the order of SMS recipients.
class SmsRecipientList {
  SmsRecipientList._({
    required List<SmsRecipient> unique,
    required List<String> duplicates,
    required List<String> rejected,
  }) : unique = List.unmodifiable(unique),
       duplicates = List.unmodifiable(duplicates),
       rejected = List.unmodifiable(rejected);

  factory SmsRecipientList.build(Iterable<String> rawValues) {
    final unique = <SmsRecipient>[];
    final seen = <String>{};
    final duplicateSet = <String>{};
    final rejected = <String>[];

    for (final raw in rawValues) {
      if (raw.trim().isEmpty) continue;
      final normalized = GhanaPhoneNumber.normalize(raw);
      if (normalized == null) {
        rejected.add(raw);
        continue;
      }
      if (!seen.add(normalized)) {
        duplicateSet.add(normalized);
        continue;
      }
      unique.add(SmsRecipient(raw: raw, normalized: normalized));
    }

    return SmsRecipientList._(
      unique: unique,
      duplicates: duplicateSet.toList(growable: false),
      rejected: rejected,
    );
  }

  final List<SmsRecipient> unique;
  final List<String> duplicates;
  final List<String> rejected;

  int get uniqueCount => unique.length;
  bool get isEmpty => unique.isEmpty;
  bool get hasDuplicates => duplicates.isNotEmpty;

  bool contains(String raw) {
    final normalized = GhanaPhoneNumber.normalize(raw);
    return normalized != null &&
        unique.any((item) => item.normalized == normalized);
  }
}

SmsRecipientList initialSmsRecipients(String? savedPhone) =>
    SmsRecipientList.build(savedPhone == null ? const [] : [savedPhone]);

class SmsSendFailure {
  const SmsSendFailure({
    required this.recipient,
    required this.errorCode,
    required this.message,
  });

  final SmsRecipient recipient;
  final String errorCode;
  final String message;
}

class SmsSendSummary {
  SmsSendSummary({
    required this.recipientCount,
    required this.creditsRequired,
    required this.creditsCharged,
    required this.creditsRefunded,
    required List<SmsRecipient> sent,
    required List<SmsSendFailure> failures,
    required List<String> duplicates,
    required List<String> rejected,
  }) : sent = List.unmodifiable(sent),
       failures = List.unmodifiable(failures),
       duplicates = List.unmodifiable(duplicates),
       rejected = List.unmodifiable(rejected);

  final int recipientCount;
  final int creditsRequired;
  final int creditsCharged;
  final int creditsRefunded;
  final List<SmsRecipient> sent;
  final List<SmsSendFailure> failures;
  final List<String> duplicates;
  final List<String> rejected;

  bool get allSucceeded => failures.isEmpty && sent.length == recipientCount;

  String get message {
    if (allSucceeded) {
      final noun = recipientCount == 1 ? 'recipient' : 'recipients';
      return '$recipientCount $noun accepted by the SMS provider.';
    }
    if (sent.isEmpty) return 'No SMS was accepted by the provider.';
    return '${sent.length} of $recipientCount SMS messages were accepted; '
        '${failures.length} failed and were not charged.';
  }
}

/// Sends receipt summaries while keeping company balance changes on the server.
///
/// The production transport is [SupabaseEdgeFunctionSmsTransport]. That Edge
/// Function derives the company from the authenticated membership and delivery,
/// atomically reserves the company's credits, calls the one shared Sailup
/// account, then consumes or refunds the reservation. The optional balance
/// reader here is only a fast UI guard; it never mutates a balance.
class SmsReceiptService {
  SmsReceiptService({
    http.Client? client,
    String? gatewayUrl,
    this.database,
    this.transport,
    this.senderLabel = 'Company',
    this.companyIdProvider,
    this.creditReader,
  }) : _client = client ?? http.Client(),
       _gatewayUrl =
           gatewayUrl ?? const String.fromEnvironment('SMS_GATEWAY_URL');

  final http.Client _client;
  final String _gatewayUrl;
  final Database? database;
  final SmsTransport? transport;
  final String senderLabel;
  final String? Function()? companyIdProvider;
  final SmsCreditBalanceReader? creditReader;

  Future<void> send(Delivery delivery, {String? companyName}) async {
    final summary = await sendToMany(
      delivery,
      phones: [delivery.supplier.phone ?? ''],
      companyName: companyName,
    );
    if (summary.sent.isEmpty) {
      final failure = summary.failures.isEmpty ? null : summary.failures.first;
      throw SmsReceiptException(
        failure?.message ?? 'The SMS service rejected the receipt.',
        code: failure?.errorCode,
      );
    }
  }

  Future<SmsSendSummary> sendToMany(
    Delivery delivery, {
    required Iterable<String> phones,
    String? companyName,
  }) async {
    final companyId = _resolveCompany(delivery);
    final recipients = SmsRecipientList.build(phones);
    if (recipients.isEmpty) {
      throw const SmsReceiptException(
        'A valid Ghana phone number is required before sending a receipt.',
        code: 'PHONE_REQUIRED',
      );
    }

    final requiredCredits = recipients.uniqueCount;
    final reader = creditReader;
    if (reader != null && companyId != null) {
      final balance = await reader.balanceFor(companyId);
      if (balance != null && balance < requiredCredits) {
        throw SmsReceiptException(
          requiredCredits == 1
              ? 'SMS credits exhausted. You currently have 0 SMS credits. '
                    'Please top up your SMS credits before sending a receipt.'
              : 'You do not have enough SMS credits for all the recipients on '
                    'this list. No SMS was sent and no credits were used.',
          code: balance <= 0
              ? 'SMS_CREDITS_EXHAUSTED'
              : 'SMS_CREDITS_INSUFFICIENT',
        );
      }
    }

    final pending = <SmsRecipient>[];
    for (final recipient in recipients.unique) {
      if (await _alreadySent(delivery.id, recipient.normalized, companyId)) {
        continue;
      }
      pending.add(recipient);
    }
    if (pending.isEmpty) {
      throw const SmsReceiptException(
        'This receipt was already sent by SMS.',
        code: 'RECEIPT_ALREADY_SENT',
      );
    }

    final sent = <SmsRecipient>[];
    final failures = <SmsSendFailure>[];
    var refunded = 0;
    for (final recipient in pending) {
      final result = await _sendOne(
        delivery,
        recipient,
        companyName: companyName,
      );
      if (!result.accepted) {
        refunded++;
        failures.add(
          SmsSendFailure(
            recipient: recipient,
            errorCode: result.errorCode ?? 'SMS_REJECTED',
            message:
                result.errorMessage ?? 'The SMS provider rejected the receipt.',
          ),
        );
        continue;
      }
      sent.add(recipient);
      await _recordAccepted(
        delivery,
        recipient,
        companyId: companyId,
        providerReference: result.providerReference,
      );
    }

    return SmsSendSummary(
      recipientCount: pending.length,
      creditsRequired: pending.length,
      creditsCharged: sent.length,
      creditsRefunded: refunded,
      sent: sent,
      failures: failures,
      duplicates: recipients.duplicates,
      rejected: recipients.rejected,
    );
  }

  String? _resolveCompany(Delivery delivery) {
    final provider = companyIdProvider;
    if (provider == null) return delivery.companyId;
    final activeCompany = provider();
    if (activeCompany == null || activeCompany.trim().isEmpty) {
      throw const SmsReceiptException(
        'Select an active company before sending a receipt.',
        code: 'COMPANY_ACCESS_REQUIRED',
      );
    }
    if (delivery.companyId != null && delivery.companyId != activeCompany) {
      throw const SmsReceiptException(
        'This receipt belongs to a different company.',
        code: 'COMPANY_ACCESS_REQUIRED',
      );
    }
    return activeCompany;
  }

  Future<bool> _alreadySent(
    String deliveryId,
    String phone,
    String? companyId,
  ) async {
    final db = database;
    if (db == null) return false;
    final clauses = <String>[
      'delivery_id = ?',
      'channel = ?',
      'status IN (?, ?)',
    ];
    final args = <Object?>[deliveryId, 'sms', 'sent', 'queued'];
    if (companyId != null) {
      clauses.add('company_id = ?');
      args.add(companyId);
    }
    clauses.add('phone = ?');
    args.add(phone);
    final rows = await db.query(
      'receipt_sends',
      columns: ['id'],
      where: clauses.join(' AND '),
      whereArgs: args,
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<SmsSendResult> _sendOne(
    Delivery delivery,
    SmsRecipient recipient, {
    String? companyName,
  }) async {
    final message = _message(delivery, companyName);
    final configuredTransport = transport;
    if (configuredTransport != null) {
      return configuredTransport.send(
        phone: recipient.normalized,
        message: message,
        reference: delivery.id,
      );
    }
    if (_gatewayUrl.trim().isEmpty) {
      return const SmsSendResult.rejected(
        'SMS_NOT_CONFIGURED',
        'SMS sending is not configured. Set SMS_GATEWAY_URL to your secure backend endpoint.',
      );
    }
    try {
      final response = await _client
          .post(
            Uri.parse(_gatewayUrl),
            headers: const {'content-type': 'application/json'},
            body: jsonEncode({
              'to': recipient.normalized,
              'message': message,
              'reference': delivery.id,
            }),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return SmsSendResult.rejected(
          'SMS_REJECTED',
          'The SMS service rejected the receipt (${response.statusCode}).',
        );
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic> || decoded['accepted'] != true) {
        return const SmsSendResult.rejected(
          'SMS_NOT_CONFIRMED',
          'The SMS provider did not confirm receipt submission.',
        );
      }
      return SmsSendResult.accepted(
        providerReference: decoded['reference'] as String?,
      );
    } catch (_) {
      return const SmsSendResult.rejected(
        'SMS_UNREACHABLE',
        'The SMS service could not be reached. Check the connection and try again.',
      );
    }
  }

  Future<void> _recordAccepted(
    Delivery delivery,
    SmsRecipient recipient, {
    required String? companyId,
    String? providerReference,
  }) async {
    final db = database;
    if (db == null) return;
    final row = <String, Object?>{
      'id':
          'sms-${DateTime.now().microsecondsSinceEpoch}-${recipient.normalized}',
      'delivery_id': delivery.id,
      'phone': recipient.normalized,
      'channel': 'sms',
      'status': 'queued',
      'sent_at': DateTime.now().toUtc().toIso8601String(),
      'provider_reference': providerReference ?? 'sms-provider',
    };
    if (companyId != null) row['company_id'] = companyId;
    await db.insert('receipt_sends', row);
  }

  String _message(Delivery delivery, String? companyName) {
    final weights = delivery.isBulk
        ? null
        : delivery.bagWeights
              .asMap()
              .entries
              .map(
                (entry) =>
                    '${entry.key + 1}. ${entry.value.toStringAsFixed(1)} kg',
              )
              .join('\n');
    final weightsSection = weights == null
        ? 'Bags: ${delivery.numberOfBags}\nTotal Weight: ${delivery.totalWeight.toStringAsFixed(1)} kg'
        : 'Weights:\n$weights\n\nTotal Weight: ${delivery.totalWeight.toStringAsFixed(1)} kg';
    return '${_companyLabel(companyName ?? senderLabel)}\n\nReceipt\n'
        'Customer: ${delivery.supplier.name}\nDate: ${_date(delivery.recordedAt)}\n'
        'Reference: ${delivery.id}\n\n$weightsSection\n\n'
        'Thank you for doing business with us.';
  }

  static String _date(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}

abstract final class GhanaPhoneNumber {
  static String? normalize(String? value) {
    if (value == null) return null;
    var digits = value.replaceAll(RegExp(r'[^0-9+]'), '');
    if (digits.startsWith('+233')) digits = digits.substring(1);
    if (digits.startsWith('233')) {
      digits = digits.substring(3);
    } else if (digits.startsWith('0')) {
      digits = digits.substring(1);
    } else {
      return null;
    }
    if (digits.length != 9 || !RegExp(r'^[2357]').hasMatch(digits)) {
      return null;
    }
    return '233$digits';
  }
}

String? validateRequiredGhanaPhone(String? value) {
  if (value == null || value.trim().isEmpty) {
    return 'Phone number is required';
  }
  if (GhanaPhoneNumber.normalize(value) == null) {
    return 'Enter a valid Ghana phone number';
  }
  return null;
}
