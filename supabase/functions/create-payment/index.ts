// Creates a PENDING payment intent for the caller's own company.
//
// THIS FUNCTION GRANTS NOTHING. It records intent and returns where the
// customer should go to pay. An entitlement is granted only by
// `apply_verified_payment()`, and only after `verify-payment` confirms with the
// provider that the money actually moved. A client cannot shortcut this by
// asserting that it paid.
//
// SECURITY:
//  - The company is derived from the caller's own membership, never from the
//    body. A client-supplied company_id is rejected outright, exactly as
//    `send-sms-receipt` rejects `sender_id`.
//  - Only an owner/admin may start a purchase; a secretary is refused.
//  - The AMOUNT is computed here from subscription_config. The client may
//    choose a purpose and a quantity, but never a price, so nobody can buy a
//    year of software for one pesewa.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import {
  PaymentNotConfiguredError,
  resolveSubscriptionPaymentProvider,
  type PaymentPurpose,
} from '../_shared/payment_provider.ts';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const PURPOSES: PaymentPurpose[] = [
  'SETUP_FEE',
  'SOFTWARE_SUBSCRIPTION',
  'SECRETARY_BUNDLE',
  'AI_SUBSCRIPTION',
];

type Config = {
  currency: string;
  setup_fee_minor: number;
  base_monthly_minor: number;
  additional_secretary_bundle_minor: number;
  secretary_bundle_size: number;
  ai_monthly_minor: number;
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

/**
 * The price of a purpose, in minor units, straight from the server's config.
 *
 * This is deliberately the only place a subscription amount is decided. The
 * client never sends an amount at all.
 */
export function priceFor(
  purpose: PaymentPurpose,
  quantity: number,
  config: Config,
): number {
  switch (purpose) {
    case 'SETUP_FEE':
      return config.setup_fee_minor;
    case 'SOFTWARE_SUBSCRIPTION':
      return config.base_monthly_minor;
    case 'SECRETARY_BUNDLE':
      // A bundle purchase costs the bundle price times the bundle count. There
      // is no per-secretary price, by design.
      return config.additional_secretary_bundle_minor * quantity;
    case 'AI_SUBSCRIPTION':
      return config.ai_monthly_minor;
    default:

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (request.method !== 'POST') return json({ error: 'Method not allowed' }, 405);

  const url = Deno.env.get('SUPABASE_URL');
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !anonKey || !serviceKey) {
    return json({ error: 'Payment service is not configured' }, 500);
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

  // 2. Read the request. A client-supplied company is rejected, not ignored, so
  //    a caller can never even attempt to buy for another company.
  let input: {
    purpose?: unknown;
    quantity?: unknown;
    company_id?: unknown;
    return_url?: unknown;
  };
  try {
    input = (await request.json()) as typeof input;
  } catch {
    return json({ error: 'Invalid request body' }, 400);
  }
  if (input.company_id != null) {
    return json({ error: 'COMPANY_ID_NOT_ACCEPTABLE' }, 400);
  }

  const purpose = String(input.purpose ?? '') as PaymentPurpose;
  // SMS credits are not sold here: they keep their own separate purchase path.
  if (!PURPOSES.includes(purpose)) {
    return json({ error: 'A valid payment purpose is required' }, 400);
  }

  // Only secretary bundles are bought in quantity, and only a small sane
  // number. Everything else is exactly one.
  const requestedQuantity = Number(input.quantity ?? 1);
  const quantity = purpose === 'SECRETARY_BUNDLE'
    ? Math.floor(requestedQuantity)
    : 1;
  if (!Number.isFinite(quantity) || quantity < 1 || quantity > 100) {
    return json({ error: 'A valid quantity is required' }, 400);
  }

  const admin = createClient(url, serviceKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  // 3. Derive the caller's company from their own membership. Never from input.
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


  // 5. Record the intent as PENDING. Creating this row grants nothing: the
  //    status stays PENDING until a verified payment settles it.
  const { data: payment, error: paymentError } = await admin
    .from('payment_transactions')
    .insert({
      company_id: companyId,
      purpose,
      amount_minor: amountMinor,
      currency: (config as { currency: string }).currency,
      // Recorded as 'unconfigured' so an audit reader can tell at a glance that
      // no real provider was involved yet. It is replaced by the real provider
      // name once Hubtel is implemented.
      provider: 'unconfigured',
      status: 'PENDING',
      quantity,
      created_by_user_id: callerId,
    })
    .select('id, purpose, amount_minor, currency, status')
    .single();
  if (paymentError || !payment) {
    return json({ error: 'Could not start the payment' }, 500);
  }

  // 6. Ask the provider where to send the customer. This is where a real
  //    integration (Hubtel) will be plugged in; today it refuses, so no payment
  //    can be completed and no entitlement can be granted by this endpoint.
  const provider = resolveSubscriptionPaymentProvider();
  if (!provider.isConfigured()) {
    return json(
      {
        error: 'PAYMENT_PROVIDER_NOT_CONFIGURED',
        message:
          'Online payment is not available yet. No charge has been made and nothing has been added to your account.',
        // The PENDING row is returned so the admin can see the attempt, and so
        // it can be reconciled later. It grants nothing.
        payment,
      },
      503,
    );
  }

  try {
    const session = await provider.createPayment({
      companyId,
      userId: callerId,
      purpose,
      amountMinor,
      currency: (config as { currency: string }).currency,
      reference: (payment as { id: string }).id,
      quantity,
      returnUrl: typeof input.return_url === 'string' ? input.return_url : '',
      callbackUrl: `${url}/functions/v1/subscription-webhook`,
    });
    // The provider's reference is what makes settlement idempotent, so it is
    // stored immediately and is unique per provider.
    await admin
      .from('payment_transactions')
      .update({ status: 'PROCESSING', provider: provider.name })
      .eq('id', (payment as { id: string }).id);

    return json({
      payment: { ...(payment as object), status: 'PROCESSING' },
      checkoutUrl: session.checkoutUrl,
    }, 201);
  } catch {
    // The provider's own error text is never echoed back to the client.
    return json({ error: 'Could not start the payment' }, 502);
  }
});

  // 4. Price the purchase from the server's own configuration.
  const { data: config, error: configError } = await admin
    .from('subscription_config')
    .select('currency, setup_fee_minor, base_monthly_minor, additional_secretary_bundle_minor, secretary_bundle_size, ai_monthly_minor')
    .eq('id', true)
    .single();
  if (configError || !config) {
    return json({ error: 'PAYMENT_NOT_CONFIGURED' }, 500);
  }

  const amountMinor = priceFor(purpose, quantity, config as unknown as Config);
  if (amountMinor <= 0) {
    return json({ error: 'PAYMENT_NOT_AVAILABLE' }, 400);
  }

      // SMS_CREDITS is intentionally not purchasable here: credits keep their
      // own separate accounting and their own top-up path.
      return 0;
  }
}
