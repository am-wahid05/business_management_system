import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_2/app/password_recovery_gate.dart';
import 'package:flutter_application_2/features/auth/account_service.dart';

/// A stand-in whose recovery state is driven by the test, not by a network call.
///
/// It models the real service's most important property: a recovery session
/// outlives the widgets that observe it, so a late listener is told about the
/// session that is already in progress.
class FakeRecoveryAccountService implements AccountService {
  FakeRecoveryAccountService({this.recovering = false}) {
    // Replay the current value to whoever listens, mirroring the real service.
    _controller.add(recovering);
  }

  bool recovering;
  final StreamController<bool> _controller = StreamController<bool>.broadcast();

  @override
  bool get isAvailable => true;

  @override
  String? get currentEmail => 'user@example.com';

  @override
  bool get isRecovering => recovering;

  @override
  Stream<bool> get recoveryEvents async* {
    yield recovering;
    yield* _controller.stream;
  }

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {}

  @override
  Future<void> sendPasswordResetEmail(String email) async {}

  @override
  Future<void> resetPassword(String newPassword) async {
    recovering = false;
  }

  @override
  Future<void> cancelRecovery() async {
    recovering = false;
  }

  /// Simulates the PKCE exchange completing and Supabase signalling recovery.
  void emitRecovery() {
    recovering = true;
    _controller.add(true);
  }

  Future<void> close() => _controller.close();
}

Widget gateHarness(AccountService? account) => MaterialApp(
  builder: (context, child) =>
      PasswordRecoveryGate(accountService: account, child: child),
  home: const Text('sign in'),
);

void main() {
  testWidgets('a warm-start recovery link replaces the app content', (
    tester,
  ) async {
    final account = FakeRecoveryAccountService();
    addTearDown(account.close);

    await tester.pumpWidget(gateHarness(account));
    expect(find.text('sign in'), findsOneWidget);

    // The app is already running and the link arrives through the stream.
    account.emitRecovery();
    await tester.pumpAndSettle();

    expect(find.text('Choose a New Password'), findsOneWidget);
    // The underlying screen is gone, not merely covered.
    expect(find.text('sign in'), findsNothing);
  });

  testWidgets('a cold-start recovery link is not lost', (tester) async {
    // The exchange finished before any widget existed, which is what happens
    // when the phone opens the app from scratch.
    final account = FakeRecoveryAccountService(recovering: true);
    addTearDown(account.close);

    await tester.pumpWidget(gateHarness(account));

    expect(find.text('Choose a New Password'), findsOneWidget);
    expect(find.text('sign in'), findsNothing);
  });

  // The recovery session publishes a user, which changes the MaterialApp key and
  // rebuilds this subtree. The reset screen must survive that.
  testWidgets('the reset screen survives a rebuild of the gate', (
    tester,
  ) async {
    final account = FakeRecoveryAccountService();
    addTearDown(account.close);

    await tester.pumpWidget(gateHarness(account));
    account.emitRecovery();
    await tester.pumpAndSettle();
    expect(find.text('Choose a New Password'), findsOneWidget);

    // Rebuild under a different MaterialApp key, as a session change does.
    await tester.pumpWidget(
      MaterialApp(
        key: const ValueKey('signed-in:company-1'),
        builder: (context, child) =>
            PasswordRecoveryGate(accountService: account, child: child),
        home: const Text('dashboard'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Choose a New Password'), findsOneWidget);
    expect(find.text('dashboard'), findsNothing);
  });

  testWidgets('a normal session is never blocked by the gate', (tester) async {
    final account = FakeRecoveryAccountService();
    addTearDown(account.close);

    await tester.pumpWidget(gateHarness(account));
    await tester.pumpAndSettle();

    expect(find.text('sign in'), findsOneWidget);
    expect(find.text('Choose a New Password'), findsNothing);
  });

  testWidgets('the local-only setup renders the app unchanged', (tester) async {
    await tester.pumpWidget(gateHarness(null));

    expect(find.text('sign in'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
