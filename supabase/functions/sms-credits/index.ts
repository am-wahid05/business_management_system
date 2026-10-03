import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
};

const HISTORY_LIMIT = 50;

/**
 * Read-only SMS credit balance and transaction history.
 *
 * The company is never taken from the request. It is derived from the caller's
 * own active membership, so a user can only ever read their own company's
 * balance and ledger. There is deliberately no write path here: credits can only
 * be added by the secure server functions, never by this endpoint or the client.
 */
Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }
  if (request.method !== 'GET' && request.method !== 'POST') {
    return json({ error: 'Method not allowed' }, 405);
  }

  const url = Deno.env.get('SUPABASE_URL');
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !anonKey || !serviceKey) {
    return json({ error: 'SMS credit service is not configured' }, 500);
  }

  // 1. Authenticate the caller.
  const authorization = request.headers.get('Authorization');
  if (!authorization) return json({ error: 'Authentication required' }, 401);
  const callerClient = createClient(url, anonKey, {
    global: { headers: { Authorization: authorization } },
  });
  const { data: callerData, error: callerError } =
    await callerClient.auth.getUser();
  if (callerError || !callerData.user) {
    return json({ error: 'Invalid session' }, 401);
  }
  const callerId = callerData.user.id;

  const adminClient = createClient(url, serviceKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  // 2. Optional company filter. It is intersected with the caller's authorized
  //    companies, so asking for another company simply returns nothing. The
  //    filter may arrive in the query string or in a POST body.
  let requested = new URL(request.url).searchParams.get('company_id');
  if (request.method === 'POST') {
    try {
      const body = await request.json();
      if (body?.company_id != null) requested = String(body.company_id);
    } catch {
      // An empty body simply means "no filter".
    }
  }
  const { data: memberships, error: membershipError } = await adminClient
    .from('company_memberships')
    .select('company_id')
    .eq('user_id', callerId)
    .eq('is_active', true);
  if (membershipError) return json({ error: 'Could not verify company access' }, 403);
  const allowed = new Set<string>(
    ((memberships ?? []) as { company_id: string }[]).map((m) => m.company_id),
  );
  if (allowed.size === 0) return json({ error: 'COMPANY_ACCESS_REQUIRED' }, 403);
  if (requested && !allowed.has(requested)) {
    return json({ error: 'COMPANY_ACCESS_REQUIRED' }, 403);
  }
  const companyIds = requested ? [requested] : [...allowed];

  // 3. Balances for the authorized companies.
  const { data: companies, error: companiesError } = await adminClient
    .from('companies')
    .select('id, name, sms_credits')
    .in('id', companyIds);
  if (companiesError) return json({ error: 'Could not load SMS credits' }, 500);

  // 4. Transaction history, newest first, same company scope.
  const { data: transactions, error: historyError } = await adminClient
    .from('sms_credit_transactions')
    .select(
      'id, company_id, type, credits, balance_after, amount_minor, currency, payment_provider, payment_reference, status, delivery_id, created_at',
    )
    .in('company_id', companyIds)
    .order('created_at', { ascending: false })
    .limit(HISTORY_LIMIT);
  if (historyError) return json({ error: 'Could not load credit history' }, 500);

  const balances = ((companies ?? []) as {
    id: string;
    name: string;
    sms_credits: number | null;
  }[]).map((company) => ({
    company_id: company.id,
    company_name: company.name,
    // A company created before the migration, or any unexpected null, is
    // reported as zero rather than as a fabricated balance.
    balance: Math.max(0, company.sms_credits ?? 0),
  }));

  return json(
    {
      balances,
      transactions: transactions ?? [],
    },
    200,
  );
});

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}
