-- Subscriptions, entitlements, and payment transactions.
--
-- This migration adds the billing foundation only. NO payment provider is
-- integrated: the eventual provider is Hubtel, but that account is not verified
-- and its API must not be guessed. Nothing here grants an entitlement on its
-- own. An entitlement is granted ONLY by public.apply_verified_payment(), which
-- is reached exclusively from a trusted server (service role) after a real
-- provider verification or webhook has been implemented. Until then the
-- company sits in TRIAL, which the application grants for free.
--
-- Requires the multi-company schema (202609230002). Safe to re-run.
--
-- MONEY: all amounts are integer minor units ("pesewas"). GH 1 = 100 pesewas.
-- There is no floating point anywhere in the billing model, and there is
-- deliberately no per-secretary price: secretaries are sold in bundles of 3.
do $$
begin
  if to_regclass('public.company_memberships') is null then
    raise exception 'Apply and verify 202609230002_multi_company.sql before this migration';
  end if;
end
$$;

-- ---------------------------------------------------------------------------
-- 1. Central configuration
--
-- The single source of truth for every price and duration. Prices are NOT
-- duplicated in Dart: the app reads these rows so a change here changes what
-- the software charges. Only the service role may write them.
-- ---------------------------------------------------------------------------
create table if not exists public.subscription_config (
  id boolean primary key default true check (id),
  currency text not null default 'GHS',
  -- One-time onboarding charge, separate from the recurring subscription.
  setup_fee_minor bigint not null default 50000 check (setup_fee_minor >= 0),
  -- The base monthly software subscription.
  base_monthly_minor bigint not null default 20000 check (base_monthly_minor >= 0),
  -- One additional bundle of secretaries. There is no per-secretary price.
  additional_secretary_bundle_minor bigint not null default 7500 check (additional_secretary_bundle_minor >= 0),
  -- How many secretaries one bundle adds, and how many the base includes.
  secretary_bundle_size integer not null default 3 check (secretary_bundle_size > 0),
  base_secretary_limit integer not null default 3 check (base_secretary_limit >= 0),
  -- AI premium is a separate product from the software subscription.
  ai_monthly_minor bigint not null default 5000 check (ai_monthly_minor >= 0),
  -- Durations, in whole days. Each trial is tracked independently.
  software_trial_days integer not null default 30 check (software_trial_days >= 0),
  ai_trial_days integer not null default 30 check (ai_trial_days >= 0),
  grace_period_days integer not null default 7 check (grace_period_days >= 0),
  updated_at timestamptz not null default now()
);

insert into public.subscription_config (id) values (true) on conflict (id) do nothing;

-- ---------------------------------------------------------------------------
-- 2. Enumerated states
--
-- An explicit state machine rather than scattered booleans, so "expired" and
-- "paused" can never be confused for one another.
-- ---------------------------------------------------------------------------
do $$ begin
  create type public.subscription_status as enum
    ('TRIAL', 'ACTIVE', 'GRACE_PERIOD', 'EXPIRED', 'PAUSED');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.ai_entitlement_status as enum
    ('TRIAL', 'ACTIVE', 'EXPIRED', 'NONE');
exception when duplicate_object then null;
end $$;

-- Payment purposes stay deliberately separate. SMS credits are NOT part of the
-- software subscription and are never settled through this table's subscription
-- path.
do $$ begin
  create type public.payment_purpose as enum
    ('SETUP_FEE', 'SOFTWARE_SUBSCRIPTION', 'SECRETARY_BUNDLE', 'AI_SUBSCRIPTION', 'SMS_CREDITS');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.payment_status as enum
    ('PENDING', 'PROCESSING', 'SUCCESSFUL', 'FAILED', 'CANCELLED', 'EXPIRED', 'REFUNDED');
exception when duplicate_object then null;
end $$;

-- ---------------------------------------------------------------------------
-- 3. Company subscription
--
-- One row per company. Creating a row is NOT itself a charge: TRIAL is free
-- and is granted on onboarding.
-- ---------------------------------------------------------------------------
create table if not exists public.company_subscriptions (
  company_id uuid primary key references public.companies(id) on delete cascade,
  status public.subscription_status not null default 'TRIAL',
  -- Software trial. Set once at onboarding and NEVER reset by a pause or a
  -- reactivation, so a company cannot farm a second trial.
  trial_started_at timestamptz,
  trial_ends_at timestamptz,
  trial_consumed boolean not null default false,
  -- The paid period. Null while the company has never paid.
  current_period_start timestamptz,
  current_period_end timestamptz,
  -- Set when the paid period lapses; runs to current_period_end + grace days.
  grace_period_start timestamptz,
  grace_period_end timestamptz,
  -- How many additional secretary bundles have been PURCHASED. The secretary
  -- allowance is base + (bundles * bundle_size).
  secretary_bundles integer not null default 0 check (secretary_bundles >= 0),
  -- One-time setup fee state, tracked apart from the recurring subscription.
  setup_fee_status public.payment_status not null default 'PENDING',
  setup_fee_paid_at timestamptz,
  -- Pause is explicit. Pausing keeps every row, user, and setting in place.
  paused_at timestamptz,
  pause_reason text,
  -- Counter for the audit trail, not for authorization.
  activation_count integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  -- A trial or paid period must have a start whenever it has an end.
  constraint subscription_period_paired check (
    (current_period_start is null) = (current_period_end is null)
    ),
  constraint subscription_trial_paired check (
    (trial_started_at is null) = (trial_ends_at is null)
  ),
  -- A company is never marked consumed unless it actually started a trial.
  constraint subscription_trial_consumed check (not trial_consumed or trial_started_at is not null)
);

