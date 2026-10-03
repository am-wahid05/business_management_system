import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

// One GSM-7 SMS segment holds 160 characters. Individual bag weights are
// intentionally excluded so a normal receipt stays within a single segment.
const MAX_SMS_LENGTH = 160;

const SAILUP_SMS_ENDPOINT = 'https://api.sailup.io/v1/sms/';

type SendRequest = {
  recipient: string;
  message: string;
  reference: string;
  /**
   * Always resolved server-side from the delivery's company. It is never read
   * from the request body, so a client cannot choose which sender ID is used.
   */
  senderId: string;
};

type SendOutcome = {
  accepted: boolean;
  /** 'queued' means the provider accepted the message; it is not a delivery receipt. */
  status: 'queued' | 'failed';
  providerMessageId?: string;
  error?: string;
};

/** Provider abstraction. All Sailup specifics live behind this interface. */
interface SmsProvider {
  readonly name: string;
  isConfigured(): boolean;
  send(request: SendRequest): Promise<SendOutcome>;
}

/**
 * Sailup transport. The API key is read from the Edge Function secret
 * SAILUP_API_KEY and is never returned, logged, or sent back to the client.
 */
class SailupSmsProvider implements SmsProvider {
  readonly name = 'sailup';

  private get apiKey(): string {
    return (Deno.env.get('SAILUP_API_KEY') ?? '').trim();
  }

  isConfigured(): boolean {
    return this.apiKey.length > 0;
  }

  async send(request: SendRequest): Promise<SendOutcome> {
    if (!this.isConfigured()) {
      return { accepted: false, status: 'failed', error: 'SMS_PROVIDER_NOT_CONFIGURED' };
    }

    let response: Response;
    try {
      response = await fetch(SAILUP_SMS_ENDPOINT, {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${this.apiKey}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          from: request.senderId,
          to: [request.recipient],
          body: request.message,
        }),
      });
    } catch {
      return { accepted: false, status: 'failed', error: 'SMS_PROVIDER_UNREACHABLE' };
    }

    // 202 means queued for delivery, NOT delivered.
    if (response.status === 202 || response.status === 200) {
      return {
        accepted: true,
        status: 'queued',
        providerMessageId: await readMessageId(response),
      };
    }
    return { accepted: false, status: 'failed', error: await readProviderError(response) };
  }
}

async function readMessageId(response: Response): Promise<string | undefined> {
  try {
    const body = await response.json();
    if (body && typeof body === 'object') {
      const record = body as Record<string, unknown>;
      const data = record.data;
      const candidate =
        record.messageId ??
        record.id ??
        (Array.isArray(data) ? (data as Record<string, unknown>[])[0]?.id : undefined);
      if (typeof candidate === 'string' && candidate.length > 0) return candidate;
    }
  } catch {
    // A 2xx with an unexpected body is still treated as queued.
  }
  return undefined;
}

/**
 * Returns a safe, user-facing code. Never echoes credentials or raw bodies.
 *
 * Sailup reports an unregistered/unapproved sender ID as a 4xx with a
 * `sender_not_approved` style error. That is a configuration problem the user
 * can act on, so it is surfaced as its own code. The raw response body is
 * deliberately not returned, so no server detail or credential can leak.
 */
async function readProviderError(response: Response): Promise<string> {
  if (response.status === 401 || response.status === 403) {
    return 'SMS_PROVIDER_REJECTED_CREDENTIALS';
  }
  if (response.status === 429) return 'SMS_PROVIDER_RATE_LIMITED';
  if (response.status >= 500) return 'SMS_PROVIDER_UNAVAILABLE';
  if (await mentionsSenderNotApproved(response)) return 'SMS_SENDER_ID_NOT_APPROVED';
  return 'SMS_PROVIDER_REJECTED';
}

/**
 * Detects a sender-approval rejection without ever surfacing the body itself.
 * Only the boolean result is used.
 */
async function mentionsSenderNotApproved(response: Response): Promise<boolean> {
  let text: string;
  try {
    text = (await response.text()).toLowerCase();
  } catch {
    return false;
  }
  return (
    text.includes('sender_not_approved') ||
    text.includes('sender not approved') ||
    text.includes('sender id not approved') ||
    text.includes('unapproved sender')
  );
}

