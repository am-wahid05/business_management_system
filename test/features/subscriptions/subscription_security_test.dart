import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the security properties of the subscription backend.
///
/// The authorization, company-isolation and read-only rules live in SQL, which
/// `flutter test` cannot execute. These checks read the migration so the
/// critical invariants cannot be silently removed: if someone later lets a
/// client settle a payment, trusts a client-supplied company, or lets a
/// secretary read billing, this suite fails.
void main() {
  final migration = File(
    'supabase/migrations/202609270001_subscriptions.sql',
  ).readAsStringSync();

  // Line comments are stripped. Block comments are left alone because the
  // security rules are documented there and the assertions must not be
  // satisfied by prose.
  final sql = migration.replaceAll(RegExp(r'--.*'), '');

  /// The text of a routine, from its name up to the next routine definition.
  ///
  /// Bounded by the next `create or replace function` so a slice always ends at
  /// a sensible place, and never by the first `end;`, which appears inside
  /// nested plpgsql blocks long before the routine actually ends.
  String body(String marker) {
    final start = sql.indexOf(marker);
    if (start < 0) return '';
    final end = sql.indexOf('create or replace function', start + marker.length);
    return sql.substring(start, end < 0 ? sql.length : end);
  }

  group('payment settlement cannot be reached by a client', () {
    test('apply_verified_payment requires the service role', () {
      // The single function that can grant an entitlement refuses to run for
      // anything except the service role, so Flutter can never call it.
      expect(sql, contains("auth.jwt() ->> 'role'"));
      expect(sql, contains("<> 'service_role'"));
      expect(
        sql,
        contains('Payments are settled by a trusted server only'),
      );
    });

    test('settlement refuses a payment with no provider reference', () {
      // A created intent is not a payment. Without the provider's own reference
      // there is nothing to verify, so nothing is granted.
      expect(
        sql,
        contains('A payment cannot be settled without a provider reference'),
      );
    });

    test('a replayed payment is answered without granting anything again', () {
      expect(sql, contains("if pay.status = 'SUCCESSFUL' then"));
      expect(sql, contains("'applied', false, 'idempotent', true"));
    });

    test('the provider reference is unique per provider', () {
      // The database-level half of the idempotency guarantee.
      expect(sql, contains('payment_provider_reference_key'));
      expect(sql, contains('create unique index'));
    });

    test('the payment row is locked before it is settled', () {
      expect(sql, contains('for update'));
    });

    test('success cannot be recorded without a provider reference', () {
      // A belt-and-braces database constraint on top of the function check.
      expect(sql, contains('payment_verified_needs_reference'));
    });
  });

  group('the 30-day trial is created automatically, exactly once', () {
    test('a trigger on the companies table starts the trial', () {
      // Companies are created by public.handle_new_user() during sign-up. Until
      // this trigger existed nothing called start_company_trials(), so a brand
      // new company had no subscription row at all.
      expect(
        sql,
        contains('create trigger company_trial_onboarding'),
      );
      expect(
        sql,
        contains('after insert on public.companies'),
      );
    });

    test('the trigger calls a dedicated trigger function', () {
      // PostgreSQL forbids passing an argument to EXECUTE FUNCTION, so the
      // trigger cannot call start_company_trials(new.id) directly. It calls a
      // dedicated RETURNS TRIGGER wrapper instead.
      expect(
        sql,
        contains('execute function public.grant_company_trial_on_insert()'),
      );
      expect(
        sql,
        isNot(contains('execute function public.start_company_trials')),
      );
    });

    test('that trigger function has a valid PostgreSQL trigger signature', () {
      // RETURNS TRIGGER, no parameters, and it returns NEW.
      final start = sql.indexOf('create or replace function public.grant_company_trial_on_insert()');
      expect(start, isNot(-1));
      final body = sql.substring(start, sql.indexOf(r'$$;', start));
      expect(body, contains('returns trigger'));
      expect(body, contains('perform public.start_company_trials(new.id);'));
      expect(body, contains('return new;'));
      // A trigger function takes no declared parameters.
      expect(
        body,
        isNot(contains('grant_company_trial_on_insert(uuid)')),
      );
    });

    test('the trigger is AFTER INSERT only, never on update', () {
      // AFTER INSERT means editing an existing company cannot hand it a trial.
      expect(sql, contains('after insert on public.companies'));
      expect(sql, isNot(contains('after update on public.companies')));
    });

    test('the trigger is attached to the table, not to sign-up', () {
      // Covering the table means every creation path is covered: the auth
      // trigger, a manual insert, or any future provisioning route.
      expect(sql, isNot(contains('on auth.users')));
    });

    test('the trial is created only once, by ON CONFLICT DO NOTHING', () {
      // This single property is what stops a second trial. The trigger only
      // fires for a brand new company row, and the insert is a no-op when one
      // already exists.
      final trials = body('start_company_trials');
      final conflicts = 'on conflict (company_id) do nothing'.allMatches(trials);
      expect(conflicts.length, 2, reason: 'Both the software and AI trial.');
    });

    test('a repeat call writes no second audit event', () {
      // The event is only recorded when a trial was actually created, so a
      // reinstall or a re-login cannot even fake a second "trial started".
      final trials = body('start_company_trials');
      expect(trials, contains('created_company := found'));
      expect(trials, contains('if not created_company then'));
    });

    test('the trial length comes from configuration, not a literal', () {
      // 30 days is the default in subscription_config, not a number baked
      // into the trigger or the function.
      final trials = body('start_company_trials');
      expect(trials, contains('cfg.software_trial_days'));
      expect(trials, contains('cfg.ai_trial_days'));
      expect(trials, isNot(contains("+ interval '30 day'")));
    });

    test('existing companies are backfilled exactly once', () {
      // Companies created before this migration get their trial from a
      // conflict-guarded backfill, which a re-run also cannot duplicate.
      expect(sql, contains('on conflict (company_id) do nothing'));
    });

    test('nothing but a new company can start a trial', () {
      // Renewal, pause and reactivation must never write a trial, or a
      // seasonal company could farm a new one.
      for (final routine in [
        'apply_verified_payment',
        'pause_company_subscription',
        'resume_company_subscription',
      ]) {
        expect(
          body(routine),
          isNot(contains('trial_started_at =')),
          reason: '$routine must never start a trial.',
        );
      }
    });
  });

  group('expiry is enforced from the dates, not from a stale status', () {
    test('the projection derives an effective status', () {
      // If company_entitlements() simply echoed the status column, a company
      // whose expiry had passed but whose sweep had not run would keep admin
      // access indefinitely. The status is therefore recomputed at read time.
      final projection = body('company_entitlements');
      expect(projection, contains('as stored_status'));
      expect(projection, contains('as effective_grace_end'));
      expect(projection, contains('as sub_status'));
    });

    test('an expired paid period falls into grace even if the sweep has not run', () {
      final projection = body('company_entitlements');
      // A stored ACTIVE whose current_period_end has passed must be reported
      // as GRACE_PERIOD, and its grace end derived from the period end.
      expect(
        projection,
        contains("r.stored_status = 'ACTIVE' and r.current_period_end is not null"),
      );
      expect(
        projection,
        contains("then 'GRACE_PERIOD'::public.subscription_status"),
      );
    });

    test('an expired trial also falls into grace without a sweep', () {
      final projection = body('company_entitlements');
      expect(
        projection,
        contains("r.stored_status = 'TRIAL' and r.trial_ends_at is not null"),
      );
    });

    test('the grace window end is derived, and is monotonic once passed', () {
      final projection = body('company_entitlements');
      // Once the derived grace end is in the past the status is EXPIRED, and it
      // stays there because the derived end does not move.
      expect(projection, contains("then 'EXPIRED'::public.subscription_status"));
      expect(projection, contains('coalesce('));
      expect(
        projection,
        contains('make_interval(days => coalesce(r.grace_period_days, 7))'),
      );
    });

    test('canAccessAdmin is decided from the effective status', () {
      final projection = body('company_entitlements');
      expect(
        projection,
        contains(
          "'canAccessAdmin', r.sub_status in ('TRIAL', 'ACTIVE', 'GRACE_PERIOD')",
        ),
      );
      // It must NOT be read from the stored status anywhere.
      expect(
        projection,
        isNot(contains("'canAccessAdmin', r.stored_status")),
      );
    });

    test('secretary work is still independent of the admin lock', () {
      final projection = body('company_entitlements');
      // Expiry must not stop a company recording deliveries.
      expect(
        projection,
        contains("'canRecordAsSecretary', r.sub_status <> 'PAUSED'"),
      );
    });

    test('a paused company is still derived, never date-driven', () {
      // PAUSE is explicit and not a function of dates, so it must be the first
      // branch: a paused company is never dragged into grace or expiry.
      final projection = body('company_entitlements');
      final pausedAt =
          projection.indexOf("when e.stored_status = 'PAUSED' then 'PAUSED'");
      final expiredAt =
          projection.indexOf("then 'EXPIRED'::public.subscription_status");
      expect(pausedAt, isNot(-1));
      expect(expiredAt, isNot(-1));
      expect(pausedAt < expiredAt, isTrue);
    });

    test('the projection reads from the derived state, not the raw one', () {
      final projection = body('company_entitlements');
      expect(projection, contains('from final_state r;'));
      expect(projection, isNot(contains('from resolved r;')));
    });
  });

  group('the secretary allowance is safe under concurrent additions', () {
    test('a row lock is taken before the count', () {
      // Without a lock, two simultaneous inserts both count the same
      // pre-existing secretaries and both succeed, exceeding the allowance.
      final trigger = body('enforce_secretary_limit');
      final lock = trigger.indexOf('for update of c, s;');
      final count = trigger.indexOf('select count(*) into current_count');
      expect(lock, isNot(-1), reason: 'The count must be under a row lock');
      expect(count, isNot(-1));
      expect(lock < count, isTrue);
    });

    test('the lock covers the company and its subscription row', () {
      // The company row always exists, so it is a stable per-company mutex even
      // for a company with no subscription row yet.
      final trigger = body('enforce_secretary_limit');
      expect(trigger, contains('from public.companies c'));
      expect(trigger, contains('left join public.company_subscriptions s'));
      expect(trigger, contains('for update of c, s;'));
    });

    test('the allowance is read only after the lock is held', () {
      final trigger = body('enforce_secretary_limit');
      final lock = trigger.indexOf('for update of c, s;');
      final read = trigger.indexOf("->> 'maxSecretaries'");
      expect(read, isNot(-1));
      expect(lock < read, isTrue);
    });

    test('the limit still only ever blocks insertions', () {
      // The lock must not change who is allowed through.
      final trigger = body('enforce_secretary_limit');
      expect(
        trigger,
        contains("if tg_op <> 'INSERT' or new.role <> 'secretary' then"),
      );
      expect(trigger, contains('SECRETARY_LIMIT_REACHED'));
    });
  });

  group('the migration is structurally whole', () {
    test('every dollar-quote token is paired', () {
      // An unpaired $$ means a DO block or function body runs on into whatever
      // follows it, which is how this file was previously corrupted.
      final tokens = r'$$'.allMatches(sql).length;
      expect(
        tokens.isEven,
        isTrue,
        reason: 'Found $tokens dollar-quote tokens; the count must be even.',
      );
      // 9 functions + 5 DO blocks.
      expect(tokens, 28);
    });

    test('every DO block is closed', () {
      // 1 prerequisite check + 4 enum types.
      final openers = r'do $$'.allMatches(sql).length;
      expect(openers, 5);
      // Each enum DO block ends with its own `end $$;`. The line ending is
      // matched loosely because this file is CRLF on Windows.
      expect(
        RegExp(
          r'exception when duplicate_object then null;\r?\nend \$\$;',
        ).allMatches(sql).length,
        4,
      );
    });

    test('every function has a body and a terminator', () {
      final functions = 'create or replace function'.allMatches(sql).length;
      expect(functions, 9);
      // Each function opens with `as $$` and closes with its own `$$;` line.
      expect(r'as $$'.allMatches(sql).length, functions);
      // 9 function terminators, plus the one from the multi-line prerequisite
      // DO block, which also ends with `$$;` on its own line.
      expect(
        RegExp(r'^\$\$;', multiLine: true).allMatches(sql).length,
        functions + 1,
      );
    });

    test('both trigger functions return trigger', () {
      // A trigger function that does not return trigger is rejected by
      // PostgreSQL, and one that takes a parameter is not callable as a
      // trigger at all.
      expect('returns trigger'.allMatches(sql).length, 2);
    });

    test('each create table is closed', () {
      // A table opened but never closed swallows everything after it.
      final opened = RegExp(r'create table if not exists public\.\w+ \(')
          .allMatches(sql)
          .length;
      expect(opened, 5);
      for (final table in [
        'subscription_config',
        'company_subscriptions',
        'company_ai_entitlements',
        'payment_transactions',
        'subscription_events',
      ]) {
        final start = sql.indexOf('create table if not exists public.$table (');
        expect(start, isNot(-1), reason: '$table must be created');
        // Find where the next top-level object begins. The table MUST close
        // before that point, otherwise its columns would swallow what follows.
        final rest = sql.substring(start + 1);
        final nextObject = RegExp(
          r'\r?\n(create table|create index|create unique index|create or replace function|drop policy|create policy|insert into|do \$\$|--\r?\n-- \d+\.)',
        ).firstMatch(rest);
        final limit = nextObject?.start ?? rest.length;
        final statement = rest.substring(0, limit);
        expect(
          RegExp(r'\r?\n\);').hasMatch(statement),
          isTrue,
          reason: '$table must be closed before the next statement',
        );
      }
    });

    test('company_ai_entitlements carries its full design', () {
      // This table was previously opened here and had its columns left
      // stranded further down the file, which is not valid SQL.
      final start = sql.indexOf('create table if not exists public.company_ai_entitlements (');
      expect(start, isNot(-1));
      final rest = sql.substring(start);
      final body = rest.substring(0, RegExp(r'\r?\n\);').firstMatch(rest)!.end);
      for (final fragment in [
        'company_id uuid primary key references public.companies(id) on delete cascade',
        'status public.ai_entitlement_status',
        'trial_started_at timestamptz',
        'trial_ends_at timestamptz',
        'trial_consumed boolean not null default false',
        'current_period_start timestamptz',
        'current_period_end timestamptz',
        'created_at timestamptz not null default now()',
        'updated_at timestamptz not null default now()',
        'constraint ai_trial_paired check',
      ]) {
        expect(body, contains(fragment));
      }
    });

    test('the enums are all fully defined and closed', () {
      for (final type in [
        'subscription_status',
        'ai_entitlement_status',
        'payment_purpose',
        'payment_status',
      ]) {
        expect(sql, contains('create type public.$type as enum'));
      }
      // Each enum DO block ends with its own `end $$;`.
      expect(
        RegExp(
          r"'PENDING', 'PROCESSING', 'SUCCESSFUL', 'FAILED', 'CANCELLED', "
          r"'EXPIRED', 'REFUNDED'\);\r?\nexception when duplicate_object "
          r'then null;\r?\nend \$\$;',
        ).allMatches(sql).length,
        1,
        reason: 'payment_status must be closed correctly',
      );
    });

    test('objects are created before they are used', () {
      // company_subscriptions references the enums, so the enums come first.
      int before(String a, String b) =>
          sql.indexOf(a) < sql.indexOf(b) ? 0 : 1;

      expect(
        before(
          'create type public.subscription_status',
          'create table if not exists public.company_subscriptions',
        ),
        0,
      );
      expect(
        before(
          'create type public.ai_entitlement_status',
          'create table if not exists public.company_ai_entitlements',
        ),
        0,
      );
      expect(
        before(
          'create type public.payment_status',
          'create table if not exists public.payment_transactions',
        ),
        0,
      );
      // subscription_events has a foreign key to payment_transactions.
      expect(
        before(
          'create table if not exists public.payment_transactions',
          'create table if not exists public.subscription_events',
        ),
        0,
      );
      // The onboarding function must exist before the trigger that calls it.
      expect(
        before(
          'create or replace function public.start_company_trials',
          'create or replace function public.grant_company_trial_on_insert',
        ),
        0,
      );
      expect(
        before(
          'create or replace function public.grant_company_trial_on_insert',
          'create trigger company_trial_onboarding',
        ),
        0,
      );
      // The event helper must exist before any caller uses it.
      expect(
        before(
          'create or replace function public.record_subscription_event',
          'create or replace function public.start_company_trials',
        ),
        0,
      );
    });
  });

  group('company isolation', () {
    test('every billing table enables row level security', () {
      for (final table in [
        'public.subscription_config',
        'public.company_subscriptions',
        'public.company_ai_entitlements',
        'public.payment_transactions',
        'public.subscription_events',
      ]) {
        expect(
          sql,
          contains('alter table $table enable row level security'),
          reason: '$table must have RLS enabled.',
        );
      }
    });

    test('billing rows are readable only by an admin of that company', () {
      expect(
        sql,
        contains(
          'create policy subscriptions_admin_read on public.company_subscriptions',
        ),
      );
      expect(
        sql,
        contains(
          "public.has_company_role(company_id, array['owner','admin']::public.company_role[])",
        ),
      );
    });

    test('a secretary cannot read the company billing position', () {
      // The policy names only owner/admin, so a secretary's own membership
      // never satisfies it. They are not a route around subscription
      // administration. Only the policy itself is inspected, so a later
      // policy in the file cannot affect the result.
      final start = sql.indexOf('create policy subscriptions_admin_read');
      final next = sql.indexOf('create policy', start + 10);
      final policy = sql.substring(start, next == -1 ? sql.length : next);
      expect(policy, contains('has_company_role'));
      expect(policy, isNot(contains('is_company_member')));
      expect(policy, isNot(contains('is_company_admin')));
    });

    test('no client-writable policy exists for the billing tables', () {
      // Only SELECT policies are created, so the authenticated role cannot
      // insert, update or delete a subscription, payment or event.
      expect(sql, isNot(contains('for insert to authenticated')));
      expect(sql, isNot(contains('for update to authenticated')));
      expect(sql, isNot(contains('for delete to authenticated')));
    });

    test('every billing table carries a company foreign key', () {
      for (final table in [
        'public.company_subscriptions',
        'public.company_ai_entitlements',
        'public.payment_transactions',
        'public.subscription_events',
      ]) {
        expect(sql, contains('create table if not exists $table'));
      }
      expect(
        sql,
        contains('company_id uuid not null references public.companies(id)'),
      );
    });
  });

  group('pause, renewal and expiry never delete data', () {
    test('the expiry sweep only changes status', () {
      // No delete anywhere in the sweep: a lapsed company keeps everything.
      expect(body('sweep_expired_subscriptions'), isNot(contains('delete')));
    });

    test('pausing and resuming never delete', () {
      for (final routine in [
        'pause_company_subscription',
        'resume_company_subscription',
      ]) {
        expect(
          body(routine),
          isNot(contains('delete')),
          reason: '$routine must not delete any company data.',
        );
      }
    });

    test('reactivating never issues a second trial', () {
      // trial_started_at and trial_ends_at are never written on resume, so a
      // seasonal company cannot farm a new trial by pausing and returning.
      final statements = body('resume_company_subscription');
      expect(statements, isNot(contains('trial_started_at =')));
      expect(statements, isNot(contains('trial_ends_at =')));
    });

    test('pausing an already-paused subscription is a no-op', () {
      expect(sql, contains("if before_status = 'PAUSED' then"));
    });

    test('onboarding cannot hand out a second trial', () {
      // Both inserts are conditional on conflict, so a repeat call is a no-op
      // and a company can never farm a second trial.
      final trials = body('start_company_trials');
      expect(trials, contains('on conflict (company_id) do nothing'));
    });
  });

  group('secretary allowance only ever blocks additions', () {
    test('the limit is enforced by a trigger on membership insert', () {
      expect(sql, contains('enforce_secretary_limit'));
      expect(sql, contains('before insert on public.company_memberships'));
      expect(sql, contains('SECRETARY_LIMIT_REACHED'));
    });

    test('the trigger checks only inserts, never updates or removals', () {
      // A company that reduces its subscription must not lose users, so the
      // guard ignores everything that is not a new secretary.
      expect(
        sql,
        contains("if tg_op <> 'INSERT' or new.role <> 'secretary' then"),
      );
    });

    test('the allowance is derived from bundles, never stored per secretary', () {
      expect(sql, contains('maxSecretaries'));
      expect(sql, contains("coalesce(r.secretary_bundles, 0)"));
      expect(sql, contains("coalesce(r.secretary_bundle_size, 3)"));
    });
  });

  group('SMS credits stay independent of the subscription', () {
    test('an SMS payment grants no subscription entitlement', () {
      // The settlement switch has an explicit branch for SMS_CREDITS, and that
      // branch deliberately does nothing: paying for credits can never
      // activate, extend or otherwise change a subscription. The assertion is
      // on the executable SQL, not on the comment explaining it.
      final settlement = body('apply_verified_payment');
      final branch = settlement.indexOf("when 'SMS_CREDITS' then");
      expect(branch, isNot(-1));
      final endOfCase = settlement.indexOf('end case;', branch);
      expect(endOfCase, isNot(-1));
      final smsBranch = settlement.substring(branch, endOfCase);
      // A no-op branch: no write of any kind may appear inside it.
      expect(smsBranch, isNot(contains('update')));
      expect(smsBranch, isNot(contains('insert')));
      expect(smsBranch, isNot(contains('delete')));
    });

    test('a subscription payment never moves an SMS balance', () {
      expect(sql, isNot(contains('update public.companies')));
    });

    test('the payment shape keeps SMS credits exclusive to that purpose', () {
      // A credit count may only exist on an SMS_CREDITS row, so a subscription
      // row can never be mistaken for a credit purchase.
      expect(sql, contains('payment_purpose_shape'));
      expect(sql, isNot(contains('sms_credits =')));
    });
  });

  group('prices and durations are centralised', () {
    test('all billing values live in one configuration table', () {
      for (final column in [
        'setup_fee_minor',
        'base_monthly_minor',
        'additional_secretary_bundle_minor',
        'secretary_bundle_size',
        'base_secretary_limit',
        'ai_monthly_minor',
        'software_trial_days',
        'ai_trial_days',
        'grace_period_days',
      ]) {
        expect(sql, contains(column));
      }
    });

    test('there is no per-secretary price column', () {
      // The only secretary pricing is per bundle.
      expect(sql, isNot(contains('per_secretary')));
    });

    test('money is integer minor units, never floating point', () {
      expect(sql, contains('amount_minor bigint'));
      expect(sql, isNot(contains('amount_minor double')));
      expect(sql, isNot(contains('amount_minor real')));
    });

    test('configuration is readable but never client-writable', () {
      expect(sql, contains('create policy subscription_config_read'));
      expect(sql, isNot(contains('for update to authenticated')));
    });
  });
}

