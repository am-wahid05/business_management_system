import 'dart:async';

import 'package:flutter_application_2/features/auth/supabase_auth_link_handler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late StreamController<Uri> links;
  late SupabaseAuthLinkHandler handler;

  setUp(() async {
    links = StreamController<Uri>.broadcast();
    handler = SupabaseAuthLinkHandler(
      incomingLinks: links.stream,
      isAuthCallback: (_) => true,
    );
    await handler.start();
  });

  tearDown(() async {
    await handler.dispose();
    await links.close();
  });

  test('an expired recovery callback is classified without exchanging it', () async {
    handler.expectPasswordRecovery();
    final errorFuture = handler.errors.first;

    links.add(
      Uri.parse(
        'businessms://auth-callback?type=recovery&error_code=otp_expired&'
        'error_description=This+link+has+expired&role=admin&company_id=forged',
      ),
    );

    final error = await errorFuture;
    expect(error.kind, AuthLinkKind.passwordRecovery);
    expect(error.message, contains('invalid, expired'));
    expect(error.message, isNot(contains('admin')));
    expect(error.message, isNot(contains('forged')));
  });

  test('an expired verification callback is classified separately', () async {
    handler.expectEmailVerification();
    final errorFuture = handler.errors.first;

    links.add(
      Uri.parse(
        'businessms://auth-callback?type=signup&error=access_denied&'
        'error_description=The+confirmation+link+is+invalid',
      ),
    );

    final error = await errorFuture;
    expect(error.kind, AuthLinkKind.emailVerification);
    expect(error.message, contains('invalid, expired'));
  });

  test('a valid callback does not create a client-side session', () async {
    final errors = <AuthLinkError>[];
    final subscription = handler.errors.listen(errors.add);
    addTearDown(subscription.cancel);

    links.add(
      Uri.parse('businessms://auth-callback?code=server-exchanged-code'),
    );
    await Future<void>.delayed(Duration.zero);

    expect(errors, isEmpty);
    expect(handler.latestError, isNull);
  });

  test(
    'the same provider failure reported by two auth listeners is shown once',
    () async {
      handler.expectPasswordRecovery();
      final errorFuture = handler.errors.first;

      handler.handleAuthStreamError(StateError('Invalid or expired auth code'));
      handler.handleAuthStreamError(StateError('Invalid or expired auth code'));

      final error = await errorFuture;
      expect(error.kind, AuthLinkKind.passwordRecovery);
      expect(handler.latestError, same(error));
    },
  );

  test('unrelated auth-stream errors are ignored without a callback', () {
    handler.handleAuthStreamError(StateError('Invalid login credentials'));

    expect(handler.latestError, isNull);
  });
}
