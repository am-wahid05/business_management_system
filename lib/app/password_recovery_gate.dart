import 'dart:async';

import 'package:flutter/material.dart';

import '../features/auth/account_service.dart';
import '../features/auth/reset_password_screen.dart';
import '../features/auth/supabase_auth_link_handler.dart';
import 'app_routes.dart';

/// Watches for a Supabase password-recovery event and shows the reset screen.
///
/// The reason this exists as its own gate, wrapping the whole navigator, is that
/// a recovery link arrives as a deep link while the app may already be running
/// on any screen. Supabase signals it with [AuthChangeEvent.passwordRecovery]
/// after the PKCE exchange on businessms://auth-callback completes, so no extra
/// redirect scheme, no localhost, and no second deep-link handler is needed: it
/// reuses the existing callback architecture exactly as email confirmation
/// already does.
///
/// Two safety properties come from wrapping the navigator rather than pushing a
/// route:
///   * The reset screen is the ONLY thing visible during recovery, so a recovery
///     session can never fall through to a dashboard and look as if the
///     password had already been changed.
///   * An email-confirmation callback and a password-recovery callback are told
///     apart by the auth event itself, not by guessing from the URL, so opening
///     a confirmation link never lands on the reset screen.
class PasswordRecoveryGate extends StatefulWidget {
  const PasswordRecoveryGate({
    required this.accountService,
    this.authLinkHandler,
    required this.child,
    super.key,
  });

  /// Null in the local-only setup, where there is no recovery flow to run.
  final AccountService? accountService;
  final SupabaseAuthLinkHandler? authLinkHandler;

  final Widget? child;

  @override
  State<PasswordRecoveryGate> createState() => _PasswordRecoveryGateState();
}

class _PasswordRecoveryGateState extends State<PasswordRecoveryGate> {
  StreamSubscription<bool>? _subscription;
  StreamSubscription<AuthLinkError>? _callbackSubscription;

  /// True while a recovery session is being handled.
  ///
  /// This starts from the service's own flag rather than from `false`, because a
  /// recovery link is often exchanged before this gate is built: on a cold start
  /// the PKCE code exchange completes during app start-up, and on Android the
  /// session then publishes a user, which changes the MaterialApp key and
  /// rebuilds this whole subtree. Seeding from the service means a rebuilt gate
  /// still shows the reset screen instead of briefly falling through to the
  /// dashboard, where a recovery session would look like a normal sign-in.
  bool _recovering = false;

  /// Whether the reset screen has already been shown for the current event, so
  /// the same event cannot push the screen twice.
  bool _handled = false;
  AuthLinkError? _callbackError;

  @override
  void initState() {
    super.initState();
    _recovering = widget.accountService?.isRecovering ?? false;
    _callbackError = widget.authLinkHandler?.latestError;
    _listen();
    _listenForCallbackErrors();
  }

  @override
  void didUpdateWidget(covariant PasswordRecoveryGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.accountService != widget.accountService) {
      _subscription?.cancel();
      _handled = false;
      // Re-read rather than assume: the new service may already hold an active
      // recovery session from a link opened before this widget was rebuilt.
      _recovering = widget.accountService?.isRecovering ?? false;
      _listen();
    }
    if (oldWidget.authLinkHandler != widget.authLinkHandler) {
      _callbackSubscription?.cancel();
      _callbackError = widget.authLinkHandler?.latestError;
      _listenForCallbackErrors();
    }
  }

  void _listen() {
    final account = widget.accountService;
    if (account == null) return;
    _subscription = account.recoveryEvents.listen(_onRecoveryEvent);
  }

  void _listenForCallbackErrors() {
    final handler = widget.authLinkHandler;
    if (handler == null) return;
    _callbackSubscription = handler.errors.listen((error) {
      if (!mounted) return;
      setState(() => _callbackError = error);
    });
  }

  void _onRecoveryEvent(bool recovering) {
    if (!recovering || !mounted) return;
    if (_handled) return;
    _handled = true;
    // The navigator is not available during initState, so the screen is shown
    // by swapping the child rather than by pushing a route. That is also what
    // guarantees the reset screen covers whatever was on screen.
    setState(() => _recovering = true);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _callbackSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final account = widget.accountService;
    final callbackError = _callbackError;
    if (callbackError != null) {
      return Navigator(
        onGenerateRoute: (settings) => MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => _AuthCallbackErrorScreen(
            error: callbackError,
            onBack: () {
              widget.authLinkHandler?.clearError();
              if (mounted) setState(() => _callbackError = null);
            },
          ),
        ),
      );
    }
    if (!_recovering || account == null) {
      return widget.child ?? const SizedBox();
    }
    // The gate deliberately sits above the app's Navigator so that the reset
    // screen replaces whatever was on screen instead of being pushed over it.
    // That placement means there is no Overlay above this widget, and the reset
    // form's password-visibility control is a Tooltip, which requires one. The
    // private Navigator supplies the Overlay and Material ancestor the form
    // needs, without giving the reset screen a route that ordinary navigation
    // could pop and reveal the screen underneath.
    return Navigator(
      onGenerateRoute: (settings) => MaterialPageRoute<void>(
        settings: settings,
        builder: (context) => ResetPasswordScreen(
          accountService: account,
          onCompleted: () {
            // The reset is finished, so the gate steps aside and the normal
            // sign-in flow takes over again. `_handled` is cleared as well, so a
            // second reset link later in the same session is handled again.
            if (!mounted) return;
            setState(() {
              _recovering = false;
              _handled = false;
            });
          },
        ),
      ),
    );
  }
}

/// The route name the reset screen is registered under.
///
/// Recovery is handled by [PasswordRecoveryGate] rather than by pushing this
/// route, because a pushed route could be popped or replaced by an ordinary
/// navigation. It is kept here so the route table and the gate cannot drift
/// apart.
const String passwordResetRoute = AppRoutes.resetPassword;

class _AuthCallbackErrorScreen extends StatelessWidget {
  const _AuthCallbackErrorScreen({required this.error, required this.onBack});

  final AuthLinkError error;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final title = switch (error.kind) {
      AuthLinkKind.passwordRecovery => 'Reset link unavailable',
      AuthLinkKind.emailVerification => 'Verification link unavailable',
      AuthLinkKind.unknown => 'Email link unavailable',
    };
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  Icons.link_off_outlined,
                  size: 56,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(height: 16),
                Text(error.message, textAlign: TextAlign.center),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: onBack,
                  child: const Text('Return to Sign In'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
