-- Company SMS configuration.
--
-- The Sailup sender ID is per-company and must be registered and approved in
-- Sailup before it can be used. It is deliberately stored per company rather
-- than globally so a company can never send under another company's sender ID.
--
-- This is the minimal change required: one nullable text column on the existing
-- `companies` table, written only by company owners/admins through the same RLS
-- path already used for `name` and `logo_path`.
--
-- Requires the multi-company schema (202609230002) and the company branding
-- migration (202609240001). Safe to re-run.
do $$
begin
  if to_regclass('public.companies') is null then
    raise exception 'Apply and verify 202609230002_multi_company.sql before this migration';
  end if;
end
$$;

alter table public.companies add column if not exists sms_sender_id text;

-- A Sailup sender ID is either a numeric MSISDN (max 15 digits) or an
-- alphanumeric ID of up to 11 characters. Anything else is rejected at the
-- database boundary so an unusable value can never be stored and later used to
-- call the provider. Empty/NULL means "not configured yet", which the Edge
-- Function reports as a clear configuration error.
do $$
begin
  alter table public.companies drop constraint if exists companies_sms_sender_id_format;
  alter table public.companies add constraint companies_sms_sender_id_format check (
    sms_sender_id is null
    or btrim(sms_sender_id) = ''
    or sms_sender_id ~ '^[0-9]{1,15}$'
    or (sms_sender_id ~ '^[A-Za-z0-9 ]{3,11}$' and btrim(sms_sender_id) = sms_sender_id)
  );
end
$$;

-- Only owners and admins may change company settings. The existing restrictive
-- boundary policy from the branding migration still applies, and the column
-- grant below keeps secret/system columns unwritable.
grant update (sms_sender_id) on public.companies to authenticated;

comment on column public.companies.sms_sender_id is
  'Company sender ID registered and approved in Sailup. Used server-side by the send-sms-receipt Edge Function; never exposed to or chosen by clients.';