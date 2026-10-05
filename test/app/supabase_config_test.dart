import 'dart:io';

import 'package:flutter_application_2/app/supabase_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Supabase email confirmation callback', () {
    test('uses the registered application callback URL', () {
      expect(SupabaseConfig.emailRedirectTo, 'businessms://auth-callback');
    });

    test('accepts only the application auth callback host', () {
      expect(
        SupabaseConfig.isAuthCallback(
          Uri.parse('businessms://auth-callback?code=confirmation-code'),
        ),
        isTrue,
      );
      expect(
        SupabaseConfig.isAuthCallback(
          Uri.parse('https://auth-callback?code=confirmation-code'),
        ),
        isFalse,
      );
      expect(
        SupabaseConfig.isAuthCallback(
          Uri.parse('businessms://other-host?code=confirmation-code'),
        ),
        isFalse,
      );
    });

    // A recovery link is a PKCE callback like any other, so it must be accepted
    // by the same predicate. If this ever returned false, Android would launch
    // the app correctly and then silently show the login screen instead of the
    // reset screen, which is much harder to diagnose than a broken intent filter.
    test('accepts the password recovery callback Supabase actually sends', () {
      const recoveryLink = 'businessms://auth-callback?code=pkce-recovery-code';
      expect(SupabaseConfig.isAuthCallback(Uri.parse(recoveryLink)), isTrue);
    });
  });

  group('Android deep link registration', () {
    late String manifest;

    setUpAll(() {
      manifest = File('android/app/src/main/AndroidManifest.xml')
          .readAsStringSync();
    });

    /// The filter that lets Android hand the callback to this app.
    ///
    /// Without VIEW plus a BROWSABLE/DEFAULT data entry, the link is reported by
    /// the phone as an invalid address rather than opening the app.
    test('declares an intent filter for the custom scheme and host', () {
      expect(manifest, contains('android:scheme="businessms"'));
      expect(manifest, contains('android:host="auth-callback"'));
      expect(manifest, contains('android.intent.action.VIEW'));
      expect(manifest, contains('android.intent.category.BROWSABLE'));
      expect(manifest, contains('android.intent.category.DEFAULT'));
    });

    test('declares no other custom scheme that could hijack the callback', () {
      final schemes = RegExp(r'android:scheme="([^"]+)"')
          .allMatches(manifest)
          .map((m) => m.group(1))
          .toSet();
      expect(schemes, {'businessms'});
    });

    // A warm start reuses the running activity through onNewIntent. That only
    // works when the activity is singleTop; the default 'standard' launch mode
    // would create a second instance and the running one would never see the link.
    test('keeps the activity singleTop so a warm start is delivered', () {
      expect(manifest, contains('android:launchMode="singleTop"'));
    });

    // Android 12+ refuses to install an APK whose launcher activity is not
    // explicitly exported, which would leave the phone with no app to open.
    test('exports the activity so the system can launch it', () {
      expect(manifest, contains('android:exported="true"'));
    });
  });
}
