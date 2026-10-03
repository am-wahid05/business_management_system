import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Outcome of a single SMS submission attempt.
class SmsSendResult {
  const SmsSendResult.accepted({this.providerReference, this.status = 'queued'})
    : accepted = true,
      errorCode = null,
      errorMessage = null;

  const SmsSendResult.rejected(this.errorCode, this.errorMessage)
    : accepted = false,
      status = 'failed',
      providerReference = null;

  final bool accepted;

  /// 'queued' means the provider accepted the message for delivery.
  /// It must never be reported to the user as delivered.
  final String status;
  final String? providerReference;
  final String? errorCode;
  final String? errorMessage;
}

/// Transport used to hand a receipt summary to the SMS backend.
///
/// The concrete transport is injectable so tests never need a network, and so
/// the SMS provider itself stays behind the Supabase Edge Function boundary.
abstract interface class SmsTransport {
  Future<SmsSendResult> send({
    required String phone,
    required String message,
    required String reference,
  });
}

/// Production transport: an authenticated Supabase Edge Function owns the
/// provider credential, so no API secret ever reaches the client.
///
/// Only the delivery reference and the recipient number are sent. The company
/// and the sender ID are derived server-side from the caller's membership and
/// the delivery's company, so this client can neither select nor influence which
/// sender ID is used.
class SupabaseEdgeFunctionSmsTransport implements SmsTransport {
  const SupabaseEdgeFunctionSmsTransport(this.client);

  final SupabaseClient client;

  @override
  Future<SmsSendResult> send({
    required String phone,
    required String message,
    required String reference,
  }) async {
    try {
      final response = await client.functions.invoke(
        'send-sms-receipt',
        body: {'delivery_id': reference, 'phone': phone},
      );
      final data = response.data;
      final ok =
          response.status >= 200 &&
          response.status < 300 &&
          data is Map &&
          data['accepted'] == true;
      if (ok) {
        return SmsSendResult.accepted(
          status: data['status'] as String? ?? 'queued',
          providerReference: data['reference'] as String?,
        );
      }
      final code = data is Map ? data['error'] as String? : null;
      return SmsSendResult.rejected(
        code ?? 'SMS_REJECTED',
        _messageFor(code) ?? 'The SMS service rejected the receipt.',
      );
    } catch (_) {
      return const SmsSendResult.rejected(
        'SMS_UNREACHABLE',
        'The SMS service could not be reached. Check your internet connection and try again.',
      );
    }
  }

  static String? _messageFor(String? code) => switch (code) {
    'SMS_PROVIDER_NOT_CONFIGURED' =>
      'SMS is not configured yet. Ask an administrator to finish SMS setup.',
    'RECEIPT_ALREADY_SENT' => 'This receipt was already sent by SMS.',
    'DELIVERY_NOT_FOUND' => 'This delivery is not available on the server yet. Wait for it to finish syncing, then try again.',
    'COMPANY_ACCESS_REQUIRED' =>
      'Your account is not allowed to send receipts for this company.',
    'SMS_SENDER_ID_NOT_CONFIGURED' => 'This company has no approved SMS sender ID yet. Ask an administrator to finish SMS setup.',
    'SMS_SENDER_ID_INVALID' => 'The SMS sender ID saved for this company is not valid. Ask an administrator to correct it.',
    'SMS_SENDER_ID_NOT_APPROVED' => 'This company\'s SMS sender ID is not approved in Sailup yet. Ask an administrator to finish sender registration.',
    'SMS_CREDITS_EXHAUSTED' =>
      'SMS credits exhausted. You currently have 0 SMS credits. Please top up '
          'your SMS credits before sending a receipt.',
    'SMS_CREDITS_INSUFFICIENT' =>
      'You do not have enough SMS credits for all the recipients on this list. '
          'No SMS was sent and no credits were used.',
    'SENDER_ID_NOT_ACCEPTABLE' =>
      'The sender ID cannot be chosen manually. It is set by the company administrator.',
    'SMS_PROVIDER_REJECTED_CREDENTIALS' =>
      'SMS is temporarily unavailable. Please contact your administrator.',
    'SMS_PROVIDER_RATE_LIMITED' =>
      'Too many SMS were sent just now. Please wait a moment and try again.',
    'SMS_PROVIDER_UNAVAILABLE' =>
      'The SMS provider is temporarily unavailable. Please try again later.',
    'SMS_PROVIDER_UNREACHABLE' =>
      'No internet connection. The SMS was not sent.',
    _ => null,
  };
}

/// Direct-HTTP transport retained for the existing self-hosted gateway path.
class HttpGatewaySmsTransport implements SmsTransport {
  HttpGatewaySmsTransport({http.Client? client, required this.url})
    : _client = client ?? http.Client();

  final http.Client _client;
  final String url;

  @override
  Future<SmsSendResult> send({
    required String phone,
    required String message,
    required String reference,
  }) async {
    final http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse(url),
            headers: const {'content-type': 'application/json'},
            body: jsonEncode({
              'to': phone,
              'message': message,
              'reference': reference,
            }),
          )
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      return const SmsSendResult.rejected(
        'SMS_UNREACHABLE',
        'The SMS service could not be reached. Check the connection and try again.',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return SmsSendResult.rejected(
        'SMS_REJECTED',
        'The SMS service rejected the receipt (${response.statusCode}).',
      );
    }
    Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      return const SmsSendResult.rejected(
        'SMS_INVALID_RESPONSE',
        'The SMS service returned an invalid response.',
      );
    }
    if (decoded is! Map<String, dynamic> || decoded['accepted'] != true) {
      return const SmsSendResult.rejected(
        'SMS_NOT_CONFIRMED',
        'The SMS provider did not confirm receipt submission.',
      );
    }
    return SmsSendResult.accepted(
      providerReference: decoded['reference'] as String?,
    );
  }
}
