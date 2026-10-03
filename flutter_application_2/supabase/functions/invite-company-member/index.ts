import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (request.method !== 'POST') return json({ error: 'Method not allowed' }, 405);

  const url = Deno.env.get('SUPABASE_URL');
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !anonKey || !serviceKey) return json({ error: 'Invite service is not configured' }, 500);

  const authorization = request.headers.get('Authorization');
  if (!authorization) return json({ error: 'Authentication required' }, 401);
  const callerClient = createClient(url, anonKey, { global: { headers: { Authorization: authorization } } });
  const { data: callerData, error: callerError } = await callerClient.auth.getUser();
  if (callerError || !callerData.user) return json({ error: 'Invalid session' }, 401);

  let input: { company_id?: string; email?: string; display_name?: string; password?: string; role?: string };
  try {
    input = await request.json();
  } catch {
    return json({ error: 'Invalid request body' }, 400);
  }
  const companyId = input.company_id?.trim();
  const email = input.email?.trim().toLowerCase();
  const displayName = input.display_name?.trim();
  const password = input.password ?? '';
  const role = input.role;
  if (!companyId || !email || !displayName || password.length < 8 || !['admin', 'secretary'].includes(role ?? '')) {
    return json({ error: 'Company, valid email, display name, role, and an 8-character temporary password are required' }, 400);
  }

  const adminClient = createClient(url, serviceKey, { auth: { autoRefreshToken: false, persistSession: false } });
  const { data: membership, error: membershipError } = await adminClient
    .from('company_memberships')
    .select('role')
    .eq('company_id', companyId)
    .eq('user_id', callerData.user.id)
    .eq('is_active', true)
    .maybeSingle();
  if (membershipError || !membership || !['owner', 'admin'].includes(membership.role)) {
    return json({ error: 'Company administrator access is required' }, 403);
  }
  if (role === 'admin' && membership.role !== 'owner') {
    return json({ error: 'Only an owner can invite another administrator' }, 403);
  }

  const { data: created, error: createError } = await adminClient.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
    user_metadata: { display_name: displayName },
  });
  if (createError || !created.user) return json({ error: createError?.message ?? 'Could not create account' }, 400);

  const { error: insertError } = await adminClient.from('company_memberships').insert({
    company_id: companyId,
    user_id: created.user.id,
    role,
  });
  if (insertError) {
    await adminClient.auth.admin.deleteUser(created.user.id);
    return json({ error: insertError.message }, 400);
  }

  return json({
    user: {
      id: created.user.id,
      username: created.user.email ?? email,
      display_name: displayName,
      role,
      is_active: true,
      company_id: companyId,
    },
  }, 201);
});

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}
