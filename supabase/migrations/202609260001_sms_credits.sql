-- SMS credit balance, append-only ledger, and credit reservations.
--
-- Every company starts with 0 credits. Credits only ever increase through a
-- verified payment (no payment provider is integrated yet) or an automatic
-- refund of a failed SMS submission. No role, including owner and admin, can
-- write a balance by hand.
--
-- Requires the multi-company schema (202609230002) and the company branding
-- migration (202609240001). Safe to re-run.
--
-- MONEY: all amounts are integer minor units ("pesewas"). One SMS credit is
-- exactly 5 pesewas (GH 0.05). No floating point is used for any amount.
do $$
begin
  if to_regclass('public.companies') is null then
    raise exception 'Apply and verify 202609230002_multi_company.sql before this migration';
  end if;
end
$$;

-- ---------------------------------------------------------------------------
-- 1. Balance
-- ---------------------------------------------------------------------------
alter table public.companies
  add column if not exists sms_credits integer not null default 0;

-- Idempotent: drop before add, so re-running this migration never fails with a
-- duplicate-constraint error.
alter table public.companies
  drop constraint if exists companies_sms_credits_non_negative;
alter table public.companies
  add constraint companies_sms_credits_non_negative
  check (sms_credits >= 0);

-- ---------------------------------------------------------------------------
-- 2. Reservations (mutable working state, deliberately not the audit trail)
--
-- One row per outgoing SMS. Created when a credit is reserved, then moved
-- pending -> consumed / refunded. This is the only table whose status is
-- updated after insert.
--
-- Created BEFORE the ledger so the ledger can hold a real foreign key to it.
-- ---------------------------------------------------------------------------
create table if not exists public.sms_credit_reservations (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  -- Always -1 today; explicit so the sign convention matches the ledger.
  credits integer not null check (credits = -1),
  delivery_id text,
  status text not null default 'pending'
    check (status in ('pending', 'consumed', 'refunded')),
  created_at timestamptz not null default now(),
  settled_at timestamptz,
  created_by_user_id uuid references auth.users(id) on delete set null
);

create index if not exists sms_credit_reservations_company_idx
  on public.sms_credit_reservations (company_id, created_at desc);

-- ---------------------------------------------------------------------------
-- 3. Append-only ledger
--
-- STRICTLY APPEND-ONLY. No function in this migration ever UPDATEs or DELETEs a
-- row here. Every row is a settled fact: a completed purchase, a consumed
-- credit, or an automatic refund. There are deliberately no pending, failed or
-- cancelled rows: in-flight state lives in sms_credit_reservations above, and a
-- failed payment simply leaves no ledger row at all.
--
-- 'credits' is signed: purchase and refund are positive, usage is negative.
-- Every row moves the balance, so credits can never be zero.
-- 'balance_after' records the resulting balance so the whole history can be
-- replayed and audited against companies.sms_credits.
-- ---------------------------------------------------------------------------
create table if not exists public.sms_credit_transactions (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  type text not null check (type in ('purchase', 'usage', 'refund')),
  -- Only settled facts belong here, and every one of them moves the balance, so
  -- credits can never be zero. A failed or cancelled payment simply leaves no
  -- row at all.
  credits integer not null check (credits <> 0),
  balance_after integer not null check (balance_after >= 0),
  amount_minor bigint check (amount_minor is null or amount_minor >= 0),
  currency text,
  payment_provider text,
  payment_reference text,
  -- Settled only. There are no pending, failed or cancelled ledger rows; that
  -- state lives in sms_credit_reservations.
  status text not null default 'successful' check (status = 'successful'),
  -- Real foreign key to the reservation this row settles. ON DELETE SET NULL
  -- requires a REFERENCES clause, so the target table is created first.
  reservation_id uuid references public.sms_credit_reservations(id) on delete set null,
  delivery_id text,
  note text,
  created_at timestamptz not null default now(),
  created_by_user_id uuid references auth.users(id) on delete set null
);

-- Payment idempotency key. A provider reference is only unique WITHIN a
-- provider, so the key is the pair.
create unique index if not exists sms_credit_tx_payment_idempotency_key
  on public.sms_credit_transactions (payment_provider, payment_reference)
  where payment_reference is not null;

