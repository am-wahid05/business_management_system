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

  static bool get isConfigured => url.isNotEmpty && publishableKey.isNotEmpty;

  static Future<SupabaseClient?> initialize() async {
    if (!isConfigured) return null;
    await Supabase.initialize(url: url, publishableKey: publishableKey);
    return Supabase.instance.client;
  }
}
