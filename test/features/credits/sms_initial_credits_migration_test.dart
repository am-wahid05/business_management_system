import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'new company SMS balance is controlled by the additive migration at 5',
    () {
      final migration = File(
        'supabase/migrations/202610020001_sms_initial_credits_and_send_claims.sql',
      ).readAsStringSync();

      expect(migration, contains('alter column sms_credits set default 5'));
      expect(migration, contains('existing balances are unchanged'));
      expect(
        migration,
        isNot(contains('update public.companies set sms_credits')),
      );
    },
  );
}