const provider = new SailupSmsProvider();

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (request.method !== 'POST') return json({ error: 'Method not allowed' }, 405);

  const url = Deno.env.get('SUPABASE_URL');
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !anonKey || !serviceKey) {
    return json({ error: 'SMS service is not configured' }, 500);
  }

  // 1. Authenticate the caller.
  const authorization = request.headers.get('Authorization');
  if (!authorization) return json({ error: 'Authentication required' }, 401);
  const callerClient = createClient(url, anonKey, {
    global: { headers: { Authorization: authorization } },
  });
  const { data: callerData, error: callerError } = await callerClient.auth.getUser();
  if (callerError || !callerData.user) return json({ error: 'Invalid session' }, 401);
  const callerId = callerData.user.id;

  // 2. Minimal input. The company and the sender ID are never taken from the
  //    client. A `sender_id`/`from` field is rejected outright rather than
  //    ignored, so a caller can never attempt to send under another company.
  let input: {
    delivery_id?: string;
    phone?: string;
    phones?: unknown;
    sender_id?: unknown;
    from?: unknown;
  };
  try {
    input = await request.json();
  } catch {
    return json({ error: 'Invalid request body' }, 400);
  }
  if (input.sender_id != null || input.from != null) {
    return json({ error: 'SENDER_ID_NOT_ACCEPTABLE' }, 400);
  }
  const deliveryId = input.delivery_id?.trim();
  if (!deliveryId) return json({ error: 'A delivery is required' }, 400);

  // 2a. Resolve the recipient list.
  //
  // A single `phone` is still accepted and behaves exactly as before. A
  // `phones` array is the multi-recipient form. Every entry is normalized here
  // and de-duplicated after normalization, so two spellings of one Ghana number
  // are one recipient and can never be sent to or charged twice. The client
  // performs the same normalization, but the server repeats it because the
  // server is what actually spends credits and contacts the provider.
  const rawRecipients: string[] = [];
  if (Array.isArray(input.phones)) {
    for (const entry of input.phones) {
      if (typeof entry === 'string') rawRecipients.push(entry);
    }
  } else if (typeof input.phone === 'string') {
    rawRecipients.push(input.phone);
  }
  if (rawRecipients.length === 0) {
    return json({ error: 'A valid recipient phone number is required' }, 400);
  }
  const phones: string[] = [];
  for (const raw of rawRecipients) {
    const normalized = normalizeGhanaPhone(raw);
    // An invalid entry is dropped rather than guessed at. A recipient the
    // secretary typed wrongly is never guessed into a number.
    if (normalized && !phones.includes(normalized)) phones.push(normalized);
  }
  if (phones.length === 0) {
    return json({ error: 'A valid recipient phone number is required' }, 400);
  }

  const adminClient = createClient(url, serviceKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  // 3. Derive the caller's authorized companies server-side.
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

  // 4. Load the delivery strictly inside the authorized companies.
  // The bulk columns are additive, so the read is retried without them if the
  // migration has not been applied yet. An un-migrated database then behaves
  // exactly as before.
  const deliveryColumns = 'id, company_id, recorded_at, supplier_name, record_type, total_weight, bag_count';
  let delivery: Record<string, unknown> | null = null;
  let deliveryError: unknown = null;
  const first = await adminClient
    .from('deliveries')
    .select(deliveryColumns)
    .eq('id', deliveryId)
    .in('company_id', [...allowed])
    .maybeSingle();
  delivery = first.data as Record<string, unknown> | null;
  deliveryError = first.error;
  if (deliveryError) {
    const fallback = await adminClient
      .from('deliveries')
      .select('id, company_id, recorded_at, supplier_name')
      .eq('id', deliveryId)
      .in('company_id', [...allowed])
      .maybeSingle();
    if (fallback.error) return json({ error: 'DELIVERY_NOT_FOUND' }, 404);
    delivery = fallback.data as Record<string, unknown> | null;
    deliveryError = null;
  }
  if (deliveryError || !delivery) return json({ error: 'DELIVERY_NOT_FOUND' }, 404);
  // `companyId` is taken from the delivery row, and that row was only loadable
  // because its company_id is in the caller's own membership set. It is NEVER
  // read from the request body. The credit functions below therefore always act
  // on a company the authenticated caller genuinely belongs to, so a Company A
  // user cannot reserve, refund or purchase credits for Company B.
  const companyId = (delivery as { company_id: string }).company_id;

  // 5. Company sender ID, stored per company and approved in Sailup.
  const senderId = await loadSenderId(adminClient, companyId);
  if (!senderId) return json({ error: 'SMS_SENDER_ID_NOT_CONFIGURED' }, 409);
  // Defence in depth: the database check constraint also enforces this, but an
  // unusable value is rejected here rather than sent to the provider.
  if (!isValidSenderId(senderId)) return json({ error: 'SMS_SENDER_ID_INVALID' }, 409);

  // 6. Per-recipient duplicate protection, reusing the existing receipt_sends
  //    table. 'queued' counts as already-sent so a retry cannot double-send.
  //
  //    A recipient that already has a sent or queued SMS for this delivery is
  //    skipped rather than re-sent or re-charged. This is keyed on the recipient
  //    as well as the delivery, so a second recipient for the same delivery is a
  //    legitimate new send while a repeat of an existing one is refused.
  const alreadySent: string[] = [];
  for (const candidate of phones) {
    const { data: previous, error: previousError } = await adminClient
      .from('receipt_sends')
      .select('id')
      .eq('company_id', companyId)
      .eq('delivery_id', deliveryId)
      .eq('channel', 'sms')
      .eq('phone', candidate)
      .in('status', ['sent', 'queued'])
      .limit(1);
    if (previousError) return json({ error: 'Could not verify receipt history' }, 500);
    if (((previous ?? []) as unknown[]).length > 0) alreadySent.push(candidate);
  }

  const targets = phones.filter((candidate) => !alreadySent.includes(candidate));
  if (targets.length === 0) {
    return json({ error: 'RECEIPT_ALREADY_SENT' }, 409);
  }

  // 7. SMS credit check, for the WHOLE send.
  //
  //    One accepted receipt SMS costs exactly one credit, so N unique recipients
  //    cost exactly N credits. They are reserved in ONE atomic database
  //    operation, not in a loop: either every credit is taken or none is. A
  //    partially reserved send would charge a company for messages that were
  //    never delivered, so on insufficient credits this returns before Sailup is
  //    contacted at all and ZERO messages are sent.
  //
  //    The reserve returns one reservation id per recipient, so each recipient
  //    is settled on its own outcome below.
  const { data: reservation, error: reserveError } = await adminClient.rpc(
    'sms_credit_reserve_many',
    {
      p_company_id: companyId,
      p_delivery_id: deliveryId,
      p_user_id: callerId,
      p_count: targets.length,
    },
  );
  if (reserveError) {
    return json({ error: 'Could not verify SMS credits' }, 500);
  }
  if (!reservation) {
    // Not enough credits for the whole send. Sailup is deliberately NOT called,
    // so no message is sent and no credit is consumed.
    const { data: companyRow } = await adminClient
      .from('companies')
      .select('sms_credits')
      .eq('id', companyId)
      .maybeSingle();
    const balance = (companyRow as { sms_credits?: number } | null)?.sms_credits ?? 0;
    return json(
      {
        error: 'SMS_CREDITS_INSUFFICIENT',
        required: targets.length,
        balance,
      },
      402,
    );
  }
  const reservationIds = (reservation as string[]) ?? [];

  // Never send a message that has no reservation behind it. The reserve returns
  // exactly one id per target, so this only trips if the two ever disagree, and
  // sending anyway would leave a credit stranded in 'pending' with no settled
  // outcome. Stopping here sends nothing and keeps the credits reclaimable.
  if (reservationIds.length !== targets.length) {
    return json({ error: 'Could not reserve SMS credits' }, 500);
  }

  // 8. Build the short receipt summary from the saved delivery data. The client
  //    supplied message is deliberately not used: the company sender ID is the
  //    only label, so what the secretary sees matches what Sailup sends from.
  const message = await buildMessage(
    adminClient,
    delivery as {
      id: string;
      company_id: string;
      supplier_name?: string | null;
      recorded_at?: string | null;
      record_type?: string | null;
      total_weight?: number | string | null;
      bag_count?: number | string | null;
    },
    senderId,
  );

  // 9. Hand off to the Sailup adapter, one request per unique recipient.
  //    The SAME message body is used for every recipient, so all of them see an
  //    identical receipt. The sender ID resolved above is the only value that
  //    can reach the provider; nothing from the request body is used.
  const accepted: { phone: string; reference?: string }[] = [];
  const failed: { phone: string; error: string }[] = [];

  for (let index = 0; index < targets.length; index++) {
    const recipient = targets[index];
    const reservationId = reservationIds[index];
    const outcome = await provider.send({
      recipient,
      message,
      reference: deliveryId,
      senderId,
    });
    if (!outcome.accepted) {
      // The provider refused this recipient, so the reserved credit is returned
      // and a refund row is written to the ledger. The other recipients are
      // unaffected.
      await finalizeCredit(adminClient, reservationId, false, callerId);
      failed.push({ phone: recipient, error: outcome.error ?? 'SMS_REJECTED' });
      continue;
    }
    // The provider accepted the message, so this credit stays consumed.
    await finalizeCredit(adminClient, reservationId, true, callerId);
    accepted.push({
      phone: recipient,
      reference: outcome.providerMessageId ?? undefined,
    });
  }

  // 10. Record one history row per ACCEPTED recipient. A recipient that was
  //     refused is deliberately not written, so the history never shows a
  //     message that was not sent, and no recipient is recorded twice.
  if (accepted.length > 0) {
    const { error: insertError } = await adminClient.from('receipt_sends').insert(
      accepted.map((entry) => ({
        company_id: companyId,
        delivery_id: deliveryId,
        phone: entry.phone,
        channel: 'sms',
        status: 'queued',
        sent_at: new Date().toISOString(),
        provider_reference: entry.reference ?? provider.name,
      })),
    );
    if (insertError) return json({ error: 'SMS queued but could not be recorded' }, 500);
  }

  // 'queued' is explicitly not 'delivered'.
  if (accepted.length === 0) {
    // Every recipient was refused. Each reservation was already refunded above.
    return json(
      {
        accepted: false,
        error: failed[0]?.error ?? 'SMS_REJECTED',
        failed,
        skipped: alreadySent,
      },
      502,
    );
  }

  return json(
    {
      accepted: true,
      status: 'queued',
      reference: accepted[0]?.reference ?? null,
      sent: accepted.map((entry) => entry.phone),
      failed,
      skipped: alreadySent,
    },
    200,
  );
});

