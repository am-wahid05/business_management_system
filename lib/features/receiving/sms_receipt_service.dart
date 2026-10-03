import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';

import '../../domain/models/delivery.dart';
import 'sms_transport.dart';

/// Neutral label used when the active company does not provide a name.
/// Receipts are customer-facing, so tenant-specific branding must never be
/// hardcoded here.
String _companyLabel(String? companyName) {
  final name = companyName?.trim();
  return (name == null || name.isEmpty) ? 'Company' : name;
}

class SmsReceiptException implements Exception {
  const SmsReceiptException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Read-only access to the authenticated company's server-managed SMS balance.
/// Sending services may consult it before a send, but only the server can
/// reserve or change credits.
abstract interface class SmsCreditBalanceReader {
  Future<int?> balanceFor(String companyId);
}

class SmsReceiptService {
  SmsReceiptService({
    http.Client? client,
    String? gatewayUrl,
    this._database,
    this.transport,
  }) : _client = client ?? http.Client(),
       _gatewayUrl =
           gatewayUrl ?? const String.fromEnvironment('SMS_GATEWAY_URL');

  final http.Client _client;
  final String _gatewayUrl;
  final Database? _database;
  final SmsTransport? transport;

  Future<void> send(Delivery delivery, {String? companyName}) async {
    final phone = GhanaPhoneNumber.normalize(delivery.supplier.phone);
    if (phone == null) {
      throw const SmsReceiptException(
        'A valid Ghana phone number is required before sending a receipt.',
      );
    }
    final database = _database;
    if (database != null) {
      final previous = await database.query(
        'receipt_sends',
        where: 'delivery_id = ? AND channel = ? AND status = ?',
        whereArgs: [delivery.id, 'sms', 'sent'],
        limit: 1,
      );
      if (previous.isNotEmpty) {
        throw const SmsReceiptException(
          'This receipt was already sent by SMS.',
        );
      }
    }
    final configuredTransport = transport;
    if (configuredTransport != null) {
      final result = await configuredTransport.send(
        phone: phone,
        message: _message(delivery, companyName),
        reference: delivery.id,
      );
      if (!result.accepted) {
        throw SmsReceiptException(
          result.errorMessage ?? 'The SMS service rejected the receipt.',
        );
      }
      return;
    }
    if (_gatewayUrl.trim().isEmpty) {
      throw const SmsReceiptException(
        'SMS sending is not configured. Set SMS_GATEWAY_URL to your secure backend endpoint.',
      );
    }

    late http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse(_gatewayUrl),
            headers: const {'content-type': 'application/json'},
            body: jsonEncode({
              'to': phone,
              'message': _message(delivery, companyName),
              'reference': delivery.id,
            }),
          )
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      throw const SmsReceiptException(
        'The SMS service could not be reached. Check the connection and try again.',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SmsReceiptException(
        'The SMS service rejected the receipt (${response.statusCode}).',
      );
    }
    late Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      throw const SmsReceiptException(
        'The SMS service returned an invalid response.',
      );
    }
    if (decoded is! Map<String, dynamic> || decoded['accepted'] != true) {
      throw const SmsReceiptException(
        'The SMS provider did not confirm receipt submission.',
      );
    }
    if (database != null) {
      await database.insert('receipt_sends', {
        'id': 'sms-${DateTime.now().microsecondsSinceEpoch}',
        'delivery_id': delivery.id,
        'phone': phone,
        'channel': 'sms',
        'status': 'sent',
        'sent_at': DateTime.now().toUtc().toIso8601String(),
      });
    }
  }

  static String _message(Delivery delivery, String? companyName) {
    // A weighing-bridge record has no bag weights, so the per-bag breakdown is
    // omitted for it entirely. Listing nothing there would read as a broken
    // receipt, and inventing per-bag figures from the total would misstate what
    // was actually measured.
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
    return '${_companyLabel(companyName)}\n\nReceipt\nCustomer: ${delivery.supplier.name}\nDate: ${_date(delivery.recordedAt)}\nReference: ${delivery.id}\n\n$weightsSection\n\nThank you for doing business with us.';
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
    if (digits.length != 9 || !digits.startsWith(RegExp(r'[2357]'))) {
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
