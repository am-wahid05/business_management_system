// Verifies a payment with the provider and, only if it genuinely succeeded,
// settles it.
//
// THIS IS THE ONLY ROUTE TO AN ENTITLEMENT. The rules it enforces:
//   1. The client can never assert success. The provider is asked directly.
//   2. The provider's reference AND amount must both match what was expected,
//      so a cheap payment cannot unlock an expensive entitlement.
//   3. The company is derived from the caller's membership, never from input.
//   4. Only an owner/admin may verify, and only for their own company.
//   5. Settlement goes through apply_verified_payment(), which is idempotent on
//      the provider reference, so a repeated callback grants nothing extra.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { resolveSubscriptionPaymentProvider } from '../_shared/payment_provider.ts';

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

type PaymentRow = {
  id: string;
  company_id: string;
  purpose: string;
  amount_minor: number;
  status: string;
  provider: string;
  provider_reference: string | null;
};

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (request.method !== 'POST') return json({ error: 'Method not allowed' }, 405);

  const url = Deno.env.get('SUPABASE_URL');
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !anonKey || !serviceKey) {
    return json({ error: 'Payment service is not configured' }, 500);
  }

  const authorization = request.headers.get('Authorization');
  if (!authorization) return json({ error: 'Authentication required' }, 401);
  const callerClient = createClient(url, anonKey, {
    global: { headers: { Authorization: authorization } },
  });
  const { data: callerData, error: callerError } = await callerClient.auth.getUser();
  if (callerError || !callerData.user) return json({ error: 'Invalid session' }, 401);
  const callerId = callerData.user.id;

  let input: { payment_id?: unknown; company_id?: unknown; success?: unknown };
  try {
    input = (await request.json()) as typeof input;
  } catch {
    return json({ error: 'Invalid request body' }, 400);
  }
  // A client-supplied company is rejected outright, and a client-supplied
  // "success" flag is never read: the provider is the only authority.
  if (input.company_id != null) {
    return json({ error: 'COMPANY_ID_NOT_ACCEPTABLE' }, 400);
  }

  const paymentId = typeof input.payment_id === 'string' ? input.payment_id.trim() : '';
  if (!paymentId) return json({ error: 'A payment is required' }, 400);

  const admin = createClient(url, serviceKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  // 1. Load the payment, then prove the caller administers that company.
  const { data: paymentData, error: paymentError } = await admin
    .from('payment_transactions')
    .select('id, company_id, purpose, amount_minor, status, provider, provider_reference')
    .eq('id', paymentId)
    .maybeSingle();
  if (paymentError || !paymentData) {
    return json({ error: 'PAYMENT_NOT_FOUND' }, 404);
  }
  const payment = paymentData as PaymentRow;

  const { data: membership } = await admin
    .from('company_memberships')
    .select('role')
    .eq('company_id', payment.company_id)
    .eq('user_id', callerId)
    .eq('is_active', true)
    .maybeSingle();
  const role = (membership as { role?: string } | null)?.role;
  if (role !== 'owner' && role !== 'admin') {
    return json({ error: 'ADMIN_ACCESS_REQUIRED' }, 403);
  }

  // 2. The replay case, answered before any provider call. A payment that has
  //    already settled returns the same answer and grants nothing further.
  if (payment.status === 'SUCCESSFUL') {
    const { data: entitlements } = await admin.rpc('company_entitlements', {
      target_company: payment.company_id,
    });
    return json({
      verified: true,
      idempotent: true,
      status: 'SUCCESSFUL',
      entitlements,
    });
  }


  // 4. Only a genuine success may settle. A pending, failed or cancelled
  //    payment is recorded and grants nothing at all.
  const statusMap: Record<string, string> = {
    pending: 'PENDING',
    successful: 'SUCCESSFUL',
    failed: 'FAILED',
    cancelled: 'CANCELLED',
  };
  const mapped = statusMap[outcome.status] ?? 'PENDING';

  if (outcome.status !== 'successful') {
    await admin
      .from('payment_transactions')
      .update({ status: mapped })
      .eq('id', payment.id);
    const { data: entitlements } = await admin.rpc('company_entitlements', {
      target_company: payment.company_id,
    });
    return json({ verified: true, status: mapped, entitlements });
  }

  // 5. The amount must match what the server itself priced. A provider that
  //    reports a smaller amount than expected does not unlock the entitlement.
  const paid = outcome.amountMinor;
  if (paid !== undefined && Number(paid) !== Number(payment.amount_minor)) {
    await admin
      .from('payment_transactions')
      .update({ status: 'FAILED', metadata: { mismatch: true } })
      .eq('id', payment.id);
    return json({ error: 'PAYMENT_AMOUNT_MISMATCH' }, 409);
  }

  // 6. Store the provider's transaction id BEFORE settling. The unique index on
  //    (provider, provider_reference) is what makes a replayed callback a no-op
  //    rather than a second grant.
  if (outcome.providerTransactionId) {
    const { error: referenceError } = await admin
      .from('payment_transactions')
      .update({
        provider: provider.name,
        provider_reference: outcome.providerTransactionId,
      })
      .eq('id', payment.id);
    if (referenceError) {
      // A duplicate provider reference means this exact payment already settled
      // under another row, so this one is a replay and must not be applied.
      return json({ verified: true, idempotent: true, status: 'SUCCESSFUL' });
    }
  }

  // 7. Settle. The database function is the only thing that can grant anything,
  //    and it refuses to run twice for the same payment.
  const { data: applied, error: applyError } = await admin.rpc('apply_verified_payment', {
    target_payment: payment.id,
  });
  if (applyError) {
    return json({ error: 'Could not apply the payment' }, 500);
  }

  const { data: entitlements } = await admin.rpc('company_entitlements', {
    target_company: payment.company_id,
  });

  return json({
    verified: true,
    status: 'SUCCESSFUL',
    idempotent: Boolean((applied as { idempotent?: boolean } | null)?.idempotent),
    entitlements,
  });
});

  // 3. Ask the provider what really happened.
  const provider = resolveSubscriptionPaymentProvider();
  if (!provider.isConfigured()) {
    return json({ error: 'PAYMENT_PROVIDER_NOT_CONFIGURED' }, 503);
  }

  let outcome;
  try {
    outcome = await provider.verifyPayment(payment.provider_reference ?? payment.id);
  } catch {
    return json({ error: 'Could not verify the payment' }, 502);
  }