-- Hard backstop: a reservation can be refunded at most once, even if the
-- reservation status guard were ever bypassed.
create unique index if not exists sms_credit_tx_refund_once_key
  on public.sms_credit_transactions (reservation_id)
  where reservation_id is not null and type = 'refund';

create index if not exists sms_credit_tx_company_created_idx
  on public.sms_credit_transactions (company_id, created_at desc);

-- Database-level enforcement of append-only.
--
-- The functions above are the only writers of this table and they only ever
-- INSERT, so this trigger is a second, independent line of defence. It makes the
-- append-only rule a property of the schema itself rather than a convention, so
-- a mistake in future code, a manual session, or a cascade from another table
-- cannot silently rewrite or erase settled financial history.
--
-- BEFORE UPDATE OR DELETE means INSERT is completely unaffected: the trigger
-- never fires for it, so crediting and refunding continue to work exactly as
-- before.
create or replace function public.sms_credit_transactions_append_only()
returns trigger
language plpgsql
as $$
begin
  raise exception 'sms_credit_transactions is append-only';
end;
$$;

drop trigger if exists sms_credit_transactions_append_only on public.sms_credit_transactions;
create trigger sms_credit_transactions_append_only
  before update or delete on public.sms_credit_transactions
  for each row execute function public.sms_credit_transactions_append_only();

-- ---------------------------------------------------------------------------
-- 4. Protection
--
-- Two independent layers:
--   * Column privileges decide WHICH columns are writable.
--   * RLS decides WHICH rows and by whom.
--
-- The existing table-level `revoke update on public.companies` (migration
-- 202609240001) already removed UPDATE for the whole table, and only name,
-- logo_path and sms_sender_id were granted back by column. sms_credits is
-- deliberately NOT added to that grant, so not even an owner or admin can edit a
-- balance by hand. The explicit revoke below is defence in depth.
-- ---------------------------------------------------------------------------
revoke update (sms_credits) on public.companies from public, anon, authenticated;

alter table public.sms_credit_transactions enable row level security;
alter table public.sms_credit_reservations enable row level security;

-- Clients may read their own company's ledger, and nothing else.
revoke insert, update, delete on public.sms_credit_transactions
  from public, anon, authenticated;
grant select on public.sms_credit_transactions to authenticated;

-- Reservations are server-internal. Clients get no access at all.
revoke all on public.sms_credit_reservations from public, anon, authenticated;

drop policy if exists sms_credit_transactions_company_read on public.sms_credit_transactions;
create policy sms_credit_transactions_company_read
  on public.sms_credit_transactions for select to authenticated
  using (public.is_company_member(company_id));

-- No INSERT/UPDATE/DELETE policy exists on either table for any client role, and
-- reservations have no SELECT policy either. Even if a privilege were granted by
-- mistake, RLS would still deny the write.

-- ---------------------------------------------------------------------------
-- 5. Server-side credit operations
--
-- All three are SECURITY DEFINER with an explicit search_path, and all three are
-- revoked from public / anon / authenticated so only the service-role key can
-- reach them. They are the only writers of a balance, and the only writers of
-- the ledger, and they only ever INSERT into the ledger.
--
-- Company isolation: these functions accept a company_id because they are called
-- exclusively from our own Edge Functions with the service-role key. That is
-- deliberate and is NOT sufficient on its own, so the calling Edge Function must
-- derive the company from the authenticated caller's own memberships and the
-- delivery's company_id before calling in. Never pass a client-supplied company
-- straight to these functions.
-- ---------------------------------------------------------------------------