/**
 * Settles a reserved SMS credit once the provider has answered.
 *
 * Never throws. A failure to settle must not change what the user is told about
 * the SMS itself, and the reservation stays 'pending' in the ledger so it can be
 * reconciled rather than silently lost. The database function is itself
 * idempotent, so a retry cannot refund a credit twice.
 */
async function finalizeCredit(
  adminClient: ReturnType<typeof createClient>,
  reservationId: string,
  succeeded: boolean,
  actorUserId: string,
): Promise<void> {
  try {
    await adminClient.rpc('sms_credit_finalize', {
      p_reservation_id: reservationId,
      p_succeeded: succeeded,
      p_actor_user_id: actorUserId,
    });
  } catch {
    // Intentionally ignored; see above.
  }
}

/**
 * Reads the company-approved Sailup sender ID. Returns null when the company has
 * no sender configured, or when the column is not deployed yet.
 */
async function loadSenderId(
  adminClient: ReturnType<typeof createClient>,
  companyId: string,
): Promise<string | null> {
  const { data, error } = await adminClient
    .from('companies')
    .select('sms_sender_id')
    .eq('id', companyId)
    .maybeSingle();
  if (error || !data) return null;
  const value = (data as { sms_sender_id?: string | null }).sms_sender_id;
  return value && value.trim().length > 0 ? value.trim() : null;
}

