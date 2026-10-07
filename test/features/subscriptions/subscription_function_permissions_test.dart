import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final migration = File(
    'supabase/migrations/202610070001_subscription_function_execute_privileges.sql',
  ).readAsStringSync();
  final sql = migration
      .replaceAll(RegExp(r'--.*'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'\s*\(\s*'), '(')
      .replaceAll(RegExp(r'\s*\)'), ')');

  const signatures = {
    'public.company_entitlements(uuid)',
    'public.record_subscription_event(uuid, text, public.subscription_status, public.subscription_status, text, uuid, jsonb)',
    'public.start_company_trials(uuid)',
    'public.sweep_expired_subscriptions()',
  };

  group('subscription SECURITY DEFINER execute privileges', () {
    test('all four exact signatures revoke client and PUBLIC execution', () {
      final revokes = sql
          .split(';')
          .map((statement) => statement.trim())
          .where(
            (statement) => statement.startsWith('revoke execute on function'),
          )
          .toSet();

      expect(
        revokes,
        signatures
            .map(
              (signature) =>
                  'revoke execute on function $signature from public, anon, authenticated',
            )
            .toSet(),
      );
    });

    test('only Edge Function routines are granted to service_role', () {
      final grants = sql
          .split(';')
          .map((statement) => statement.trim())
          .where(
            (statement) => statement.startsWith('grant execute on function'),
          )
          .toSet();

      expect(grants, {
        'grant execute on function public.company_entitlements(uuid) to service_role',
        'grant execute on function public.sweep_expired_subscriptions() to service_role',
      });
    });

    test(
      'Edge Functions call the granted routines with service-role clients',
      () {
        final subscriptionStatus = File(
          'supabase/functions/subscription-status/index.ts',
        ).readAsStringSync();
        final verifyPayment = File('supabase/functions/verify-payment/index.ts')
            .readAsStringSync();
        final inviteMember = File(
          'supabase/functions/invite-company-member/index.ts',
        ).readAsStringSync();

        expect(subscriptionStatus, contains('createClient(url, serviceKey'));
        expect(
          subscriptionStatus,
          contains("admin.rpc('sweep_expired_subscriptions')"),
        );
        expect(subscriptionStatus, contains("'company_entitlements'"));
        expect(verifyPayment, contains('createClient(url, serviceKey'));
        expect(verifyPayment, contains("'company_entitlements'"));
        expect(inviteMember, contains('createClient(url, serviceKey'));
        expect(
          inviteMember,
          contains("adminClient.rpc('company_entitlements'"),
        );
      },
    );
  });
}
