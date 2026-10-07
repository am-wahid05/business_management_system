-- Restrict direct RPC access to subscription SECURITY DEFINER routines.
-- Edge Functions use the service role for the two externally consumed helpers;
-- the event and trial helpers are called only by trusted database routines.
revoke execute on function public.company_entitlements(uuid)
  from public, anon, authenticated;
grant execute on function public.company_entitlements(uuid) to service_role;

revoke execute on function public.record_subscription_event(
  uuid, text, public.subscription_status, public.subscription_status,
  text, uuid, jsonb
) from public, anon, authenticated;

revoke execute on function public.start_company_trials(uuid)
  from public, anon, authenticated;

revoke execute on function public.sweep_expired_subscriptions()
  from public, anon, authenticated;
grant execute on function public.sweep_expired_subscriptions() to service_role;
