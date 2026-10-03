-- Multi-recipient SMS: reserve a whole send atomically.
--
-- Additive only. This migration creates ONE function and touches no table, no
-- column, no policy and no other function. In particular it does not redefine
-- sms_credit_reserve, sms_credit_finalize or sms_credit_record_purchase, so the
-- existing one-credit pricing and the existing settlement rules are unchanged.
--
-- Requires 202609260001_sms_credits.sql (companies.sms_credits and
-- sms_credit_reservations) and 202609260002_bulk_deliveries.sql. Safe to re-run.
--
-- WHY THIS EXISTS
--
-- A receipt may be sent to several phone numbers, but the send must be
-- all-or-nothing. Reserving credits one at a time in a loop would let a send of
-- 5 recipients take 2 credits, then fail, leaving the company partly charged
-- for messages that were never delivered. So the whole balance is taken in ONE
-- predicated UPDATE: either every credit is reserved or none is, and the
-- caller must send ZERO messages when it returns NULL.
--
-- The single UPDATE is the concurrency guard. PostgreSQL re-evaluates the WHERE
-- clause under the row lock it takes, so two concurrent sends can never both
-- observe enough credits and both proceed.
--
-- One reservation row is written per recipient, each for exactly one credit, so
-- sms_credit_finalize() is reused completely unchanged: an accepted recipient
-- keeps its credit and a refused recipient is refunded individually. A credit is
-- therefore never permanently consumed for a recipient that was not sent.
--
-- SECURITY MODEL (identical to the existing reserve)
--
-- SECURITY DEFINER with an explicit search_path, EXECUTE revoked from public,
-- anon and authenticated, and granted only to service_role. No client role, and
-- no Flutter code, can call this or change a balance. Company isolation is not
-- established here and never was: the function accepts a company_id because it
-- is called exclusively from our own Edge Function with the service-role key,
-- which derives that company from the caller's own memberships and the
-- delivery's own company_id. Never pass a client-supplied company to it.
--
-- Supports N = 1, so the existing single-recipient behaviour keeps working
-- through the same path. Pricing is unchanged: one credit per recipient.
create or replace function public.sms_credit_reserve_many(
  p_company_id uuid,
  p_delivery_id text,
  p_user_id uuid,
  p_count integer
)
returns uuid[]
language plpgsql
security definer
set search_path = public
as $$
declare
  v_balance integer;
  v_ids uuid[] := '{}';
  v_id uuid;
begin
  -- A send to nobody costs nothing and reserves nothing. Returns an empty list,
  -- which the caller reads as "nothing to send" rather than as a failure.
  if p_count is null or p_count < 1 then
    return v_ids;
  end if;

  -- All or nothing. A company with fewer than p_count credits matches no row,
  -- so `found` is false, nothing was written, and NULL is returned. The caller
  -- must then contact no SMS provider at all.
  update public.companies
     set sms_credits = sms_credits - p_count
   where id = p_company_id
     and sms_credits >= p_count
  returning sms_credits into v_balance;

  if not found then
    return null;
  end if;

  -- One pending row per recipient, so each recipient settles on its own
  -- outcome through the existing sms_credit_finalize().
  for i in 1..p_count loop
    insert into public.sms_credit_reservations (
      company_id, credits, delivery_id, status, created_by_user_id
    ) values (
      p_company_id, -1, p_delivery_id, 'pending', p_user_id
    )
    returning id into v_id;

    v_ids := array_append(v_ids, v_id);
  end loop;

  return v_ids;
end;
$$;

-- EXECUTE is granted to PUBLIC by default, so it must be revoked explicitly for
-- every client role. Only service_role may reserve a batch, exactly as for the
-- existing single-recipient reserve.
revoke all on function public.sms_credit_reserve_many(uuid, text, uuid, integer)
  from public, anon, authenticated;

grant execute on function public.sms_credit_reserve_many(uuid, text, uuid, integer)
  to service_role;

comment on function public.sms_credit_reserve_many(uuid, text, uuid, integer) is
  'Atomically reserves p_count SMS credits for one multi-recipient receipt send. Returns one reservation id per recipient, or NULL when the balance cannot cover the whole send, in which case no message may be sent.';
