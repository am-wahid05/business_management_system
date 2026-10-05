import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/supabase_config.dart';
import '../receiving/print_settings_service.dart';
import 'supabase_auth_link_handler.dart';

/// Outcome of a remote sign-up attempt.
///
/// The two cases are genuinely different for the user: one can continue
/// straight into the app, the other has to go and confirm an email address
/// first. They are modelled separately so the screen cannot report success
/// before the account is actually usable.
enum SignUpOutcome {
  /// Signed in immediately (email confirmation disabled). The company already
  /// exists, so the user can be taken straight to their dashboard.
  readyToContinue,

  /// The account was created but the address must be confirmed first.
  needsEmailConfirmation,
}

/// A failure during remote sign-up that is safe to show the user.
class SignUpException implements Exception {
  const SignUpException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Registers the very first owner of a brand-new company.
///
/// This deliberately contains no company, membership or role logic. The whole
/// provisioning chain already exists on the server: `handle_new_user()` reacts
/// to the `auth.users` insert and creates the profile, the company, the owner
/// membership and the default products. The only thing this class decides is
/// what to put in the signup metadata, and in particular whether the user is
/// signing up to create a company at all.
///
/// Because the role is assigned by the trigger, there is deliberately no
/// admin/secretary selector here. The first registered user of a new company
/// always becomes its owner, so offering a choice would be offering a choice
/// the architecture does not honour.
class SupabaseSignUpService {
  const SupabaseSignUpService(this.client, {this.authLinkHandler});

  final SupabaseClient client;
  final SupabaseAuthLinkHandler? authLinkHandler;

  /// Creates the account and, through the existing server trigger, its company.
  ///
  /// [displayName] and [companyName] are passed as raw user metadata, which is
  /// exactly what `handle_new_user()` reads. When [companyName] is omitted the
  /// user is registered as an account with no company, which is the correct
  /// path for a secretary who will be invited into an existing company later.
  Future<SignUpOutcome> register({
    required String email,
    required String password,
    String? displayName,
    String? companyName,
  }) async {
    final address = email.trim();
    final name = displayName?.trim();
    final company = companyName?.trim();
    final metadata = <String, String>{
      if (name != null && name.isNotEmpty) 'display_name': name,
      // Only a genuinely new company is requested. An empty box is treated as
      // "I am joining an existing company" rather than creating a blank one,
      // because the trigger provisions a company for every non-empty value.
      if (company != null && company.isNotEmpty) 'company_name': company,
    };
    authLinkHandler?.expectEmailVerification();
    try {
      final response = await client.auth.signUp(
        email: address,
        password: password,
        data: metadata,
        // Reuses the existing deep-link architecture, exactly as the password
        // recovery link already does.
        emailRedirectTo: SupabaseConfig.emailRedirectTo,
      );
      // A null session with no error means the project requires the user to
      // confirm the address first. That is a success, not a failure.
      if (response.session == null) return SignUpOutcome.needsEmailConfirmation;
      authLinkHandler?.clearExpectedFlow();
      return SignUpOutcome.readyToContinue;
    } on AuthException catch (error) {
      authLinkHandler?.clearExpectedFlow();
      throw SignUpException(_friendlyMessage(error));
    } catch (_) {
      authLinkHandler?.clearExpectedFlow();
      throw const SignUpException(
        'We could not create your account. Check your connection and try again.',
      );
    }
  }

  /// Turns a Supabase signup failure into a message that is useful but reveals
  /// nothing about accounts other than the one being created.
  String _friendlyMessage(AuthException error) {
    final status = error.statusCode;
    final raw = error.message.toLowerCase();
    bool hasStatus(int code) => status == '$code';

    if (hasStatus(429) ||
        raw.contains('too many attempts') ||
        raw.contains('too many requests') ||
        raw.contains('rate limit')) {
      return 'Too many signup attempts. Please wait a few minutes and try again.';
    }

    // Supabase returns this for an address that is already registered. It is
    // the only account-existence detail exposed, and it is unavoidable: it is
    // about the address the user just typed, not a way to enumerate accounts.
    if (hasStatus(422) || hasStatus(400)) {
      if (raw.contains('already') || raw.contains('registered')) {
        return 'An account already exists for this email address. '
            'Try signing in, or reset your password.';
      }
      if (raw.contains('password')) {
        return 'That password was not accepted. Choose a different one that '
            'meets the password rules.';
      }
      return 'That email address or password was not accepted. Please check and '
          'try again.';
    }
    if (_looksOffline(error)) {
      return 'No internet connection. Your account was not created.';
    }
    return 'We could not create your account. Please try again.';
  }