-- Reserve one credit for an outgoing SMS.
--
-- Returns the reservation id, or NULL when the company has no credit left.
--
-- The single predicated UPDATE is the concurrency guard: PostgreSQL re-checks
-- the WHERE clause under the row lock it takes, so if only one credit remains and
-- two requests arrive at once, exactly one UPDATE matches and the other returns
-- NULL without sending anything.
create or replace function public.sms_credit_reserve(
  p_company_id uuid,
  p_delivery_id text,
  p_user_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_balance integer;
  v_id uuid;
begin
  update public.companies
     set sms_credits = sms_credits - 1
   where id = p_company_id
     and sms_credits > 0
  returning sms_credits into v_balance;

  -- No credit available. The caller must not contact the SMS provider.
  if not found then
    return null;
  end if;

  insert into public.sms_credit_reservations (
    company_id, credits, delivery_id, status, created_by_user_id
  ) values (
    p_company_id, -1, p_delivery_id, 'pending', p_user_id
  )
  returning id into v_id;

  return v_id;
end;
$$;

-- Settle a reservation once the SMS provider has answered.
--
--   p_succeeded = true  -> the credit stays spent and a 'usage' ledger row is
--                          appended.
--   p_succeeded = false -> the credit is returned and a 'refund' ledger row is
--                          appended, so the failed attempt is fully auditable.
--
-- The reservation row is locked FOR UPDATE and the status transition is
-- conditional on it still being 'pending', so a replayed or concurrent finalize
-- affects nothing. The unique partial index on refund rows keyed by
-- reservation_id is a second, independent guarantee that a reservation can
-- never be refunded twice.
create or replace function public.sms_credit_finalize(
  p_reservation_id uuid,
  p_succeeded boolean,
  p_actor_user_id uuid default null
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_res public.sms_credit_reservations%rowtype;
  v_new_balance integer;
begin
  select * into v_res
    from public.sms_credit_reservations
   where id = p_reservation_id
   for update;

  if not found then
    return false;
  end if;
  if v_res.status <> 'pending' then
    return false;
  end if;

  if p_succeeded then
    -- Lock the company row before reading the balance.
    --
    -- The credit was already taken at reserve time, so this branch does not
    -- change the balance; it only records the resulting figure. Taking an
    -- explicit FOR UPDATE lock makes that read exact and serialises it against a
    -- concurrent reserve, refund or purchase on the same company, so
    -- balance_after can never be read from a torn or stale snapshot.
    select sms_credits into v_new_balance
      from public.companies
     where id = v_res.company_id
     for update;

    if not found then
      raise exception 'Unknown company for reservation';
    end if;

    update public.sms_credit_reservations
       set status = 'consumed', settled_at = now()
     where id = p_reservation_id and status = 'pending';

    insert into public.sms_credit_transactions (
      company_id, type, credits, balance_after, status,
      reservation_id, delivery_id, created_by_user_id
    ) values (
      v_res.company_id, 'usage', -1, v_new_balance,
      'successful', p_reservation_id, v_res.delivery_id, p_actor_user_id
    );
    return true;
  end if;

  -- Failed submission: return exactly one reserved credit.
  update public.sms_credit_reservations
     set status = 'refunded', settled_at = now()
   where id = p_reservation_id and status = 'pending';

  update public.companies
     set sms_credits = sms_credits + 1
   where id = v_res.company_id
  returning sms_credits into v_new_balance;

  insert into public.sms_credit_transactions (
    company_id, type, credits, balance_after, status,
    reservation_id, delivery_id, created_by_user_id
  ) values (
    v_res.company_id, 'refund', 1, v_new_balance,
    'successful', p_reservation_id, v_res.delivery_id, p_actor_user_id
  );

  return true;
end;
$$;

-- Record a verified purchase.
--
-- This is the seam a payment provider will call after it has independently
-- verified a payment. No provider is integrated yet, so it currently has no
-- caller and credits cannot be purchased.
--
-- IDEMPOTENCY, and why the order matters:
--   The ledger INSERT happens BEFORE the balance UPDATE. The unique index on
--   (payment_provider, payment_reference) is the idempotency anchor, so a
--   replayed payment raises unique_violation inside the EXCEPTION block, the
--   function returns NULL immediately, and the balance UPDATE below is never
--   reached. A duplicate therefore cannot add credit.
--
--   The earlier design incremented first and caught the conflict afterwards.
--   Because an EXCEPTION block only rolls back statements inside itself, that
--   increment survived and a replayed webhook permanently double-credited. The
--   insert-first order is what removes that window; the whole function is one
--   transaction, so any uncaught error also rolls the balance back.
--
-- The company row is locked FOR UPDATE first, which serialises concurrent
-- purchases for the same company and makes balance_after exact.
create or replace function public.sms_credit_record_purchase(
  p_company_id uuid,
  p_credits integer,
  p_amount_minor bigint,
  p_currency text,
  p_payment_provider text,
  p_payment_reference text,
  p_user_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  -- One credit is 5 pesewas (GH 0.05). Integer only, never floating point.
  -- This must stay in step with pesewasPerCredit in
  -- lib/features/credits/sms_credit_pricing.dart.
  c_pesewas_per_credit constant integer := 5;
  v_balance integer;
  v_new_balance integer;
  v_id uuid;
begin
  -- Server-side validation. A client-supplied amount is never trusted: it is
  -- recomputed here and must match the credits requested.
  if p_credits is null or p_credits <= 0 then
    raise exception 'Purchase credits must be a positive whole number';
  end if;
  if p_amount_minor is null or p_amount_minor <= 0 then
    raise exception 'Purchase amount must be greater than zero';
  end if;
  if p_amount_minor <> p_credits * c_pesewas_per_credit then
    raise exception 'Purchase amount % does not match % credits at % pesewas each',
      p_amount_minor, p_credits, c_pesewas_per_credit;
  end if;
  if p_currency is distinct from 'GHS' then
    raise exception 'Currency must be GHS';
  end if;
  if p_payment_provider is null or btrim(p_payment_provider) = '' then
    raise exception 'A payment provider is required';
  end if;
  if p_payment_reference is null or btrim(p_payment_reference) = '' then
    raise exception 'A payment reference is required';
  end if;

  -- Lock the company row: serialises concurrent purchases and pins the balance.
  select sms_credits into v_balance
    from public.companies
   where id = p_company_id
     for update;

  if not found then
    raise exception 'Unknown company';
  end if;
  v_new_balance := v_balance + p_credits;

  -- Idempotency anchor FIRST. A duplicate returns here, before any balance
  -- change has been made.
  begin
    insert into public.sms_credit_transactions (
      company_id, type, credits, balance_after, amount_minor, currency,
      payment_provider, payment_reference, status, created_by_user_id
    ) values (
      p_company_id, 'purchase', p_credits, v_new_balance, p_amount_minor,
      btrim(p_currency), btrim(p_payment_provider), btrim(p_payment_reference),
      'successful', p_user_id
    )
    returning id into v_id;
  exception when unique_violation then
    -- Already processed. No additional credit, no additional ledger row.
    return null;
  end;

  -- Only reached once the ledger row is safely written.
  update public.companies
     set sms_credits = v_new_balance
   where id = p_company_id;

  return v_id;
end;
$$;

-- EXECUTE is granted to PUBLIC by default, so it must be revoked explicitly for
-- every client role. Only service_role can change credits.
revoke all on function public.sms_credit_reserve(uuid, text, uuid)
  from public, anon, authenticated;
revoke all on function public.sms_credit_finalize(uuid, boolean, uuid)
  from public, anon, authenticated;
revoke all on function public.sms_credit_record_purchase(uuid, integer, bigint, text, text, text, uuid)
  from public, anon, authenticated;

grant execute on function public.sms_credit_reserve(uuid, text, uuid) to service_role;
grant execute on function public.sms_credit_finalize(uuid, boolean, uuid) to service_role;
grant execute on function public.sms_credit_record_purchase(uuid, integer, bigint, text, text, text, uuid)
  to service_role;

comment on column public.companies.sms_credits is
  'SMS credits for this company. Starts at 0. Read-only for clients; changed only by the sms_credit_* server functions.';
comment on table public.sms_credit_transactions is
  'Append-only audit ledger of SMS credit purchases, usage and refunds. Rows are never updated or deleted. Readable for own company only; never client-writable.';
comment on table public.sms_credit_reservations is
  'In-flight SMS credit reservations. Mutable working state, not part of the audit trail. Server-only; clients have no access.';

