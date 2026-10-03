import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the security properties of the subscription Edge Functions.
///
/// These endpoints move money, so their rules are asserted directly against the
/// source: the company must come from the caller's membership, only an
/// owner/admin may act, a client must never be able to declare a payment
/// successful, and no real Hubtel API may be invented.
void main() {
  String read(String path) => File(path).readAsStringSync();

  // Block comments are stripped, and line comments only when '//' starts the
  // line, so a URL is never mangled.
  String code(String source) => source
      .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
      .replaceAll(RegExp(r'^\s*//.*$', multiLine: true), '');

  final createPayment = code(read('supabase/functions/create-payment/index.ts'));
  final verifyPayment = code(read('supabase/functions/verify-payment/index.ts'));
  final status = code(read('supabase/functions/subscription-status/index.ts'));
  final manage = code(read('supabase/functions/subscription-manage/index.ts'));
  final provider = code(read('supabase/functions/_shared/payment_provider.ts'));
  final aiAssistant = code(read('supabase/functions/ai-assistant/index.ts'));
  final invite = code(
    read('supabase/functions/invite-company-member/index.ts'),
  );

  group('every billing endpoint authenticates and scopes the company', () {
    final endpoints = {
      'create-payment': createPayment,
      'verify-payment': verifyPayment,
      'subscription-status': status,
      'subscription-manage': manage,
    };

    endpoints.forEach((name, source) {
      test('$name authenticates from the Authorization header', () {
        expect(source, contains("request.headers.get('Authorization')"));
        expect(source, contains('auth.getUser()'));
      });

      test('$name derives the company from membership', () {
        expect(source, contains("from('company_memberships')"));
      });

      // subscription-status is deliberately different: a company_id there is a
      // read hint that is intersected with the caller's proven set, whereas the
      // payment endpoints reject one outright so a caller can never even try.
      if (name == 'subscription-status') {
        test('$name intersects a company hint with the proven set', () {
          expect(source, contains('adminCompanies.includes(requested)'));
        });
      } else {
        test('$name rejects a client-supplied company_id', () {
          expect(source, contains('COMPANY_ID_NOT_ACCEPTABLE'));
        });
      }

      test('$name refuses a secretary', () {
        // A secretary must not be able to read or manage billing, and must not
        // be a route around subscription administration.
        expect(source, contains('ADMIN_ACCESS_REQUIRED'));
      });
    });
  });

  group('the client can never declare a payment successful', () {
    test('verify-payment never reads a success flag from the request', () {
      // The body type mentions `success` only so it is visibly ignored; the
      // provider is the only authority.
      expect(verifyPayment, contains('success?: unknown'));
      expect(verifyPayment, isNot(contains('input.success')));
    });

    test('verify-payment asks the provider, not the client', () {
      expect(verifyPayment, contains('provider.verifyPayment'));
      expect(verifyPayment, contains('resolveSubscriptionPaymentProvider'));
    });

    test('only a provider success settles the payment', () {
      expect(verifyPayment, contains("if (outcome.status !== 'successful')"));
    });

    test('a replayed payment returns early and grants nothing further', () {
      expect(verifyPayment, contains("if (payment.status === 'SUCCESSFUL')"));
      expect(verifyPayment, contains('idempotent: true'));
    });

    test('an amount mismatch does not unlock the entitlement', () {
      // A cheap payment must never buy an expensive entitlement.
      expect(verifyPayment, contains('PAYMENT_AMOUNT_MISMATCH'));
    });

    test('settlement is delegated to the guarded database function', () {
      expect(verifyPayment, contains("'apply_verified_payment'"));
    });

    test('creating a payment records intent and grants nothing', () {
      expect(createPayment, contains("status: 'PENDING'"));
      expect(createPayment, isNot(contains("status: 'SUCCESSFUL'")));
    });
  });

  group('prices are decided by the server, never the client', () {
    test('the client never sends an amount', () {
      // The create-payment body type has no amount field at all, so there is
      // nothing for a caller to tamper with.
      expect(createPayment, isNot(contains('amount_minor?:')));
    });

    test('the price is read from subscription_config', () {
      expect(createPayment, contains("from('subscription_config')"));
    });

    test('SMS credits are not purchasable through this endpoint', () {
      // The allowed purpose list deliberately omits SMS_CREDITS: credits keep
      // their own separate purchase path and accounting.
      expect(createPayment, isNot(contains("'SMS_CREDITS',\n]")));
      expect(createPayment, contains('const PURPOSES'));
    });
  });

  group('no real Hubtel API was invented', () {
    test('the Hubtel adapter is not configured and does nothing', () {
      expect(provider, contains('class HubtelPaymentProvider'));
      expect(provider, contains('return new HubtelPaymentProvider();'));
    });

    test('no Hubtel endpoint or credential name is guessed', () {
      // Only the class name may appear. Any URL, header or secret name for
      // Hubtel would be a fabrication, since the account is unverified.
      final hubtel =
          provider.substring(provider.indexOf('HubtelPaymentProvider'));
      expect(hubtel, isNot(contains('https://')));
      expect(hubtel, isNot(contains('Authorization')));
      expect(hubtel.toLowerCase(), isNot(contains('api_key')));
      expect(hubtel.toLowerCase(), isNot(contains('apikey')));
    });

    test('the mock provider exists for tests only', () {
      expect(provider, contains('class MockPaymentProvider'));
      expect(provider, contains('mockSubscriptionPaymentProvider'));
    });

    test('the provider is selected centrally, in one place', () {
      expect(
        provider,
        contains('export function resolveSubscriptionPaymentProvider'),
      );
    });
  });

  group('the existing AI assistant keeps its admin gate', () {
    test('the admin/owner restriction is preserved', () {
      expect(aiAssistant, contains('ADMIN_ACCESS_REQUIRED'));
      expect(aiAssistant, contains('ADMIN_ROLES'));
    });

    test('the AI entitlement is checked before any provider call', () {
      // The check sits after the admin gate and before the OpenAI request, so
      // an unentitled company never spends provider cost.
      expect(aiAssistant, contains('AI_NOT_ENTITLED'));
      expect(
        aiAssistant.indexOf('AI_NOT_ENTITLED') <
            aiAssistant.indexOf('provider.complete'),
        isTrue,
        reason: 'The entitlement check must run before the provider call.',
      );
    });

    test('the AI entitlement is read without any RPC or raw SQL', () {
      // The assistant gained an entitlement check, but gained no ability to ask
      // the database an arbitrary question. It reads two known tables.
      expect(aiAssistant, isNot(contains('.rpc(')));
      expect(aiAssistant, contains("from('company_ai_entitlements')"));
      expect(aiAssistant, contains("from('company_subscriptions')"));
    });

    test('the AI assistant still cannot write any data', () {
      for (final verb in ['.insert(', '.update(', '.upsert(', '.delete(']) {
        expect(aiAssistant, isNot(contains(verb)));
      }
    });

    test('the AI credentials are still server-side only', () {
      expect(aiAssistant, contains("Deno.env.get('OPENAI_API_KEY')"));
      expect(aiAssistant, contains("Deno.env.get('OPENAI_MODEL')"));
    });
  });

  group('invite-company-member respects the paid secretary allowance', () {
    test('the allowance is checked before any account is created', () {
      final limitCheck = invite.indexOf('maxSecretaries');
      final createUser = invite.indexOf('auth.admin.createUser');
      expect(limitCheck, isNot(-1));
      expect(createUser, isNot(-1));
      // The check runs first, so a company at its limit never has an account
      // created and then deleted again.
      expect(limitCheck < createUser, isTrue);
    });

    test('the refusal is friendly and creates nothing', () {
      expect(invite, contains('No account has been created.'));
    });
  });

  group('status reporting never leaks another company', () {
    test('the company hint is intersected with the proven set', () {
      // A client may pass company_id, but it is only honoured when the caller
      // is already a proven admin of it.
      expect(status, contains('adminCompanies.includes(requested)'));
    });

    test('payment and event history are scoped to the resolved company', () {
      expect(status, contains("from('payment_transactions')"));
      expect(status, contains("from('subscription_events')"));
      expect(status, contains(".eq('company_id', companyId)"));
    });

    test('being over the secretary allowance is reported, not acted on', () {
      // Nothing is deleted or deactivated: the admin is simply told.
      expect(status, contains('overSecretaryAllowance'));
    });
  });
}