create index if not exists company_subscriptions_status_idx
  on public.company_subscriptions (status);
-- Expiry sweeps look up companies whose grace period has run out.
create index if not exists company_subscriptions_grace_idx
  on public.company_subscriptions (grace_period_end)
  where grace_period_end is not null;

-- ---------------------------------------------------------------------------
-- 4. AI premium entitlement
--
-- Deliberately a SEPARATE table with its own trial. The AI trial is tracked
-- independently of the software trial, so it never resets when the software
-- subscription is renewed, paused, or when a secretary is added.
-- ---------------------------------------------------------------------------
create table if not exists public.company_ai_entitlements (
  company_id uuid primary key references public.companies(id) on delete cascade,
  status public.ai_entitlement_status not null default 'NONE',
  -- Set once, at onboarding, from subscription_config.ai_trial_days. Never reset.
  trial_started_at timestamptz,
  trial_ends_at timestamptz,
  trial_consumed boolean not null default false,
  -- The paid AI period, independent of the software subscription's own period.
  current_period_start timestamptz,
  current_period_end timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  -- A trial has a start whenever it has an end.
  constraint ai_trial_paired check ((trial_started_at is null) = (trial_ends_at is null))
);

-- ---------------------------------------------------------------------------
-- 5. Payment transactions
--
-- An auditable record of every payment intent and its settlement. Creating a
-- row here NEVER grants an entitlement: only public.apply_verified_payment()
-- does, and it is idempotent on provider_reference.
-- ---------------------------------------------------------------------------
create table if not exists public.payment_transactions (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  purpose public.payment_purpose not null,
  -- Minor units. For SMS_CREDITS this is the money paid, NOT a credit count:
  -- the credit balance is only ever moved by the existing secure credit path.
  amount_minor bigint not null check (amount_minor >= 0),
  currency text not null default 'GHS',
  provider text not null,
  -- The provider's own transaction id. UNIQUE, so a replayed callback or a
  -- double-submitted verification can never settle the same payment twice.
  provider_reference text,
  status public.payment_status not null default 'PENDING',
  -- For SECRETARY_BUNDLE: how many bundles this payment buys.
  quantity integer not null default 1 check (quantity > 0),
  -- For SMS_CREDITS: how many credits this payment buys. NULL for every other
  -- purpose, so an SMS purchase can never be mistaken for a subscription.
  sms_credits integer check (sms_credits is null or sms_credits > 0),
  -- Free-form provider payload, retained for audit. Never trusted for logic.
  metadata jsonb not null default '{}'::jsonb,
  created_by_user_id uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  -- Set the moment a payment is confirmed SUCCESSFUL by the server.
  verified_at timestamptz,
  -- Guards the idempotent settlement: a row may only move to SUCCESSFUL once.
  settled_at timestamptz,

  -- The two identity rules that make settlement unambiguous.
  constraint payment_purpose_shape check (
    (purpose = 'SMS_CREDITS' and sms_credits is not null) or
    (purpose <> 'SMS_CREDITS' and sms_credits is null)
  ),
  constraint payment_verified_needs_reference check (
    status <> 'SUCCESSFUL' or provider_reference is not null
  )
);

-- A provider may only ever issue one reference for one payment. This is the
-- database-level half of the idempotency guarantee.
create unique index if not exists payment_provider_reference_key
  on public.payment_transactions (provider, provider_reference)
  where provider_reference is not null;
create index if not exists payment_transactions_company_idx
  on public.payment_transactions (company_id, created_at desc);
create index if not exists payment_transactions_status_idx
  on public.payment_transactions (status);

