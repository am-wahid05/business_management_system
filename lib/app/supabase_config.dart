import 'package:supabase_flutter/supabase_flutter.dart';

abstract final class SupabaseConfig {
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

  static const emailRedirectTo = 'businessms://auth-callback';

  /// Limits Supabase's deep-link handler to this application's callback URL.
  static bool isAuthCallback(Uri uri) =>
      uri.scheme.toLowerCase() == 'businessms' && uri.host == 'auth-callback';

  static bool get isConfigured =>
      url.trim().isNotEmpty && publishableKey.trim().isNotEmpty;

  static Future<SupabaseClient?> initialize() async {
    if (!isConfigured) return null;
    await Supabase.initialize(
      url: url,
      publishableKey: publishableKey,
      authOptions: FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
        detectSessionInUriPredicate: isAuthCallback,
      ),
    );
    return Supabase.instance.client;
  }
}