  /// Whether a failure looks like a connectivity problem, not a rejection.
  bool _looksOffline(AuthException error) {
    final raw = error.message.toLowerCase();
    return raw.contains('socket') ||
        raw.contains('connection') ||
        raw.contains('failed to fetch');
  }
}

/// The password operations the app needs from its identity provider.
///
/// This sits behind an interface for two reasons. It keeps every screen and test
/// independent of Supabase, and it makes the security boundary explicit: a
/// password only ever travels to the identity provider, through these calls. No
/// password is written to SQLite, SharedPreferences, a log, or analytics, and no
/// password is ever sent to an Edge Function of this project.
abstract interface class AccountService {
  /// Whether password features are available at all.
  ///
  /// False in the local-only setup, where there is no Supabase project. The UI
  /// hides the password actions rather than offering something that cannot work.
  bool get isAvailable;

  /// The signed-in account's email, or null when unknown.
  String? get currentEmail;

  /// Re-checks the current password, then sets a new one.
  ///
  /// [currentPassword] is verified by signing in again before the update, which
  /// is the reauthentication Supabase expects for a credential change. It is
  /// passed to Supabase Auth and nowhere else.
  ///
  /// Throws [AccountException] with a user-safe message on failure.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  });

  /// Emails a password reset link to [email].
  ///
  /// The implementation must not reveal whether the address exists. Callers show
  /// the same confirmation either way, so a stranger cannot use this screen to
  /// discover which emails are registered.
  Future<void> sendPasswordResetEmail(String email);

  /// Sets a new password using the recovery session from a reset link.
  Future<void> resetPassword(String newPassword);

  /// Emits true when a password-recovery link has just been opened.
  ///
  /// This is what routes a user to the reset screen. It is deliberately
  /// separate from the ordinary signed-in session so a recovery event can never
  /// be mistaken for a normal sign-in and drop the user straight into a
  /// dashboard.
  Stream<bool> get recoveryEvents;

  /// Whether a recovery session is currently active.
  bool get isRecovering;

  /// Ends a recovery session without changing the password.
  Future<void> cancelRecovery();
}

/// A failure from an identity-provider password operation.
class AccountException implements Exception {
  const AccountException(this.message);

  /// A message that is safe and useful to show a user.
  final String message;

  @override
  String toString() => message;
}

/// The Supabase Auth implementation of [AccountService].
class SupabaseAccountService implements AccountService {
  SupabaseAccountService(this.client, {this.authLinkHandler}) {
    // The recovery flag is owned here rather than by the gate widget, because a
    // recovery link can be exchanged before any widget is listening (cold start),
    // and because MaterialApp is rebuilt with a new key once the recovery session
    // resolves to a user. A flag held in widget state would be lost in both cases.
    _authSubscription = client.auth.onAuthStateChange.listen(
      _onAuthStateChange,
      onError: _onAuthStreamError,
    );
    if (authLinkHandler?.takePendingPasswordRecovery() == true) {
      _recovering = true;
    }
  }

  final SupabaseClient client;
  final SupabaseAuthLinkHandler? authLinkHandler;

  late final StreamSubscription<AuthState> _authSubscription;
  final StreamController<bool> _recoveryEvents =
      StreamController<bool>.broadcast();

  /// Ends the recovery session and releases the auth subscription.
  Future<void> dispose() async {
    await _authSubscription.cancel();
    await _recoveryEvents.close();
  }

  void _onAuthStateChange(AuthState state) {
    if (state.event == AuthChangeEvent.passwordRecovery) {
      authLinkHandler?.clearExpectedFlow();
      _setRecovering(true);
      return;
    }
    if (state.event == AuthChangeEvent.signedIn) {
      authLinkHandler?.clearExpectedFlow();
    }
    // A sign-out ends any recovery window, so a later link cannot be replayed
    // against a session that has already been abandoned.
    if (state.event == AuthChangeEvent.signedOut) {
      _setRecovering(false);
    }
  }

  void _onAuthStreamError(Object error, StackTrace stackTrace) {
    authLinkHandler?.handleAuthStreamError(error, stackTrace);
  }

