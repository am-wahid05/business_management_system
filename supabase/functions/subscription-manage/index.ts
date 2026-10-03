// Pause and reactivate a company's subscription.
//
// Seasonal businesses stop trading for part of the year, so pausing is a
// first-class operation rather than a cancellation. Pausing deletes nothing:
// users, deliveries, weights, suppliers, products, reports, receipts, SMS
// history and branding all stay exactly as they are, and the company keeps its
// identity. Reactiving restores what the company actually had and never issues a
// second trial.
//
// SECURITY: the company is derived from the caller's own membership and only an
// owner/admin may act, so one company can never pause or resume another's
// subscription. A client-supplied company_id is rejected outright.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

/** The actions this endpoint will perform. Nothing else is accepted. */
const ACTIONS = ['PAUSE', 'RESUME'] as const;
type Action = (typeof ACTIONS)[number];

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (request.method !== 'POST') return json({ error: 'Method not allowed' }, 405);

  const url = Deno.env.get('SUPABASE_URL');
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !anonKey || !serviceKey) {
    return json({ error: 'Subscription service is not configured' }, 500);
  }

  const authorization = request.headers.get('Authorization');
  if (!authorization) return json({ error: 'Authentication required' }, 401);
  const callerClient = createClient(url, anonKey, {
    global: { headers: { Authorization: authorization } },
  });
  const { data: callerData, error: callerError } = await callerClient.auth.getUser();
  if (callerError || !callerData.user) return json({ error: 'Invalid session' }, 401);
  const callerId = callerData.user.id;

  let input: { action?: unknown; reason?: unknown; company_id?: unknown };
  try {
    input = (await request.json()) as typeof input;
  } catch {
    return json({ error: 'Invalid request body' }, 400);
  }
  if (input.company_id != null) {
    return json({ error: 'COMPANY_ID_NOT_ACCEPTABLE' }, 400);
  }

  const action = String(input.action ?? '') as Action;
  if (!ACTIONS.includes(action)) {
    return json({ error: 'A valid action is required' }, 400);
  }
  const reason = typeof input.reason === 'string' ? input.reason.trim() : '';

  const admin = createClient(url, serviceKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  // Derive the caller's company from their membership, never from the body.
  const { data: memberships, error: membershipError } = await admin
    .from('company_memberships')
    .select('company_id, role')
    .eq('user_id', callerId)
    .eq('is_active', true);
  if (membershipError) return json({ error: 'Could not verify company access' }, 403);

  const adminMemberships = ((memberships ?? []) as { company_id: string; role: string }[])
    .filter((row) => row.role === 'owner' || row.role === 'admin');
  if (adminMemberships.length === 0) {
    return json({ error: 'ADMIN_ACCESS_REQUIRED' }, 403);
  }
  const companyId = adminMemberships[0].company_id;

  // Pausing reports its own reason; a default keeps the audit trail readable.
  const fallbackReason = 'Season ended; subscription paused by the company';
  const { data, error } = action === 'PAUSE'
    ? await admin.rpc('pause_company_subscription', {
        target_company: companyId,
        why: reason || fallbackReason,
      })
    : await admin.rpc('resume_company_subscription', {
        target_company: companyId,
      });

  if (error) {
    // The database function's message is a known, safe string ("This
    // subscription is not paused"), so it is safe to surface.
    return json({ error: error.message }, 400);
  }

  return json({ action, entitlements: data }, 200);
});
