import 'dart:convert';

import 'package:flutter_application_2/features/auth/account_service.dart';
import 'package:flutter_application_2/features/auth/supabase_auth_link_handler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('forgot-password sends the configured recovery redirect', () async {
    final requests = <http.Request>[];
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-publishable-key',
      authOptions: const AuthClientOptions(authFlowType: AuthFlowType.implicit),
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response('{}', 200);
      }),
    );
    final handler = SupabaseAuthLinkHandler();
    final service = SupabaseAccountService(client, authLinkHandler: handler);

    await service.sendPasswordResetEmail('user@example.com');

    expect(requests, hasLength(1));
    expect(requests.single.url.path, '/auth/v1/recover');
    expect(
      requests.single.url.queryParameters['redirect_to'],
      'businessms://auth-callback',
    );
    final body = jsonDecode(requests.single.body) as Map<String, dynamic>;
    expect(body['email'], 'user@example.com');
    expect(body, isNot(contains('redirect_to')));
    expect(body, isNot(contains('role')));
    expect(body, isNot(contains('company_id')));

    await service.dispose();
    await client.dispose();
    await handler.dispose();
  });

  test(
    'signup with confirmation required reports a null-session outcome',
    () async {
      final requests = <http.Request>[];
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-publishable-key',
        authOptions: const AuthClientOptions(
          authFlowType: AuthFlowType.implicit,
        ),
        httpClient: MockClient((request) async {
          requests.add(request);
          return http.Response('{}', 200);
        }),
      );
      final handler = SupabaseAuthLinkHandler();
      final service = SupabaseSignUpService(client, authLinkHandler: handler);

      final outcome = await service.register(
        email: 'new@example.com',
        password: 'Password1',
        displayName: 'New User',
        companyName: 'New Company',
      );

      expect(outcome, SignUpOutcome.needsEmailConfirmation);
      expect(requests, hasLength(1));
      expect(
        requests.single.url.queryParameters['redirect_to'],
        'businessms://auth-callback',
      );
      final body = jsonDecode(requests.single.body) as Map<String, dynamic>;
      final metadata = body['data'] as Map<String, dynamic>;
      expect(body, isNot(contains('redirect_to')));
      expect(metadata['display_name'], 'New User');
      expect(metadata['company_name'], 'New Company');
      expect(metadata, isNot(contains('role')));
      expect(metadata, isNot(contains('company_id')));

      await client.dispose();
      await handler.dispose();
    },
  );
}