  void _setRecovering(bool value) {
    if (_recovering == value) return;
    _recovering = value;
    if (!_recoveryEvents.isClosed) _recoveryEvents.add(value);
  }

  @override
  bool get isAvailable => true;

  @override
  String? get currentEmail => client.auth.currentUser?.email;

  @override
  bool get isRecovering => _recovering;

  bool _recovering = false;

  /// Emits true when a password-recovery link has just been opened.
  ///
  /// A recovery session outlives any single widget, so a listener that arrives
  /// late is replayed the current value rather than being told only about future
  /// events. That is what makes a cold start work: the PKCE exchange finishes
  /// before the gate is built, and without the replay that event is gone.
  @override
  Stream<bool> get recoveryEvents async* {
    if (_recovering) yield true;
    yield* _recoveryEvents.stream;
  }

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final email = currentEmail;
    if (email == null || email.isEmpty) {
      throw const AccountException(
        'Your account email is unknown. Sign in again to change your password.',
      );
    }
    if (currentPassword == newPassword) {
      throw const AccountException(
        'Choose a new password that is different from your current one.',
      );
    }
    // Reauthenticate first. Supabase expects a credential change to come from a
    // session that has just been proven, and this is also what makes the current
    // password field meaningful: it is really checked, not merely collected.
    //
    // The new password is deliberately NOT part of this call. Signing in with the
    // new value would work, but it would briefly make the account recoverable
    // with a password the user has not confirmed, and it would replace the
    // current session before the change is committed.
    try {
      await client.auth.signInWithPassword(
        email: email,
        password: currentPassword,
      );
    } on AuthException {
      // Deliberately vague about which half was wrong.
      throw const AccountException('Your current password is not correct.');
    }
    await _updatePassword(newPassword);
  }

  @override
  Future<void> sendPasswordResetEmail(String email) async {
    authLinkHandler?.expectPasswordRecovery();
    try {
      // redirectTo reuses the project's existing deep-link architecture, so the
      // reset link returns through businessms://auth-callback exactly like the
      // email-confirmation link already does. The custom scheme is never
      // replaced with localhost.
      await client.auth.resetPasswordForEmail(
        email,
        redirectTo: SupabaseConfig.emailRedirectTo,
      );
    } on AuthException {
      authLinkHandler?.clearExpectedFlow();
      // Reported generically, so this screen cannot be used to test whether an
      // address is registered.
      throw const AccountException(
        'We could not send the reset link. Please try again in a moment.',
      );
    }
  }

  @override
  Future<void> resetPassword(String newPassword) async {
    if (!isRecovering) {
      throw const AccountException(
        'This password reset link is no longer valid. Please request a new one.',
      );
    }
    await _updatePassword(newPassword);
    authLinkHandler?.clearExpectedFlow();
    // The link has now been spent, so the recovery window closes. Without this a
    // later rebuild of the gate would offer the reset screen again for a session
    // that has already been used.
    _setRecovering(false);
  }

  Future<void> _updatePassword(String newPassword) async {
    try {
      await client.auth.updateUser(UserAttributes(password: newPassword));
    } on AuthException catch (error) {
      throw AccountException(_friendlyUpdateMessage(error));
    }
  }

  /// Turns a Supabase update failure into a message that is both useful and
  /// free of internal detail.
  String _friendlyUpdateMessage(AuthException error) {
    // AuthException.statusCode is a String in this SDK, so it is compared as
    // text rather than as an int. The helper is named hasStatus rather than
    // `is`, which is a reserved word in Dart.
    final status = error.statusCode;
    bool hasStatus(int code) => status == '$code';

    // A weak or reused password is refused by the server's own policy, so the
    // user is told the rule rather than shown the raw server text.
    if (hasStatus(422) || hasStatus(400)) {
      return 'That password was not accepted. Choose a different one that '
          'meets the password rules.';
    }
    if (hasStatus(401) || hasStatus(403)) {
      return 'Your session has expired. Please sign in again and retry.';
    }
    if (hasStatus(429)) {
      return 'Too many attempts. Please wait a moment and try again.';
    }
    return 'We could not update your password. Please try again.';
  }

  @override
  Future<void> cancelRecovery() async {
    authLinkHandler?.clearExpectedFlow();
    _setRecovering(false);
    try {
      await client.auth.signOut();
    } finally {
      PrintPreferences.clear();
    }
  }
}
