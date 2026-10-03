import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('forward migration assigns auth.uid and prevents recorder edits', () {
    final sql = File(
      'supabase/migrations/202609240002_recorded_by_identity.sql',
    ).readAsStringSync();

    expect(sql, contains('alter column recorded_by_user_id drop not null'));
    expect(sql, contains('add column if not exists recorded_by_user_id uuid'));
    expect(sql, contains('new.recorded_by_user_id := actor_id'));
    expect(
      sql,
      contains(
        'new.recorded_by_user_id is distinct from old.recorded_by_user_id',
      ),
    );
    expect(sql, contains('deliveries_recorded_by_guard'));
    expect(sql, contains('bag_weights_recorded_by_guard'));
    expect(sql, contains('deliveries_recorded_by_insert_boundary'));
    expect(sql, contains('bag_weights_recorded_by_insert_boundary'));
    expect(sql, isNot(contains('update public.deliveries set')));
    expect(sql, isNot(contains('update public.delivery_bag_weights set')));
  });
}