-- ---------------------------------------------------------------------------
-- 6. Subscription event log
--
-- Append-only audit of every state change. Written by the functions below, so a
-- state change always leaves a record behind.
-- ---------------------------------------------------------------------------
create table if not exists public.subscription_events (
  id bigint generated always as identity primary key,
  company_id uuid not null references public.companies(id) on delete cascade,
  event_type text not null,
  from_status public.subscription_status,
  to_status public.subscription_status,
  -- Why the change happened: trial started, payment verified, paused, expired.
  reason text,
  -- Optional link to the payment that caused the change.
  payment_transaction_id uuid references public.payment_transactions(id) on delete set null,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists subscription_events_company_idx
  on public.subscription_events (company_id, id desc);

-- ---------------------------------------------------------------------------
-- 7. Append-only event log helper
--
-- Append-only by construction: there is no update or delete path for this
-- function, so the audit trail cannot be rewritten.
-- ---------------------------------------------------------------------------
create or replace function public.record_subscription_event(
  target_company uuid,
  event_type text,
  from_status public.subscription_status,
  to_status public.subscription_status,
  reason text,
  payment_id uuid,
  details jsonb
)
returns void language sql security definer set search_path = public
as $$
  insert into public.subscription_events
    (company_id, event_type, from_status, to_status, reason,
     payment_transaction_id, details)
  values
    (target_company, event_type, from_status, to_status, reason, payment_id, details);
$$;

-- ---------------------------------------------------------------------------
-- 8. Onboarding: grant the free trials
--
-- Safe to call again: a company that already has a subscription keeps its
-- existing trial, so a repeat call can never hand out a second trial. The AI
-- trial is written as its own row so it is tracked independently of the
-- software trial, and neither is reset by a later pause or reactivation.
-- ---------------------------------------------------------------------------
create or replace function public.start_company_trials(target_company uuid)
returns void language plpgsql security definer set search_path = public
as $$
declare
  cfg public.subscription_config%rowtype;
  now_ts timestamptz := now();
  created_company boolean := false;
begin
  select * into cfg from public.subscription_config where id;
  if not found then
    raise exception 'subscription_config is not initialised';
  end if;

  -- ON CONFLICT DO NOTHING makes this the single place a trial is ever issued.
  -- A company that already has one keeps it, which is what stops a reinstall,
  -- a re-login, a new device, a renewal, or a pause/reactivation cycle from
  -- handing out a second trial.
  insert into public.company_subscriptions
    (company_id, status, trial_started_at, trial_ends_at, trial_consumed)
  values
    (target_company, 'TRIAL', now_ts,
     now_ts + make_interval(days => cfg.software_trial_days), true)
  on conflict (company_id) do nothing;

  created_company := found;

  insert into public.company_ai_entitlements
    (company_id, status, trial_started_at, trial_ends_at, trial_consumed)
  values
    (target_company, 'TRIAL', now_ts,
     now_ts + make_interval(days => cfg.ai_trial_days), true)
  on conflict (company_id) do nothing;

  -- The audit event is written only when a trial was actually created, so a
  -- repeat call leaves no misleading second "trial started" record either.
  if not created_company then
    return;
  end if;

  perform public.record_subscription_event(
    target_company, 'trial_started', null, 'TRIAL',
    'Free software trial started at onboarding', null,
    jsonb_build_object('software_trial_days', cfg.software_trial_days,
                       'ai_trial_days', cfg.ai_trial_days));
end;
$$;

-- ---------------------------------------------------------------------------
-- 8a. Automatic trial creation
--
-- This is what makes the 30-day trial real. public.handle_new_user() creates a
-- company during sign-up, and until this trigger existed nothing called
-- start_company_trials(): a brand new company would have had NO subscription
-- row at all. It would have read as a trial only by accident, via the
-- projection's fallback, with no stored trial start or end to reason about.
--
-- A PostgreSQL trigger function must RETURNS TRIGGER and take no arguments, so
-- it cannot be public.start_company_trials() itself (that one returns void and
-- takes a uuid). This dedicated wrapper does the calling, and it is attached
-- AFTER INSERT so a new company always has a row id by the time it runs.
--
-- The trigger is attached to the TABLE, not to the sign-up function, so every
-- path that creates a company is covered: the auth trigger, a manual insert, or
-- any future provisioning route. Nothing else has to remember to call it.
--
-- A trial is still issued exactly ONCE, because start_company_trials() uses
-- ON CONFLICT DO NOTHING on both tables. That is why none of the following can
-- produce a second trial:
--
--   * reinstalling the app      -- no new company row, so no trigger fires
--   * logging out and back in   -- no new company row, so no trigger fires
--   * changing device           -- no new company row, so no trigger fires
--   * adding/removing users     -- touches memberships, not companies
--   * renewing the subscription -- apply_verified_payment never writes a trial
--   * pause / reactivation      -- resume_company_subscription never writes one
--
-- AFTER INSERT also means an UPDATE of an existing company never fires it, so
-- a company can never be handed a second trial by editing its own row.
--
-- Eligibility is decided entirely by the existence of the company row, which
-- only the database can create. No client state can grant or restart a trial.
-- ---------------------------------------------------------------------------
create or replace function public.grant_company_trial_on_insert()
returns trigger language plpgsql security definer set search_path = public
as $$
begin
  perform public.start_company_trials(new.id);
  return new;
end;
$$;

drop trigger if exists company_trial_onboarding on public.companies;
create trigger company_trial_onboarding
  after insert on public.companies
  for each row execute function public.grant_company_trial_on_insert();

-- ---------------------------------------------------------------------------
-- 9. The entitlement projection
--
-- The single place that answers "what may this company do?". Every consumer,
-- including the Flutter app and the Edge Functions, reads this rather than
-- re-deriving the rules, so the trial, grace and pause semantics cannot drift
-- between the client and the server.
--
-- The secretary allowance is derived here, never stored: base + bundles * size.
--
-- SELF-CORRECTING EXPIRY. The status column is NOT trusted on its own. If the
-- stored status still says ACTIVE but the paid period has ended, this function
-- derives the real state from the dates and reports GRACE_PERIOD or EXPIRED
-- accordingly. That matters because the sweep that persists those statuses
-- (public.sweep_expired_subscriptions) is a best-effort housekeeping job, not
-- the security boundary: it only runs when something asks for a status. Without
-- this derivation, a company whose expiry had passed but whose sweep had not yet
-- run would keep admin access until the next sweep -- an open-ended hole that a
-- company with no traffic to the billing screen would never close.
--
-- The sweep therefore still exists, but it is now an optimisation and an audit
-- trail, not the thing that decides access. Sweep-then-read is strictly better
-- for reporting (it persists the transition and writes an event), and this
-- function makes the read correct either way.
-- ---------------------------------------------------------------------------
create or replace function public.company_entitlements(target_company uuid)
returns jsonb language sql stable security definer set search_path = public
as $$
  with cfg as (select * from public.subscription_config where id),
  sub as (select * from public.company_subscriptions where company_id = target_company),
  ai as (select * from public.company_ai_entitlements where company_id = target_company),
  resolved as (
    select
      coalesce(sub.status, 'TRIAL'::public.subscription_status) as stored_status,
      sub.current_period_start, sub.current_period_end,
      sub.grace_period_end, sub.trial_ends_at, sub.trial_consumed,
      sub.secretary_bundles, sub.setup_fee_status, sub.paused_at,
      coalesce(ai.status, 'NONE'::public.ai_entitlement_status) as ai_status,
      ai.trial_ends_at as ai_trial_ends_at,
      ai.current_period_end as ai_period_end,
      cfg.*
    from cfg left join sub on true left join ai on true
  ),
  effective as (
    select
      r.*,
      -- When admin access finally stops, derived from the DATES rather than
      -- read from the status column, so a stale status cannot keep a company
      -- open. A grace period the sweep already recorded is preferred, so the
      -- derived value always agrees with the persisted one.
      case
        when r.stored_status = 'TRIAL' and r.trial_ends_at is not null
              and now() >= r.trial_ends_at
          then coalesce(
                 r.grace_period_end,
                 r.trial_ends_at
                   + make_interval(days => coalesce(r.grace_period_days, 7)))
        when r.stored_status = 'ACTIVE' and r.current_period_end is not null
              and now() >= r.current_period_end
          then coalesce(
                 r.grace_period_end,
                 r.current_period_end
                   + make_interval(days => coalesce(r.grace_period_days, 7)))
        else r.grace_period_end
      end as effective_grace_end
    from resolved r
  ),
  final_state as (
    select
      e.*,
      -- The state this company is REALLY in right now. Once it reaches EXPIRED
      -- the derived grace end is still in the past, so it stays EXPIRED: the
      -- transition is monotonic and cannot bounce back on its own.
      case
        when e.stored_status = 'PAUSED' then 'PAUSED'::public.subscription_status
        when e.stored_status in ('TRIAL', 'ACTIVE', 'GRACE_PERIOD')
              and e.effective_grace_end is not null
              and now() >= e.effective_grace_end
          then 'EXPIRED'::public.subscription_status
        when (e.stored_status = 'TRIAL' and e.trial_ends_at is not null
                and now() >= e.trial_ends_at)
          or (e.stored_status = 'ACTIVE' and e.current_period_end is not null
                and now() >= e.current_period_end)
          then 'GRACE_PERIOD'::public.subscription_status
        else e.stored_status
      end as sub_status
    from effective e
  )
  select jsonb_build_object(
    'companyId', target_company,
    -- The EFFECTIVE status, not the stored one. A company that has run out of
    -- time reports EXPIRED here immediately, whether or not the sweep has run.
    'status', r.sub_status,
    'isInTrial',
      r.sub_status = 'TRIAL' and r.trial_ends_at is not null
      and now() < r.trial_ends_at,
    'trialEndsAt', r.trial_ends_at,
    'trialConsumed', coalesce(r.trial_consumed, false),
    'currentPeriodStart', r.current_period_start,
    'currentPeriodEnd', r.current_period_end,
    'gracePeriodEnd', r.effective_grace_end,
    'isInGracePeriod',
      r.sub_status = 'GRACE_PERIOD' and r.effective_grace_end is not null
      and now() < r.effective_grace_end,
    'isPaused', r.sub_status = 'PAUSED',
    'pausedAt', r.paused_at,

    -- Admin access is the thing the subscription gates. Because r.sub_status is
    -- already the date-corrected state, this cannot stay true past the end of
    -- the trial, the paid period, or the grace window, even if the sweep has
    -- not run. A secretary's operational work never depends on it, so expiry
    -- still cannot stop a company recording deliveries.
    'canAccessAdmin', r.sub_status in ('TRIAL', 'ACTIVE', 'GRACE_PERIOD'),
    'hasActiveSoftwareSubscription', r.sub_status = 'ACTIVE',
    -- A paused company keeps all of its data and users, but the software is
    -- not running for it until it reactivates.
    'canRecordAsSecretary', r.sub_status <> 'PAUSED',

    'secretaryBundles', coalesce(r.secretary_bundles, 0),
    'maxSecretaries',
      coalesce(r.base_secretary_limit, 3)
      + coalesce(r.secretary_bundles, 0) * coalesce(r.secretary_bundle_size, 3),
    'secretaryBundleSize', r.secretary_bundle_size,
    'setupFeeStatus', coalesce(r.setup_fee_status, 'PENDING'::public.payment_status),

    -- AI is separate from the software subscription in every way, including
    -- its own trial and its own period.
    'aiStatus',
      case
        when r.ai_period_end is not null and now() < r.ai_period_end
          then 'ACTIVE'::public.ai_entitlement_status
        when r.ai_status = 'ACTIVE' and r.ai_period_end is not null
          and now() >= r.ai_period_end
          then 'EXPIRED'::public.ai_entitlement_status
        else r.ai_status
      end,
    'aiTrialEndsAt', r.ai_trial_ends_at,
    'aiPeriodEnd', r.ai_period_end,
    'canUseAI',
      r.sub_status <> 'PAUSED'
      and (
        (r.ai_status = 'TRIAL' and r.ai_trial_ends_at is not null
          and now() < r.ai_trial_ends_at)
        or (r.ai_period_end is not null and now() < r.ai_period_end)
      ),

    'currency', r.currency,
    'setupFeeMinor', r.setup_fee_minor,
    'baseMonthlyMinor', r.base_monthly_minor,
    'additionalSecretaryBundleMinor', r.additional_secretary_bundle_minor,
    'aiMonthlyMinor', r.ai_monthly_minor,
    'softwareTrialDays', r.software_trial_days,
    'aiTrialDays', r.ai_trial_days,
    'gracePeriodDays', r.grace_period_days
  )
  from final_state r;
$$;

-- ---------------------------------------------------------------------------
-- 10. Settle a verified payment
--
-- The ONLY path that can grant an entitlement. It is deliberately unreachable
-- from a client: the function refuses to run unless it is already executing
-- with the service role, so Flutter cannot call it and an authenticated end
-- user calling it directly does nothing.
--
-- IDEMPOTENCY: the row is locked FOR UPDATE and is moved to SUCCESSFUL only if
-- it is not already settled. A replayed webhook or a double-submitted
-- verification therefore returns the first result and grants nothing extra. The
-- unique (provider, provider_reference) index is the second line of defence.
-- ---------------------------------------------------------------------------
create or replace function public.apply_verified_payment(target_payment uuid)
returns jsonb language plpgsql security definer set search_path = public
as $$
declare
  pay public.payment_transactions%rowtype;
  cfg public.subscription_config%rowtype;
  sub public.company_subscriptions%rowtype;
  now_ts timestamptz := now();
  new_period_end timestamptz;
begin
  -- Only a trusted server may settle. A client cannot promote itself.
  if coalesce((select auth.jwt() ->> 'role'), '') <> 'service_role' then
    raise exception 'Payments are settled by a trusted server only';
  end if;

  select * into pay from public.payment_transactions where id = target_payment
    for update;
  if not found then
    raise exception 'Unknown payment transaction';
  end if;

  -- The replay case: this payment already settled, so it must not grant a
  -- second subscription, bundle, AI period or credit.
  if pay.status = 'SUCCESSFUL' then
    return jsonb_build_object(
      'applied', false, 'idempotent', true, 'status', pay.status,
      'companyId', pay.company_id, 'purpose', pay.purpose);
  end if;

  -- Only a real provider confirmation settles a payment. A created intent, a
  -- pending row, or a client assertion is never enough.
  if pay.provider_reference is null or pay.provider_reference = '' then
    raise exception 'A payment cannot be settled without a provider reference';
  end if;

  select * into cfg from public.subscription_config where id;
  select * into sub from public.company_subscriptions where company_id = pay.company_id
    for update;

  -- A company with no subscription row (created before this migration) gets one
  -- now, so a payment always has a state to apply to.
  if not found then
    insert into public.company_subscriptions (company_id, status)
      values (pay.company_id, 'TRIAL');
    select * into sub from public.company_subscriptions
      where company_id = pay.company_id for update;
  end if;

  -- The one place a paid month is computed. A renewal extends from the later of
  -- now and the current period end, so a company is never charged twice for a
  -- period it already owns.
  new_period_end := greatest(coalesce(sub.current_period_end, now_ts), now_ts)
    + interval '1 month';

  update public.payment_transactions
     set status = 'SUCCESSFUL',
         verified_at = now_ts,
         settled_at = now_ts,
         metadata = metadata || jsonb_build_object('settledBy', 'apply_verified_payment')
   where id = pay.id;


  -- Each purpose grants its own entitlement and nothing else. In particular a
  -- subscription payment never touches SMS credits, and an SMS purchase never
  -- grants a subscription.
  case pay.purpose
    when 'SETUP_FEE' then
      -- One-time only. A replayed setup fee cannot reset a paid subscription
      -- back to a trial, because it touches only the setup fee columns.
      update public.company_subscriptions
         set setup_fee_status = 'SUCCESSFUL',
             setup_fee_paid_at = coalesce(setup_fee_paid_at, now_ts),
             updated_at = now_ts
       where company_id = pay.company_id;

    when 'SOFTWARE_SUBSCRIPTION' then
      update public.company_subscriptions
         set status = 'ACTIVE',
             current_period_start = coalesce(sub.current_period_start, now_ts),
             current_period_end = new_period_end,
             -- Paying clears any grace period that was running, and un-pauses
             -- a seasonal company that reactivated.
             grace_period_start = null,
             grace_period_end = null,
             paused_at = null,
             activation_count = sub.activation_count + 1,
             updated_at = now_ts
       where company_id = pay.company_id;

    when 'SECRETARY_BUNDLE' then
      -- A bundle purchase only ever ADDS allowance. It never lowers it, and it
      -- never touches the subscription period.
      update public.company_subscriptions
         set secretary_bundles = secretary_bundles + pay.quantity,
             updated_at = now_ts
       where company_id = pay.company_id;

    when 'AI_SUBSCRIPTION' then
      -- AI has its own period, independent of the software subscription.
      insert into public.company_ai_entitlements
        (company_id, status, current_period_start, current_period_end)
      values (pay.company_id, 'ACTIVE', now_ts, now_ts + interval '1 month')
      on conflict (company_id) do update
        set status = 'ACTIVE',
            current_period_start = excluded.current_period_start,
            current_period_end = excluded.current_period_end,
            updated_at = now_ts;

    when 'SMS_CREDITS' then
      -- Intentionally NOT settled here.
      --
      -- SMS credits keep their own balance and their own append-only ledger,
      -- moved only by the existing secure credit functions. A subscription
      -- expiry must never touch an SMS balance, and an SMS purchase must never
      -- grant a subscription. The credit top-up is applied by the dedicated SMS
      -- credit path once a real provider confirms the payment, which keeps the
      -- two systems completely independent.
      null;
  end case;

  perform public.record_subscription_event(
    pay.company_id, 'payment_settled', sub.status,
    (select status from public.company_subscriptions where company_id = pay.company_id),
    'Verified payment applied', pay.id,
    jsonb_build_object('purpose', pay.purpose, 'amountMinor', pay.amount_minor,
                       'quantity', pay.quantity));

  return jsonb_build_object(
    'applied', true, 'idempotent', false, 'status', 'SUCCESSFUL',
    'companyId', pay.company_id, 'purpose', pay.purpose,
    'entitlements', public.company_entitlements(pay.company_id));
end;
$$;

-- ---------------------------------------------------------------------------
-- 11. Secretary allowance enforcement
--
-- Adding a secretary beyond the company's paid allowance is refused. This check
-- is server-side and lives here, so it applies no matter which client or tool
-- attempts the insert.
--
-- It only ever blocks ADDITIONS. Reducing a subscription never deletes or
-- deactivates an existing secretary: the company simply becomes over its
-- allowance, which the billing screen reports so the admin can act.
-- ---------------------------------------------------------------------------
create or replace function public.enforce_secretary_limit()
returns trigger language plpgsql security definer set search_path = public
as $$
declare
  allowed integer;
  current_count integer;
  bundle_size integer;
begin
  -- Only an ADDED secretary membership is checked. Updates and removals are
  -- never blocked, so reducing a subscription cannot cascade into losing users.
  if tg_op <> 'INSERT' or new.role <> 'secretary' then
    return new;
  end if;

  -- Serialise concurrent secretary additions for this company.
  --
  -- Without this, two admins adding a secretary at the same time would each
  -- count the same pre-existing secretaries, each conclude there was room, and
  -- both be inserted -- quietly exceeding the paid allowance. Taking a row lock
  -- on the company's subscription row makes the check-and-insert atomic: the
  -- second transaction blocks here until the first commits, then counts the
  -- row the first one added and is correctly refused.
  --
  -- The company row is locked as well because it always exists, giving a stable
  -- per-company mutex even for a company that somehow has no subscription row
  -- yet. The lock order (companies, then company_subscriptions) is consistent
  -- everywhere, so this cannot deadlock against apply_verified_payment().
  -- Lock the company row first. It always exists, and it is a stable
  -- per-company mutex. Lock order is always companies -> company_subscriptions.
  perform 1
    from public.companies c
   where c.id = new.company_id
   for update;

  -- Lock the subscription row separately because it is optional.
  -- If no subscription row exists, this locks nothing; the company row
  -- above has already serialized the check.
  perform 1
    from public.company_subscriptions s
   where s.company_id = new.company_id
   for update;

  -- Read the allowance only after the lock is held, so it cannot change
  -- underneath this check.
  select (public.company_entitlements(new.company_id) ->> 'maxSecretaries')::integer
    into allowed;
  if allowed is null then
    allowed := 3;
  end if;

  select count(*) into current_count
    from public.company_memberships
   where company_id = new.company_id
     and role = 'secretary'
     and is_active;

  if current_count >= allowed then
    select secretary_bundle_size into bundle_size
      from public.subscription_config where id;
    raise exception 'SECRETARY_LIMIT_REACHED:This company can have up to % secretaries. Buy an additional bundle of % to add more.', allowed, coalesce(bundle_size, 3)
      using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

drop trigger if exists secretary_limit_guard on public.company_memberships;
create trigger secretary_limit_guard
  before insert on public.company_memberships
  for each row execute function public.enforce_secretary_limit();

-- ---------------------------------------------------------------------------
-- 12. Expiry sweep
--
-- Moves TRIAL -> GRACE_PERIOD -> EXPIRED as the dates pass. It only ever changes
-- the subscription STATUS. It deletes nothing: no company row, user, delivery,
-- supplier, product, receipt, SMS record or setting is ever removed, so a
-- renewal restores full access to exactly the data the company already had.
--
-- Safe to run repeatedly; it only advances companies that are actually due.
-- ---------------------------------------------------------------------------
create or replace function public.sweep_expired_subscriptions()
returns integer language plpgsql security definer set search_path = public
as $$
declare
  grace_cfg integer;
  moved integer := 0;
  rec record;
begin
  select grace_period_days into grace_cfg from public.subscription_config where id;
  grace_cfg := coalesce(grace_cfg, 7);

  -- A trial that has run out gets the same courtesy grace period before the
  -- admin side is locked.
  for rec in
    update public.company_subscriptions s
       set status = 'GRACE_PERIOD',
           grace_period_start = s.trial_ends_at,
           grace_period_end = coalesce(s.trial_ends_at, now())
             + make_interval(days => grace_cfg),
           updated_at = now()
     where s.status = 'TRIAL'
       and s.trial_ends_at is not null
       and now() >= s.trial_ends_at
    returning s.company_id
  loop
    perform public.record_subscription_event(
      rec.company_id, 'trial_ended', 'TRIAL', 'GRACE_PERIOD',
      'Software trial ended', null, '{}'::jsonb);
    moved := moved + 1;
  end loop;

  -- A paid period that has run out enters the grace period.
  for rec in
    update public.company_subscriptions s
       set status = 'GRACE_PERIOD',
           grace_period_start = s.current_period_end,
           grace_period_end = coalesce(s.current_period_end, now())
             + make_interval(days => grace_cfg),
           updated_at = now()
     where s.status = 'ACTIVE'
       and s.current_period_end is not null
       and now() >= s.current_period_end
    returning s.company_id
  loop
    perform public.record_subscription_event(
      rec.company_id, 'subscription_ended', 'ACTIVE', 'GRACE_PERIOD',
      'Subscription period ended', null, '{}'::jsonb);
    moved := moved + 1;
  end loop;

  -- Grace period over: the admin side locks. No data is touched.
  for rec in
    update public.company_subscriptions s
       set status = 'EXPIRED', updated_at = now()
     where s.status = 'GRACE_PERIOD'
       and s.grace_period_end is not null
       and now() >= s.grace_period_end
    returning s.company_id
  loop
    perform public.record_subscription_event(
      rec.company_id, 'grace_ended', 'GRACE_PERIOD', 'EXPIRED',
      'Grace period ended; admin access locked', null, '{}'::jsonb);
    moved := moved + 1;
  end loop;

  -- An AI period or trial that has run out becomes EXPIRED, so the AI function
  -- can stop calling the provider and saving cost.
  update public.company_ai_entitlements a
     set status = 'EXPIRED', updated_at = now()
   where a.status = 'ACTIVE'
     and a.current_period_end is not null
     and now() >= a.current_period_end;

  update public.company_ai_entitlements a
     set status = 'EXPIRED', updated_at = now()
   where a.status = 'TRIAL'
     and a.trial_ends_at is not null
     and now() >= a.trial_ends_at;

  return moved;
end;
$$;


-- ---------------------------------------------------------------------------
-- 13. Pause and reactivate (seasonal businesses)
--
-- Pausing preserves EVERYTHING: users, deliveries, weights, suppliers,
-- products, reports, receipts, SMS history, branding and trial history. It sets
-- an explicit status so the software is not treated as running, and it is a
-- first-class concept rather than an inferred one.
-- ---------------------------------------------------------------------------
create or replace function public.pause_company_subscription(target_company uuid, why text)
returns jsonb language plpgsql security definer set search_path = public
as $$
declare
  before_status public.subscription_status;
begin
  -- A trusted server only: the caller has already been proven to be an
  -- owner/admin of this company by the Edge Function.
  if coalesce((select auth.jwt() ->> 'role'), '') <> 'service_role' then
    raise exception 'Subscriptions are managed by a trusted server only';
  end if;

  select status into before_status from public.company_subscriptions
    where company_id = target_company for update;
  if before_status is null then
    raise exception 'Unknown company subscription';
  end if;
  if before_status = 'PAUSED' then
    -- Pausing an already-paused subscription is a no-op, not an error, so a
    -- repeated tap can never corrupt the state.
    return public.company_entitlements(target_company);
  end if;

  -- No row is deleted or deactivated here. Everything the company owns stays
  -- exactly as it is.
  update public.company_subscriptions
     set status = 'PAUSED', paused_at = now(), pause_reason = why, updated_at = now()
   where company_id = target_company;

  perform public.record_subscription_event(
    target_company, 'paused', before_status, 'PAUSED', why, null, '{}'::jsonb);

  return public.company_entitlements(target_company);
end;
$$;

-- ---------------------------------------------------------------------------
-- 14. Reactivate
--
-- Restores whatever the company actually had, and does NOT grant a new trial: a
-- seasonal company that pauses and returns is a returning customer, not a new
-- one, so its trial history stays exactly as it was. trial_started_at and
-- trial_ends_at are never written here.
-- ---------------------------------------------------------------------------
create or replace function public.resume_company_subscription(target_company uuid)
returns jsonb language plpgsql security definer set search_path = public
as $$
declare
  before_status public.subscription_status;
  restored public.subscription_status;
  cfg public.subscription_config%rowtype;
  now_ts timestamptz := now();
begin
  if coalesce((select auth.jwt() ->> 'role'), '') <> 'service_role' then
    raise exception 'Subscriptions are managed by a trusted server only';
  end if;

  select * into cfg from public.subscription_config where id;
  select status into before_status from public.company_subscriptions
    where company_id = target_company for update;
  if before_status is null or before_status <> 'PAUSED' then
    raise exception 'This subscription is not paused';
  end if;

  -- Returning a seasonal company restores whatever it had. A still-running
  -- period is picked back up untouched; a lapsed one returns to its grace
  -- period so the admin gets the same warning they would otherwise have seen.
  restored := case
    when exists (
      select 1 from public.company_subscriptions
       where company_id = target_company
         and current_period_end is not null
         and now() < current_period_end
    ) then 'ACTIVE'::public.subscription_status
    when exists (
      select 1 from public.company_subscriptions
       where company_id = target_company
         and trial_ends_at is not null
         and now() < trial_ends_at
    ) then 'TRIAL'::public.subscription_status
    when exists (
      select 1 from public.company_subscriptions
       where company_id = target_company
         and grace_period_end is not null
         and now() < grace_period_end
    ) then 'GRACE_PERIOD'::public.subscription_status
    -- The period fully lapsed while paused, so the company returns to the
    -- documented grace window rather than to a new trial.
    else 'GRACE_PERIOD'::public.subscription_status
  end;

  update public.company_subscriptions
     set status = restored,
         paused_at = null,
         pause_reason = null,
         -- Re-entering grace after a lapse restarts the window from today.
         grace_period_start = case when restored = 'GRACE_PERIOD' then now_ts else null end,
         grace_period_end = case when restored = 'GRACE_PERIOD'
                                then now_ts + make_interval(days => cfg.grace_period_days)
                                else null end,
         activation_count = activation_count + 1,
         updated_at = now_ts
   where company_id = target_company;

  perform public.record_subscription_event(
    target_company, 'resumed', before_status, restored,
    'Subscription reactivated', null, '{}'::jsonb);

  return public.company_entitlements(target_company);
end;
$$;


-- ---------------------------------------------------------------------------
-- 15. Row Level Security
--
-- The billing tables follow the same company-membership pattern the rest of the
-- schema already uses. There is deliberately NO universal or platform-wide
-- role: a company admin can only ever read their own company's rows, and only
-- an owner/admin of that company can see them. Cross-company platform
-- management is intended to be added later as its own audited surface, not as a
-- bypass here.
-- ---------------------------------------------------------------------------
alter table public.subscription_config enable row level security;
alter table public.company_subscriptions enable row level security;
alter table public.company_ai_entitlements enable row level security;
alter table public.payment_transactions enable row level security;
alter table public.subscription_events enable row level security;

-- Config is world-readable so the app can show prices and durations, but it is
-- NOT writable by any client: only the service role may change pricing.
grant select on public.subscription_config to authenticated, anon;
drop policy if exists subscription_config_read on public.subscription_config;
create policy subscription_config_read on public.subscription_config
  for select to authenticated, anon using (true);

-- Billing is sensitive, so only an owner/admin of that company may read it. A
-- secretary is deliberately excluded: they must not be able to read or infer
-- the company's billing position.
grant select on public.company_subscriptions, public.company_ai_entitlements,
  public.payment_transactions, public.subscription_events to authenticated;

drop policy if exists subscriptions_admin_read on public.company_subscriptions;
create policy subscriptions_admin_read on public.company_subscriptions
  for select to authenticated
  using (public.has_company_role(company_id, array['owner','admin']::public.company_role[]));

drop policy if exists ai_entitlements_admin_read on public.company_ai_entitlements;
create policy ai_entitlements_admin_read on public.company_ai_entitlements
  for select to authenticated
  using (public.has_company_role(company_id, array['owner','admin']::public.company_role[]));

drop policy if exists payments_admin_read on public.payment_transactions;
create policy payments_admin_read on public.payment_transactions
  for select to authenticated
  using (public.has_company_role(company_id, array['owner','admin']::public.company_role[]));

drop policy if exists subscription_events_admin_read on public.subscription_events;
create policy subscription_events_admin_read on public.subscription_events
  for select to authenticated
  using (public.has_company_role(company_id, array['owner','admin']::public.company_role[]));

-- No client-writable policy is created for any of these tables, so the
-- authenticated role cannot insert, update or delete a subscription, an
-- entitlement, a payment or an event. Every state change goes through the
-- security-definer functions above, which the service role alone can call.
--
-- Billing is read by the app through the `subscription-status` Edge Function,
-- which uses the service role and re-checks membership itself. There is
-- deliberately no member-wide SELECT policy here: a secretary must not be able
-- to read their company's billing position, so `company_subscriptions` stays
-- owner/admin-only.

create index if not exists company_ai_entitlements_status_idx
  on public.company_ai_entitlements (status);

-- ---------------------------------------------------------------------------
-- 16. Onboard existing companies
--
-- A company created before this migration has no trial row, because the
-- company_trial_onboarding trigger did not exist yet. The inserts below give
-- every such company its free software and AI trials exactly once.
--
-- ON CONFLICT DO NOTHING makes a re-run harmless: a company that already has a
-- row keeps its existing trial, so re-applying this migration can never reset
-- or hand out a second trial.
--
-- New companies do not need this section: the company_trial_onboarding trigger
-- on public.companies grants their trial automatically on insert.
-- ---------------------------------------------------------------------------
insert into public.company_subscriptions
  (company_id, status, trial_started_at, trial_ends_at, trial_consumed)
select
  c.id,
  'TRIAL',
  now(),
  now() + make_interval(days => coalesce((select software_trial_days from public.subscription_config where id), 30)),
  true
from public.companies c
on conflict (company_id) do nothing;

insert into public.company_ai_entitlements
  (company_id, status, trial_started_at, trial_ends_at, trial_consumed)
select
  c.id,
  'TRIAL',
  now(),
  now() + make_interval(days => coalesce((select ai_trial_days from public.subscription_config where id), 30)),
  true
from public.companies c
on conflict (company_id) do nothing;