/**
 * A Sailup sender ID is either a numeric MSISDN (max 15 digits) or an
 * alphanumeric ID of 3-11 characters. This mirrors the database check
 * constraint. The value itself is never logged or returned to the client.
 */
function isValidSenderId(value: string): boolean {
  if (/^[0-9]{1,15}$/.test(value)) return true;
  return /^[A-Za-z0-9 ]{3,11}$/.test(value) && value.trim() === value;
}

/**
 * Short one-segment summary built from the stored delivery data, for example
 * "ALBNC: John Mensah | 5 bags | 251.6kg | 25/09/26".
 *
 * `label` is the company-approved sender ID, so the visible prefix always
 * matches the identity the message is actually sent from. Individual bag weights
 * are deliberately excluded; they remain on the printed receipt.
 */
async function buildMessage(
  adminClient: ReturnType<typeof createClient>,
  delivery: {
    id: string;
    company_id: string;
    supplier_name?: string | null;
    recorded_at?: string | null;
    record_type?: string | null;
    total_weight?: number | string | null;
    bag_count?: number | string | null;
  },
  label: string,
): Promise<string> {
  const { data: bags } = await adminClient
    .from('delivery_bag_weights')
    .select('weight')
    .eq('company_id', delivery.company_id)
    .eq('delivery_id', delivery.id);

  const rows = (bags ?? []) as { weight: number | string }[];
  const bagCount = rows.length;
  const total = rows.reduce((sum, row) => sum + Number(row.weight ?? 0), 0);
  const date = formatShortDate(delivery.recorded_at);
  const name = (delivery.supplier_name ?? 'Customer').replace(/\s+/g, ' ').trim();

  // A bulk weighing-bridge record has no bag weight rows, so its total and bag
  // count are read from the stored columns instead. It is still one SMS, and it
  // still costs exactly one credit.
  const isBulk = (delivery as { record_type?: string | null }).record_type === 'bulk';
  if (isBulk) {
    const storedTotal = Number(
      (delivery as { total_weight?: number | string | null }).total_weight ?? 0,
    );
    const storedBags = Number(
      (delivery as { bag_count?: number | string | null }).bag_count ?? 0,
    );
    if (!Number.isFinite(storedTotal) || storedTotal <= 0 || storedBags <= 0) {
      return truncate(`${label}: receipt ${delivery.id}`, MAX_SMS_LENGTH);
    }
    const bulkSuffix = ` | Bulk | ${storedBags} bags | ${storedTotal.toFixed(1)}kg | ${date}`;
    const bulkAvailable = Math.max(1, MAX_SMS_LENGTH - label.length - 2 - bulkSuffix.length);
    const bulkName = name.length > bulkAvailable ? `${name.substring(0, bulkAvailable - 1)}…` : name;
    return `${label}: ${bulkName}${bulkSuffix}`;
  }

  // A bulk weighing-bridge record has no bag weight rows, so its total and bag
  // count come from the stored columns. It is still ONE SMS and still costs
  // exactly ONE credit: nothing about the credit path changes here.
  if (delivery.record_type === 'bulk') {
    const storedTotal = Number(delivery.total_weight ?? 0);
    const storedBags = Number(delivery.bag_count ?? 0);
    if (!Number.isFinite(storedTotal) || storedTotal <= 0 || storedBags <= 0) {
      return truncate(`${label}: receipt ${delivery.id}`, MAX_SMS_LENGTH);
    }
    const bulkSuffix = ` | Bulk | ${storedBags} bags | ${storedTotal.toFixed(1)}kg | ${date}`;
    const bulkRoom = Math.max(1, MAX_SMS_LENGTH - label.length - 2 - bulkSuffix.length);
    const bulkName = name.length > bulkRoom ? `${name.substring(0, bulkRoom - 1)}…` : name;
    return `${label}: ${bulkName}${bulkSuffix}`;
  }

  if (bagCount === 0 || !Number.isFinite(total)) {
    return truncate(`${label}: receipt ${delivery.id}`, MAX_SMS_LENGTH);
  }
  const suffix = ` | ${bagCount} bags | ${total.toFixed(1)}kg | ${date}`;
  const available = Math.max(1, MAX_SMS_LENGTH - label.length - 2 - suffix.length);
  const trimmed = name.length > available ? `${name.substring(0, available - 1)}…` : name;
  return `${label}: ${trimmed}${suffix}`;
}

function formatShortDate(value?: string | null): string {
  if (!value) return '';
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return '';
  return `${String(date.getUTCDate()).padStart(2, '0')}/${String(
    date.getUTCMonth() + 1,
  ).padStart(2, '0')}/${String(date.getUTCFullYear()).slice(2)}`;
}

function truncate(value: string, max: number): string {
  if (max <= 1) return value.substring(0, max < 0 ? 0 : max);
  return value.length > max ? `${value.substring(0, max - 1)}…` : value;
}

function normalizeGhanaPhone(value?: string): string | null {
  if (!value) return null;
  let digits = value.replace(/[^0-9+]/g, '');
  if (digits.startsWith('+233')) digits = digits.slice(1);
  if (digits.startsWith('233')) {
    digits = digits.slice(3);
  } else if (digits.startsWith('0')) {
    digits = digits.slice(1);
  } else {
    return null;
  }
  if (digits.length !== 9 || !/^[2357]/.test(digits)) return null;
  return `233${digits}`;
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

