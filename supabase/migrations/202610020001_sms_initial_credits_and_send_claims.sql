-- SMS onboarding credits and provider-send claims.
--
-- This migration is additive. It does not rewrite existing company balances and
-- it does not create separate provider accounts. Sailup remains one shared
-- provider account; sms_credits is the application's company-scoped entitlement.
--
-- Requires 202609260001_sms_credits.sql and 202609230002_multi_company.sql.

do $$
begin
  if to_regclass('public.companies') is null then
    raise exception 'Apply the multi-company schema before this migration';
  end if;
  if to_regclass('public.sms_credit_reservations') is null then
    raise exception 'Apply 202609260001_sms_credits.sql before this migration';
  end if;
end
$$;

-- Existing companies keep their current balance. Only companies inserted after
-- this migration receive the five-credit onboarding balance.
alter table public.companies
  alter column sms_credits set default 5;

comment on column public.companies.sms_credits is
  'Company-scoped SMS credits. New companies start with 5; existing balances are unchanged. Read-only for clients; changed only by secure server functions.';

-- The old Edge Function checked receipt_sends before contacting Sailup. Two
-- concurrent requests could both pass that check. This claim table gives the
-- server one unique, company-scoped key to acquire before contacting the shared
-- provider. A failed provider attempt deletes its claim; an accepted attempt
-- retains it as the durable duplicate-send guard.
create table if not exists public.sms_receipt_send_claims (
  company_id uuid not null references public.companies(id) on delete cascade,
  delivery_id text not null,
  phone text not null,
  status text not null default 'sending'
    check (status in ('sending', 'accepted')),
  provider_reference text,
  created_at timestamptz not null default now(),
  primary key (company_id, delivery_id, phone)
);

create index if not exists sms_receipt_send_claims_delivery_idx
  on public.sms_receipt_send_claims (company_id, delivery_id);

alter table public.sms_receipt_send_claims enable row level security;
revoke all on public.sms_receipt_send_claims from public, anon, authenticated;

comment on table public.sms_receipt_send_claims is
  'Server-only idempotency claims preventing concurrent duplicate provider sends for one company delivery and normalized phone number.';