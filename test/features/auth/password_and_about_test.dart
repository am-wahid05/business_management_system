import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_2/app/app_info.dart';
import 'package:flutter_application_2/app/app_responsive.dart';
import 'package:flutter_application_2/features/about/about_screen.dart';
import 'package:flutter_application_2/features/auth/account_service.dart';
import 'package:flutter_application_2/features/auth/change_password_screen.dart';
import 'package:flutter_application_2/features/auth/forgot_password_screen.dart';
import 'package:flutter_application_2/features/auth/password_policy.dart';
import 'package:flutter_application_2/features/auth/reset_password_screen.dart';

/// A recording stand-in for the identity provider.
///
/// Nothing here reaches a network, so these tests exercise the real screens and
/// the real validation rules without contacting Supabase. Note what the fake
/// does NOT do: it keeps no password storage at all, which mirrors the real
/// service and keeps the test honest about the "no local password storage" rule.
class FakeAccountService implements AccountService {
  FakeAccountService({this.email = 'user@example.com'});

  final String? email;
  final List<String> changedPasswords = <String>[];
  final List<String> resetEmails = <String>[];
  int cancelCount = 0;

  /// Set to make the next call fail, so error handling can be exercised.
  AccountException? nextError;

  bool _recovering = false;

  @override
  bool get isAvailable => true;

  @override
  String? get currentEmail => email;

  @override
  bool get isRecovering => _recovering;

  @override
  Stream<bool> get recoveryEvents => const Stream<bool>.empty();

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final error = nextError;
    if (error != null) {
      nextError = null;
      throw error;
    }
    changedPasswords.add(newPassword);
  }

  @override
  Future<void> sendPasswordResetEmail(String address) async {
    final error = nextError;
    if (error != null) {
      nextError = null;
      throw error;
    }
    resetEmails.add(address);
  }

  @override
  Future<void> resetPassword(String newPassword) async {
    final error = nextError;
    if (error != null) {
      nextError = null;
      throw error;
    }
    changedPasswords.add(newPassword);
    _recovering = false;
  }

  @override
  Future<void> cancelRecovery() async {
    cancelCount++;
    _recovering = false;
  }

  /// Puts the fake into the state a recovery link would create.
  void beginRecovery() => _recovering = true;
}

/// Wraps a screen in the minimum Material scaffolding a route would provide.
///
/// The screen is used directly as the app's `home` rather than being nested in
/// another Scaffold. Each password screen already returns its own Scaffold, and
/// wrapping it in a second one would give it a bounded body inside a bounded
/// body, which breaks the layout rather than testing it.
Widget harness(Widget child) => MaterialApp(home: child);

/// Hosts a screen as a route pushed over a stub page.
///
/// [ChangePasswordScreen] calls `pop` on success, and a success message is shown
/// through a SnackBar. As the root route there is nothing to pop back to, so the
/// pop is meaningless and the Scaffold hosting the message goes away with it.
/// Pushing the screen over a stub page reproduces the real navigation, which
/// gives the pop somewhere to go and keeps a Scaffold alive to host the message.
class PushedHarness extends StatelessWidget {
  const PushedHarness({required this.screen, super.key});

  final Widget screen;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => screen),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
  }
}

