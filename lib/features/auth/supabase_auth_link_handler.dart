import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';

import '../../app/supabase_config.dart';

/// The kind of Supabase email link that failed before a session was created.
enum AuthLinkKind { passwordRecovery, emailVerification, unknown }

/// A safe, user-facing failure reported by a Supabase email callback.
class AuthLinkError {
  const AuthLinkError({required this.kind, required this.message});

  final AuthLinkKind kind;
  final String message;
}

/// Observes callback failures while leaving session exchange to supabase_flutter.
///
/// Supabase Flutter already owns the actual PKCE/deep-link exchange. This class
/// deliberately does not parse or exchange tokens. It only observes the same
/// callback URI so expired and invalid links can be rendered in the app instead
/// of being left as an unhandled provider error.
class SupabaseAuthLinkHandler {
  SupabaseAuthLinkHandler({
    this._appLinks,
    this._incomingLinks,
    this._initialUri,
    bool Function(Uri uri)? isAuthCallback,
  }) : _isAuthCallback = isAuthCallback ?? SupabaseConfig.isAuthCallback;

  final AppLinks? _appLinks;
  final Stream<Uri>? _incomingLinks;
  final Uri? _initialUri;
  final bool Function(Uri uri) _isAuthCallback;
  final StreamController<AuthLinkError> _errors =
      StreamController<AuthLinkError>.broadcast();

  StreamSubscription<Uri>? _subscription;
  AuthLinkError? _latestError;
  AuthLinkKind? _expectedKind;
  AuthLinkKind? _pendingFlowKind;
  String? _latestErrorSignature;
  bool _observedAuthCallback = false;
  bool _started = false;

  AuthLinkError? get latestError => _latestError;

  /// A valid recovery callback can be exchanged while Supabase initializes,
  /// before the account service is constructed. The service consumes this marker
  /// instead of attempting a second callback exchange.
  bool takePendingPasswordRecovery() {
    if (_pendingFlowKind != AuthLinkKind.passwordRecovery) return false;
    _pendingFlowKind = null;
    return true;
  }

  /// Replays the latest callback error to a cold-start listener.
  Stream<AuthLinkError> get errors async* {
    final latest = _latestError;
    if (latest != null) yield latest;
    yield* _errors.stream;
  }

  Future<void> start() async {
    if (_started) return;
    _started = true;

    if (_initialUri != null) _inspect(_initialUri);
    if (kIsWeb) {
      _inspect(_initialUri ?? Uri.base);
      return;
    }

    final incomingLinks = _incomingLinks;
    if (incomingLinks != null) {
      _subscription = incomingLinks.listen(_inspect);
      return;
    }

    final appLinks = _appLinks ?? AppLinks();
    // Supabase's own observer is started before this class in main.dart. This
    // listener therefore observes runtime callbacks without taking ownership of
    // the official PKCE exchange. The initial URI is read separately because
    // app_links delivers the cold-start event only to the first stream listener.
    _subscription = appLinks.uriLinkStream.listen(_inspect);
    try {
      final initial = await appLinks.getInitialLink();
      if (initial != null) _inspect(initial);
    } on Object {
      // Supabase remains the authority for session exchange. A platform failure
      // while reading the optional duplicate observer must not interrupt auth.
    }
  }

  void expectPasswordRecovery() {
    _expectedKind = AuthLinkKind.passwordRecovery;
  }

  void expectEmailVerification() {
    _expectedKind = AuthLinkKind.emailVerification;
  }

  void _inspect(Uri uri) {
    if (!_isAuthCallback(uri)) return;
    _observedAuthCallback = true;

    final parameters = <String, String>{
      ...uri.queryParameters,
      ..._fragmentParameters(uri),
    };
    final kind = _kindFor(parameters);
    final errorCode = parameters['error_code'] ?? parameters['error'];
    final description = parameters['error_description'];
    if (errorCode == null && description == null) {
      if (kind == AuthLinkKind.passwordRecovery) _pendingFlowKind = kind;
      return;
    }
    _emitError(kind, errorCode, description);
    clearExpectedFlow();
  }

  AuthLinkKind _kindFor(Map<String, String> parameters) {
    final declared = switch (parameters['type']?.toLowerCase()) {
      'recovery' => AuthLinkKind.passwordRecovery,
      'email' || 'signup' => AuthLinkKind.emailVerification,
      _ => null,
    };
    return declared ?? _expectedKind ?? AuthLinkKind.unknown;
  }

  void _emitError(AuthLinkKind kind, String? code, String? description) {
    final message = _friendlyMessage(code, description);
    final signature = '${kind.name}:$message';
    if (_latestErrorSignature == signature) {
      clearExpectedFlow();
      return;
    }
    final error = AuthLinkError(kind: kind, message: message);
    _latestErrorSignature = signature;
    _latestError = error;
    if (!_errors.isClosed) _errors.add(error);
  }

  /// Receives errors from Supabase Flutter's single, official callback/session
  /// exchange. This method never exchanges a token itself.
  void handleAuthStreamError(Object error, [StackTrace? stackTrace]) {
    final message = error.toString();
    final looksLikeLinkFailure = _expectedKind != null || _observedAuthCallback;
    if (!looksLikeLinkFailure) return;
    _emitError(_expectedKind ?? AuthLinkKind.unknown, null, message);
    clearExpectedFlow();
  }

  void clearExpectedFlow() {
    _expectedKind = null;
    _observedAuthCallback = false;
  }

  static Map<String, String> _fragmentParameters(Uri uri) {
    if (uri.fragment.isEmpty) return const {};
    try {
      return Uri.splitQueryString(uri.fragment);
    } on FormatException {
      return const {};
    }
  }

  static String _friendlyMessage(String? code, String? description) {
    final normalized = '${code ?? ''} ${description ?? ''}'.toLowerCase();
    if (normalized.contains('expired') ||
        normalized.contains('invalid') ||
        normalized.contains('already_used') ||
        normalized.contains('already used') ||
        normalized.contains('otp_expired')) {
      return 'This email link is invalid, expired, or has already been used. '
          'Request a new link and try again.';
    }
    return 'We could not complete this email-link sign-in. Request a new link '
        'and try again.';
  }

  void clearError() {
    _latestError = null;
    _latestErrorSignature = null;
    clearExpectedFlow();
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    await _errors.close();
  }
}
