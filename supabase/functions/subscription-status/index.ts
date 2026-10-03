// Read-only subscription, entitlement and payment status for the caller's own
// company.
//
// SECURITY: the company is never taken from the request. It is derived from the
// caller's own active membership, exactly as `sms-credits` and `ai-assistant`
// already do, so one company can never read another's billing position. A
// secretary is refused outright: they must not be able to read or infer the
// company's billing status, and they are never a route around subscription
// administration.
//
// This endpoint grants nothing. It only reports what the database already says.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
};

const HISTORY_LIMIT = 50;

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (request.method !== 'GET' && request.method !== 'POST') {
    return json({ error: 'Method not allowed' }, 405);
  }

  const url = Deno.env.get('SUPABASE_URL');
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !anonKey || !serviceKey) {
    return json({ error: 'Subscription service is not configured' }, 500);
  }

  // 1. Authenticate the caller from the Authorization header only.
  const authorization = request.headers.get('Authorization');
  if (!authorization) return json({ error: 'Authentication required' }, 401);
  const callerClient = createClient(url, anonKey, {
    global: { headers: { Authorization: authorization } },
  });
  const { data: callerData, error: callerError } = await callerClient.auth.getUser();
  if (callerError || !callerData.user) return json({ error: 'Invalid session' }, 401);
  const callerId = callerData.user.id;

  const admin = createClient(url, serviceKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  // 2. Resolve the caller's OWN company from their membership. A client may pass
  //    company_id as a hint, but it is only honoured if the caller is already a
  //    proven owner/admin of it -- it is never the authority.
  let requested: string | null = null;
  const fromQuery = new URL(request.url).searchParams.get('company_id');
  if (fromQuery) requested = fromQuery;
  if (request.method === 'POST') {
    try {
      const body = await request.json();
      if (body?.company_id != null) requested = String(body.company_id);
    } catch {
      // An empty body simply means "no hint".
    }
  }

  const { data: memberships, error: membershipError } = await admin
    .from('company_memberships')
    .select('company_id, role')
    .eq('user_id', callerId)
    .eq('is_active', true);
  if (membershipError) return json({ error: 'Could not verify company access' }, 403);

  const adminCompanies = ((memberships ?? []) as { company_id: string; role: string }[])
    .filter((row) => row.role === 'owner' || row.role === 'admin')
    .map((row) => row.company_id);
  // A secretary is not a route to the billing information.
  if (adminCompanies.length === 0) {
    return json({ error: 'ADMIN_ACCESS_REQUIRED' }, 403);
  }

  // Intersect the hint with the caller's proven set. Asking for a company the
  // caller does not administer simply falls back to one they do.
  const companyId = requested && adminCompanies.includes(requested)
    ? requested
    : adminCompanies[0];

  // 3. Advance any subscription whose dates have passed, so the transition is
  //    persisted and written to the audit trail. This only changes status; it
  //    deletes nothing.
  //
  //    Correctness does NOT depend on this call. company_entitlements() derives
  //    the effective status from the trial, period and grace dates, so an
  //    unswept company that has run out of time is already reported as expired.
  //    The sweep is therefore an optimisation and an audit record, not the
  //    security boundary -- which is what makes a sweep failure harmless.
  const { error: sweepError } = await admin.rpc('sweep_expired_subscriptions');
  if (sweepError) {
    // Deliberately not fatal. The projection below is date-derived, so it still
    // reports the company's real state even when the sweep could not run.
    console.error('subscription sweep failed', sweepError.message);
  }

  // 4. The single source of truth for entitlements.
  const { data: entitlements, error: entitlementsError } = await admin.rpc(
    'company_entitlements',
    { target_company: companyId },
  );
  if (entitlementsError || !entitlements) {
    return json({ error: 'Could not load subscription status' }, 500);
  }

  const { data: company } = await admin
    .from('companies')
    .select('id, name')
    .eq('id', companyId)
    .maybeSingle();

  // 5. Audit trail, same company scope, so an admin can see what happened.
  const [{ data: payments }, { data: events }] = await Promise.all([
    admin
      .from('payment_transactions')
      .select('id, purpose, amount_minor, currency, provider, provider_reference, status, quantity, sms_credits, created_at, verified_at')
      .eq('company_id', companyId)
      .order('created_at', { ascending: false })
      .limit(HISTORY_LIMIT),
    admin
      .from('subscription_events')
      .select('id, event_type, from_status, to_status, reason, created_at')
      .eq('company_id', companyId)
      .order('id', { ascending: false })
      .limit(HISTORY_LIMIT),
  ]);

  // 6. How many secretaries are actually in use, so the admin can see when they
  //    are over their allowance. This is a count only: nothing is ever removed.
  const { data: secretaryRows } = await admin
    .from('company_memberships')
    .select('user_id, is_active')
    .eq('company_id', companyId)
    .eq('role', 'secretary')
    .eq('is_active', true);
  const secretariesInUse = (secretaryRows ?? []).length;

  return json(
    {
      company: company ?? { id: companyId, name: 'Company' },
      entitlements,
      secretariesInUse,
      // True when the company has more secretaries than it currently pays for.
      // The admin is told, nothing is deleted, and adding more is blocked.
      overSecretaryAllowance: secretariesInUse > Number(entitlements.maxSecretaries ?? 0),
      payments: payments ?? [],
      events: events ?? [],
    },
    200,
  );
});