/// Opens the pushed screen and settles, so a test starts on the screen itself.
Future<void> openPushedScreen(WidgetTester tester) async {
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  group('password rules', () {
    test('accepts a strong password', () {
      expect(PasswordPolicy.isValid('Password1'), isTrue);
      expect(PasswordPolicy.isValid('StrongPass9'), isTrue);
    });

    test('rejects a password with no uppercase letter', () {
      expect(
        PasswordPolicy.validate('password1'),
        'Password must contain at least one uppercase letter.',
      );
    });

    test('rejects a password with no lowercase letter', () {
      expect(
        PasswordPolicy.validate('PASSWORD1'),
        'Password must contain at least one lowercase letter.',
      );
    });

    test('rejects a password with no number', () {
      expect(
        PasswordPolicy.validate('Password'),
        'Password must contain at least one number.',
      );
    });

    test('rejects a password under 8 characters', () {
      expect(
        PasswordPolicy.validate('Pass1'),
        'Password must be at least 8 characters.',
      );
    });

    test('rejects an empty password', () {
      expect(PasswordPolicy.isValid(''), isFalse);
      expect(PasswordPolicy.isValid(null), isFalse);
    });

    test('reports length before character-class problems', () {
      // 'Pass1' is also missing an uppercase letter, but the length problem is
      // the one worth reporting first.
      expect(
        PasswordPolicy.validate('Pass1'),
        'Password must be at least 8 characters.',
      );
    });

    test('reports a mismatched confirmation', () {
      expect(
        PasswordPolicy.validateMatch('Password1', 'Password2'),
        'Passwords do not match.',
      );
    });

    test('accepts a matching confirmation', () {
      expect(PasswordPolicy.validateMatch('Password1', 'Password1'), isNull);
    });
  });
  group('Change Password', () {
    testWidgets('rejects a weak new password and shows why', (tester) async {
      final service = FakeAccountService();
      await tester.pumpWidget(
        harness(ChangePasswordScreen(accountService: service)),
      );

      await tester.enterText(find.byType(TextField).at(0), 'OldPass1');
      await tester.enterText(find.byType(TextField).at(1), 'weak');
      await tester.enterText(find.byType(TextField).at(2), 'weak');
      await tester.tap(find.text('Update password'));
      await tester.pumpAndSettle();

      expect(
        find.text('Password must be at least 8 characters.'),
        findsOneWidget,
      );
      // Nothing was sent, so a weak password never reaches the provider.
      expect(service.changedPasswords, isEmpty);
    });

    testWidgets('rejects a mismatched confirmation', (tester) async {
      final service = FakeAccountService();
      await tester.pumpWidget(
        harness(ChangePasswordScreen(accountService: service)),
      );

      await tester.enterText(find.byType(TextField).at(0), 'OldPass1');
      await tester.enterText(find.byType(TextField).at(1), 'Password1');
      await tester.enterText(find.byType(TextField).at(2), 'Password2');
      await tester.tap(find.text('Update password'));
      await tester.pumpAndSettle();

      expect(find.text('Passwords do not match.'), findsOneWidget);
      expect(service.changedPasswords, isEmpty);
    });

    testWidgets('submits a valid change and confirms success', (tester) async {
      final service = FakeAccountService();
      await tester.pumpWidget(
        PushedHarness(
          screen: ChangePasswordScreen(accountService: service),
        ),
      );
      await openPushedScreen(tester);

      await tester.enterText(find.byType(TextField).at(0), 'OldPass1');
      await tester.enterText(find.byType(TextField).at(1), 'Password1');
      await tester.enterText(find.byType(TextField).at(2), 'Password1');
      await tester.tap(find.text('Update password'));
      await tester.pumpAndSettle();

      expect(service.changedPasswords, ['Password1']);
      // The success message is confirmed to the user before returning.
      expect(find.text('Password changed successfully.'), findsOneWidget);
    });

    testWidgets('requires the current password', (tester) async {
      final service = FakeAccountService();
      await tester.pumpWidget(
        harness(ChangePasswordScreen(accountService: service)),
      );

      await tester.enterText(find.byType(TextField).at(1), 'Password1');
      await tester.enterText(find.byType(TextField).at(2), 'Password1');
      await tester.tap(find.text('Update password'));
      await tester.pumpAndSettle();

      expect(find.text('Enter your current password.'), findsOneWidget);
      expect(service.changedPasswords, isEmpty);
    });

    testWidgets('shows a friendly message when the provider refuses', (
      tester,
    ) async {
      final service = FakeAccountService()
        ..nextError = const AccountException(
          'Your current password is not correct.',
        );
      await tester.pumpWidget(
        harness(ChangePasswordScreen(accountService: service)),
      );

      await tester.enterText(find.byType(TextField).at(0), 'OldPass1');
      await tester.enterText(find.byType(TextField).at(1), 'Password1');
      await tester.enterText(find.byType(TextField).at(2), 'Password1');
      await tester.tap(find.text('Update password'));
      await tester.pumpAndSettle();

      expect(
        find.text('Your current password is not correct.'),
        findsOneWidget,
      );
      // The technical detail is not shown to the user.
      expect(find.textContaining('AuthException'), findsNothing);
    });

    testWidgets('obscures every password field until revealed', (tester) async {
      await tester.pumpWidget(
        harness(ChangePasswordScreen(accountService: FakeAccountService())),
      );

      for (final field in tester.widgetList<TextField>(find.byType(TextField))) {
        expect(field.obscureText, isTrue);
      }

      await tester.tap(find.byIcon(Icons.visibility_outlined).first);
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);
    });
  });

  group('Forgot Password', () {
    testWidgets('rejects an invalid email before sending anything', (
      tester,
    ) async {
      final service = FakeAccountService();
      await tester.pumpWidget(
        harness(ForgotPasswordScreen(accountService: service)),
      );

      await tester.enterText(find.byType(TextFormField), 'not-an-email');
      await tester.tap(find.text('Send Reset Link'));
      await tester.pumpAndSettle();

      expect(find.text('Enter a valid email address.'), findsOneWidget);
      expect(service.resetEmails, isEmpty);
    });

    testWidgets('requires an email to be entered', (tester) async {
      final service = FakeAccountService();
      await tester.pumpWidget(
        harness(ForgotPasswordScreen(accountService: service)),
      );

      await tester.tap(find.text('Send Reset Link'));
      await tester.pumpAndSettle();

      expect(find.text('Enter your email address.'), findsOneWidget);
      expect(service.resetEmails, isEmpty);
    });

    testWidgets('sends the link and confirms generically', (tester) async {
      final service = FakeAccountService();
      await tester.pumpWidget(
        harness(ForgotPasswordScreen(accountService: service)),
      );

      await tester.enterText(find.byType(TextFormField), 'user@example.com');
      await tester.tap(find.text('Send Reset Link'));
      await tester.pumpAndSettle();

      expect(service.resetEmails, ['user@example.com']);
      expect(find.text(passwordResetSentMessage), findsOneWidget);
    });

    testWidgets('never reveals whether an email is registered', (tester) async {
      // Even when the provider reports a failure, the screen must not say the
      // address is unknown, because that would turn this screen into a way to
      // test which accounts exist.
      final service = FakeAccountService()
        ..nextError = const AccountException(
          'We could not send the reset link. Please try again in a moment.',
        );
      await tester.pumpWidget(
        harness(ForgotPasswordScreen(accountService: service)),
      );

      await tester.enterText(find.byType(TextFormField), 'nobody@example.com');
      await tester.tap(find.text('Send Reset Link'));
      await tester.pumpAndSettle();

      expect(find.textContaining('does not exist'), findsNothing);
      expect(find.textContaining('no account'), findsNothing);
      expect(find.textContaining('not registered'), findsNothing);
    });

    testWidgets('offers a way back to login', (tester) async {
      await tester.pumpWidget(
        harness(ForgotPasswordScreen(accountService: FakeAccountService())),
      );
      expect(find.text('Back to Login'), findsOneWidget);
    });
  });
  group('Reset Password', () {
    testWidgets('enforces the same rules as Change Password', (tester) async {
      final service = FakeAccountService()..beginRecovery();
      await tester.pumpWidget(
        harness(ResetPasswordScreen(accountService: service)),
      );

      await tester.enterText(find.byType(TextField).at(0), 'Password');
      await tester.enterText(find.byType(TextField).at(1), 'Password');
      await tester.tap(find.text('Change Password'));
      await tester.pumpAndSettle();
      expect(
        find.text('Password must contain at least one number.'),
        findsOneWidget,
      );

      await tester.enterText(find.byType(TextField).at(0), 'Pass1');
      await tester.enterText(find.byType(TextField).at(1), 'Pass1');
      await tester.tap(find.text('Change Password'));
      await tester.pumpAndSettle();
      expect(
        find.text('Password must be at least 8 characters.'),
        findsOneWidget,
      );

      await tester.enterText(find.byType(TextField).at(0), 'Password1');
      await tester.enterText(find.byType(TextField).at(1), 'Password2');
      await tester.tap(find.text('Change Password'));
      await tester.pumpAndSettle();
      expect(find.text('Passwords do not match.'), findsOneWidget);

      expect(service.changedPasswords, isEmpty);
    });

    testWidgets('applies a valid new password and confirms', (tester) async {
      final service = FakeAccountService()..beginRecovery();
      await tester.pumpWidget(
        harness(ResetPasswordScreen(accountService: service)),
      );

      await tester.enterText(find.byType(TextField).at(0), 'NewPass9');
      await tester.enterText(find.byType(TextField).at(1), 'NewPass9');
      await tester.tap(find.text('Change Password'));
      await tester.pumpAndSettle();

      expect(service.changedPasswords, ['NewPass9']);
      expect(
        find.text('Your password has been changed successfully.'),
        findsOneWidget,
      );
      expect(find.text('Back to Login'), findsOneWidget);
    });

    testWidgets('does not reach a dashboard before the reset is done', (
      tester,
    ) async {
      // The reset screen is what a recovery session must land on. It offers no
      // way into the app, so the reset cannot be skipped.
      final service = FakeAccountService()..beginRecovery();
      await tester.pumpWidget(
        harness(ResetPasswordScreen(accountService: service)),
      );

      expect(find.text('Choose a New Password'), findsOneWidget);
      expect(find.textContaining('Dashboard'), findsNothing);
    });
  });

  group('password access does not depend on the role', () {
    testWidgets('admin and secretary reach the identical screen', (
      tester,
    ) async {
      // There is no role parameter on the screen at all: both roles use the
      // same widget, and the provider enforces the real authorization.
      await tester.pumpWidget(
        harness(ChangePasswordScreen(accountService: FakeAccountService())),
      );
      expect(find.text('Current password'), findsOneWidget);
      expect(find.text('New password'), findsOneWidget);
      expect(find.text('Confirm new password'), findsOneWidget);
    });

    test('the screen carries no role or permission gate', () {
      // Guards against someone later gating this screen behind AppPermission or
      // a subscription, which would lock a secretary out of their own account.
      final source = File(
        'lib/features/auth/change_password_screen.dart',
      ).readAsStringSync();
      expect(source, isNot(contains('AppPermission')));
      expect(source, isNot(contains('UserRole')));
      expect(source, isNot(contains('subscriptionGated')));
    });
  });
  group('About page describes the software', () {
    testWidgets('shows the product name, version and developer', (tester) async {
      await tester.pumpWidget(harness(const AboutScreen()));

      expect(find.text('Business Management System'), findsOneWidget);
      expect(find.text('Version 1.0.0'), findsOneWidget);
      expect(find.text('Developed by Abdul Wahid'), findsOneWidget);
    });

    testWidgets('labels Website without showing a URL', (tester) async {
      await tester.pumpWidget(harness(const AboutScreen()));

      // The label is present...
      expect(find.text('Website'), findsOneWidget);
      // ...but no address is displayed and no placeholder is invented.
      expect(find.textContaining('http'), findsNothing);
      expect(find.textContaining('www.'), findsNothing);
      expect(find.textContaining('coming soon'), findsNothing);
      expect(AppInfo.websiteUrl, isNull);
    });

    testWidgets('never renders the WhatsApp number as visible text', (
      tester,
    ) async {
      await tester.pumpWidget(harness(const AboutScreen()));

      // The row is labelled, and that is all the user ever sees.
      expect(find.text('WhatsApp'), findsOneWidget);

      // The number must appear nowhere in the rendered interface: not the local
      // form, not the +233 form, and not in fragments.
      expect(find.textContaining('0530466346'), findsNothing);
      expect(find.textContaining('233530466346'), findsNothing);
      expect(find.textContaining('+233'), findsNothing);

      // It is used internally to build the link.
      expect(AppInfo.whatsappUri.host, 'wa.me');
      expect(AppInfo.whatsappUri.path, '/233530466346');
    });

    test('the WhatsApp destination uses the Ghana international format', () {
      // Ghana is +233 and the local number's leading 0 is dropped.
      expect(AppInfo.whatsappUri.toString(), 'https://wa.me/233530466346');
    });

    test('the About page reads no company data', () {
      // The page must be a function of AppInfo alone. If a company name, logo
      // or contact field ever appears here, one tenant's details could be shown
      // to another tenant's user.
      final source = File(
        'lib/features/about/about_screen.dart',
      ).readAsStringSync();
      expect(source, isNot(contains('activeCompanyContext')));
      expect(source, isNot(contains('CompanyMembership')));
      expect(source, isNot(contains('brandingService')));
      expect(source, isNot(contains('CompanyBrandMark')));
      expect(source, isNot(contains('supabaseClient')));
      expect(source, isNot(contains('.from(')));
    });

    test('the software mark is not the company logo', () {
      final source = File(
        'lib/features/about/about_screen.dart',
      ).readAsStringSync();
      expect(source, contains('Icons.business_center_outlined'));
    });
  });

  group('responsive breakpoints', () {
    test('bands follow the available width, not the device', () {
      // The expectations are derived from the breakpoint constants rather than
      // restating the numbers, so changing a breakpoint cannot leave this test
      // asserting a stale value.
      expect(AppWindowSize.of(0), AppWindowSize.compact);
      expect(
        AppWindowSize.of(AppBreakpoints.compact - 1),
        AppWindowSize.compact,
      );
      expect(
        AppWindowSize.of(AppBreakpoints.compact),
        AppWindowSize.compact,
      );
      expect(
        AppWindowSize.of(AppBreakpoints.medium),
        AppWindowSize.medium,
      );
      expect(
        AppWindowSize.of(AppBreakpoints.medium - 1),
        AppWindowSize.compact,
      );
      expect(
        AppWindowSize.of(AppBreakpoints.expanded),
        AppWindowSize.expanded,
      );
      expect(
        AppWindowSize.of(AppBreakpoints.expanded - 1),
        AppWindowSize.medium,
      );
      // A real phone and a real large monitor.
      expect(AppWindowSize.of(360), AppWindowSize.compact);
      expect(AppWindowSize.of(2560), AppWindowSize.expanded);
    });

    test('a narrow window is treated exactly like a phone', () {
      // This is what makes a resized Windows window behave like the mobile
      // layout instead of forcing a desktop grid into 500px.
      expect(AppWindowSize.of(500), AppWindowSize.of(360));
      expect(AppWindowSize.of(500).hasSideNavigation, isFalse);
    });

    test('only a band that fits offers side navigation', () {
      expect(AppWindowSize.compact.hasSideNavigation, isFalse);
      expect(AppWindowSize.medium.hasSideNavigation, isTrue);
      expect(AppWindowSize.expanded.hasSideNavigation, isTrue);
    });

    testWidgets('the password form fits a small phone', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        harness(ChangePasswordScreen(accountService: FakeAccountService())),
      );
      // No exception means no RenderFlex overflow and no clipped content.
      expect(tester.takeException(), isNull);
      expect(find.text('Change Password'), findsOneWidget);
    });

    testWidgets('the password form fits a narrow desktop window', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(500, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        harness(ChangePasswordScreen(accountService: FakeAccountService())),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the About page fits a small phone', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(harness(const AboutScreen()));
      expect(tester.takeException(), isNull);
      expect(find.text('WhatsApp'), findsOneWidget);
    });

    testWidgets('the About page fits a large monitor', (tester) async {
      tester.view.physicalSize = const Size(2560, 1440);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(harness(const AboutScreen()));
      expect(tester.takeException(), isNull);
    });
  });
}
