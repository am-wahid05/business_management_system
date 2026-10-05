import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract final class SupabaseConfig {
  /// The one native callback URI used by Android, Windows and other native
  /// builds. Keep this value identical to the Supabase Dashboard additional
  /// redirect URL and to each platform's URI registration.
  static const nativeAuthCallback = 'businessms://auth-callback';
  static final Set<String> _processedCallbackFingerprints = <String>{};

  // Publishable keys are intended for client applications; access is still
  // restricted by Supabase Auth and the row-level security policies.
  static const url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://simhlgswtlpylpsdwyoy.supabase.co',
  );
  static const publishableKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_BJByb3_JBVIYEivDhXzKnQ_P2pI6ehJ',
  );

  /// Supabase is the normal app authentication path. The local repository is
  /// kept for tests and explicitly selected offline/demo installations only.
  /// Select it with `--dart-define=ALBNC_AUTH_MODE=local`.
  static const authMode = String.fromEnvironment(
    'ALBNC_AUTH_MODE',
    defaultValue: 'supabase',
  );

  static bool get useLocalAuth => authMode == 'local';

  /// Native builds use the registered custom scheme. On web, leaving this null
  /// makes Supabase use its configured Site URL, which is the URL the browser
  /// can actually reopen after email confirmation or password recovery.
  static String? get emailRedirectTo => kIsWeb ? null : nativeAuthCallback;

  /// Limits Supabase's deep-link handler to this application's callback URL.
  static bool isAuthCallback(Uri uri) {
    final nativeCallback = Uri.parse(nativeAuthCallback);
    if (uri.scheme.toLowerCase() == nativeCallback.scheme &&
        uri.host.toLowerCase() == nativeCallback.host) {
      return true;
    }
    if (!kIsWeb ||
        (uri.scheme.toLowerCase() != 'http' &&
            uri.scheme.toLowerCase() != 'https')) {
      return false;
    }
    if (uri.origin != Uri.base.origin) return false;
    final fragment = _safeFragmentParameters(uri.fragment);
    return uri.queryParameters.keys.any(_isAuthParameter) ||
        fragment.keys.any(_isAuthParameter);
  }

  /// Restricts Supabase's session exchange to one delivery of each callback.
  ///
  /// The OS can deliver a callback again when an already-open application is
  /// resumed. A spent PKCE code must not be exchanged a second time. Only an
  /// in-memory fingerprint is retained; callback contents and tokens are never
  /// logged or persisted.
  static bool shouldProcessAuthCallback(Uri uri) {
    if (!isAuthCallback(uri)) return false;
    return _processedCallbackFingerprints.add(uri.toString());
  }

  static bool _isAuthParameter(String key) =>
      key == 'access_token' ||
      key == 'code' ||
      key == 'error' ||
      key == 'error_code' ||
      key == 'error_description';

  static Map<String, String> _safeFragmentParameters(String fragment) {
    if (fragment.isEmpty) return const {};
    try {
      return Uri.splitQueryString(fragment);
    } on FormatException {
      return const {};
    }
  }

  static bool get isConfigured =>
      url.trim().isNotEmpty && publishableKey.trim().isNotEmpty;

  static Future<SupabaseClient?> initialize() async {
    if (!isConfigured) return null;
    await Supabase.initialize(
      url: url,
      publishableKey: publishableKey,
      authOptions: FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
        detectSessionInUriPredicate: shouldProcessAuthCallback,
      ),
    );
    return Supabase.instance.client;
  }
}
