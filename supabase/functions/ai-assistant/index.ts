// Online, read-only business assistant for AL/BNC.
//
// The OpenAI key never comes near the Flutter app: the client holds only a
// normal user session, and this function is the single place that talks to the
// provider. Everything the model is allowed to see is gathered here, by this
// file, from an allow-list of read-only queries.
//
// The model never writes SQL and never chooses what to fetch. It receives a
// small, already-aggregated JSON snapshot of ONE company it has already been
// authorized for, and its only job is to phrase that snapshot as an answer.
import { createClient, type SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

/** OpenAI Responses API. This is the current documented endpoint. */
const OPENAI_RESPONSES_ENDPOINT = 'https://api.openai.com/v1/responses';

/** The role that the Flutter admin gate and this function both require. */
const ADMIN_ROLES = ['owner', 'admin'] as const;

/** Bounds the amount of data a single question can pull into a prompt. */
const MAX_RANGE_DAYS = 366;
const MAX_DELIVERY_ROWS = 5000;
const MAX_ANSWER_CHARS = 4000;
const MAX_QUESTION_CHARS = 500;

/**
 * A resolved, inclusive-by-day reporting window.
 *
 * `from` and `to` are UTC midnights, matching the half-open filter used by the
 * app's analytics repository: `>= from` and `< to + 1 day`.
 */
export type DateRange = { from: string; to: string };

/** A single delivery joined with its bag weights, as read from Postgres. */
type DeliveryRow = {
  id: string;
  product_name: string | null;
  supplier_name: string | null;
  recorded_by_user_id: string | null;
  recorded_at: string;
  record_type: string | null;
  total_weight: number | string | null;
  bag_count: number | null;
  bag_weights: { weight: number | string }[] | null;
};

function toNumber(value: unknown): number {
  if (value === null || value === undefined) return 0;
  const parsed = typeof value === 'number' ? value : Number(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

function startOfUtcDay(iso: string): number {
  return Date.parse(`${iso}T00:00:00.000Z`);
}

function isoDay(millis: number): string {
  return new Date(millis).toISOString().slice(0, 10);
}

/** A range covering exactly one UTC day. */
function dayRange(day: string): DateRange {
  return { from: day, to: day };
}

/**
 * Resolves the question's time window server-side.
 *
 * An explicit `from`/`to` from the client is honoured only after strict
 * validation, and the window is always clamped. This is a date range, not an
 * authority: it can never widen what company is read, which is derived purely
 * from `company_memberships`.
 */
export function resolveDateRange(
  question: string,
  explicitFrom: unknown,
  explicitTo: unknown,
  nowMillis: number,
): DateRange {
  const todayStart = Date.UTC(
    new Date(nowMillis).getUTCFullYear(),
    new Date(nowMillis).getUTCMonth(),
    new Date(nowMillis).getUTCDate(),
  );
  const DAY = 86_400_000;

  const explicitFromDay = typeof explicitFrom === 'string' ? explicitFrom : null;
  const explicitToDay = typeof explicitTo === 'string' ? explicitTo : null;
  if (explicitFromDay && explicitToDay) {
    const from = startOfUtcDay(explicitFromDay);
    const to = startOfUtcDay(explicitToDay);
    if (Number.isFinite(from) && Number.isFinite(to) && from <= to) {
      const cappedTo = Math.min(to, from + (MAX_RANGE_DAYS - 1) * DAY);
      return { from: isoDay(from), to: isoDay(cappedTo) };
    }
  }

  const text = question.toLowerCase();
  if (text.includes('yesterday')) {
    return dayRange(isoDay(todayStart - DAY));
  }
  if (text.includes('today') || text.includes('so far')) {
    return dayRange(isoDay(todayStart));
  }
  if (text.includes('this week')) {
    return { from: isoDay(todayStart - 6 * DAY), to: isoDay(todayStart) };
  }
  if (text.includes('last month') || text.includes('previous month')) {
    const end = new Date(todayStart);
    const startOfThisMonth = Date.UTC(end.getUTCFullYear(), end.getUTCMonth(), 1);
    return {
      from: isoDay(Date.UTC(end.getUTCFullYear(), end.getUTCMonth() - 1, 1)),
      to: isoDay(startOfThisMonth - DAY),
    };
  }
  if (text.includes('this month')) {
    return {
      from: isoDay(new Date(todayStart).getUTCDate() === 1
        ? todayStart
        : Date.UTC(new Date(todayStart).getUTCFullYear(), new Date(todayStart).getUTCMonth(), 1)),
      to: isoDay(todayStart),
    };
  }
  if (text.includes('this year')) {
    return {
      from: isoDay(Date.UTC(new Date(todayStart).getUTCFullYear(), 0, 1)),
      to: isoDay(todayStart),
    };
  }
  if (text.includes('last 30 days') || text.includes('past 30 days')) {
    return { from: isoDay(todayStart - 29 * DAY), to: isoDay(todayStart) };
  }
  if (text.includes('last 7 days') || text.includes('past week')) {
    return { from: isoDay(todayStart - 6 * DAY), to: isoDay(todayStart) };
  }
  // The safest default for a free-text question is a single day.
  return dayRange(isoDay(todayStart));
}


/**
 * The weight contributed by one delivery.
 *
 * This reproduces the app's analytics rule exactly: a weighing-bridge ('bulk')
 * record has no bag-weight rows, so it contributes its own stored total;
 * an individual record contributes the sum of its bag weights. The CASE shape
 * means a delivery is counted exactly once and a bulk record is never added on
 * top of bags that do not exist.
 */
export function deliveryWeight(row: DeliveryRow): number {
  if (row.record_type === 'bulk') return toNumber(row.total_weight);
  return (row.bag_weights ?? []).reduce(
    (sum, bag) => sum + toNumber(toNumber(bag.weight) > 0 ? bag.weight : 0),
    0,
  );
}

/** The bag count for one delivery, under the same rule as [deliveryWeight]. */
export function deliveryBags(row: DeliveryRow): number {
  if (row.record_type === 'bulk') return toNumber(row.bag_count);
  return (row.bag_weights ?? []).filter((bag) => toNumber(bag.weight) > 0).length;
}

type Totals = {
  totalWeight: number;
  totalBags: number;
  deliveryCount: number;
  bulkCount: number;
};

type Bucket = Totals & { name: string; _suppliers: Set<string> };

function emptyTotals(): Totals {
  return { totalWeight: 0, totalBags: 0, deliveryCount: 0, bulkCount: 0 };
}

function addTo(totals: Totals, row: DeliveryRow): void {
  totals.totalWeight += deliveryWeight(row);
  totals.totalBags += deliveryBags(row);
  totals.deliveryCount += 1;
  if (row.record_type === 'bulk') totals.bulkCount += 1;
}

function finalize(bucket: Bucket) {
  return {
    name: bucket.name,
    totalWeightKg: Number(bucket.totalWeight.toFixed(3)),
    totalBags: bucket.totalBags,
    deliveries: bucket.deliveryCount,
    individualDeliveries: bucket.deliveryCount - bucket.bulkCount,
    bulkDeliveries: bucket.bulkCount,
    uniqueSuppliers: bucket._suppliers.size,
    averageKgPerDelivery:
      bucket.deliveryCount === 0
        ? 0
        : Number((bucket.totalWeight / bucket.deliveryCount).toFixed(3)),
    averageKgPerBag:
      bucket.totalBags === 0
        ? 0
        : Number((bucket.totalWeight / bucket.totalBags).toFixed(3)),
  };
}

/**
 * The complete, read-only snapshot handed to the model.
 *
 * Everything the assistant can possibly state about this company is computed
 * here. There is no query the model can cause, and no row it can name.
 */
export function buildSnapshot(
  companyName: string,
  range: DateRange,
  rows: DeliveryRow[],
): Record<string, unknown> {
  const total = emptyTotals();
  const products = new Map<string, Bucket>();
  const suppliers = new Map<string, Bucket>();
  const recorders = new Map<string, Bucket>();
  const months = new Map<string, Bucket>();

  const bucketFor = (map: Map<string, Bucket>, name: string): Bucket => {
    let bucket = map.get(name);
    if (!bucket) {
      bucket = { name, ...emptyTotals(), _suppliers: new Set<string>() };
      map.set(name, bucket);
    }
    return bucket;
  };

  for (const row of rows) {
    addTo(total, row);

    const productName = row.product_name?.trim() || 'Unnamed product';
    const supplierName = row.supplier_name?.trim() || 'Unnamed supplier';

    for (const [map, name] of [
      [products, productName],
      [suppliers, supplierName],
      [recorders, row.recorded_by_user_id ?? 'unassigned'],
    ] as const) {
      const bucket = bucketFor(map as Map<string, Bucket>, name as string);
      addTo(bucket, row);
      bucket._suppliers.add(supplierName);
    }

    const month = bucketFor(months, row.recorded_at.slice(0, 7));
    addTo(month, row);
    month._suppliers.add(supplierName);
  }

  const byWeight = (a: Bucket, b: Bucket) => b.totalWeight - a.totalWeight;

  return {
    company: companyName,
    period: { from: range.from, to: range.to },
    totals: {
      totalWeightKg: Number(total.totalWeight.toFixed(3)),
      totalBags: total.totalBags,
      deliveries: total.deliveryCount,
      individualDeliveries: total.deliveryCount - total.bulkCount,
      bulkDeliveries: total.bulkCount,
      uniqueSuppliers: new Set(
        rows.map((row) => row.supplier_name?.trim() || 'Unnamed supplier'),
      ).size,
      averageKgPerDelivery:
        total.deliveryCount === 0
          ? 0
          : Number((total.totalWeight / total.deliveryCount).toFixed(3)),
      averageKgPerBag:
        total.totalBags === 0
          ? 0
          : Number((total.totalWeight / total.totalBags).toFixed(3)),
    },
    byProduct: [...products.values()].sort(byWeight).map(finalize),
    bySupplier: [...suppliers.values()].sort(byWeight).slice(0, 20).map(finalize),
    byRecorder: [...recorders.values()].sort(byWeight).map(finalize),
    byMonth: [...months.values()]
      .sort((a, b) => a.name.localeCompare(b.name))
      .map(finalize),
  };
}


/**
 * Reads the model id from the function's own environment.
 *
 * The model is deliberately NOT hardcoded: which model is available, and what
 * it costs, depends on the OpenAI account, so the operator pins it with
 * `supabase secrets set OPENAI_MODEL=<id>`. If it is unset the function
 * refuses to answer rather than silently guessing a model that may not exist.
 */
function readModel(): string | null {
  const model = Deno.env.get('OPENAI_MODEL')?.trim();
  return model ? model : null;
}

const SYSTEM_INSTRUCTIONS = `You are the business assistant for a cocoa buying company in Ghana.

You answer questions about ONE company's receiving data. You are given a JSON snapshot of that company's totals, broken down by product, supplier, recorder and month, already filtered to the date range the user asked about.

Rules you must always follow:
- Use ONLY numbers present in the snapshot. Never estimate, extrapolate or invent a figure.
- If the snapshot has no data for the question, say plainly that there is no receiving data for that period.
- All weights are in kilograms (kg) and bag counts are whole bags.
- A "bulk" delivery is a weighing-bridge record; an "individual" delivery is recorded bag by bag. Totals already include both correctly, so never add them together yourself.
- Be concise: a short paragraph or a few bullet points. Use the company's own naming.
- You cannot change any data. If asked to record, edit, delete or send anything, explain that you only report figures and that the user must do it in the app.`;

/** Raised for any provider-side problem, so the client gets a clean message. */
export class ProviderError extends Error {
  constructor(readonly code: string) {
    super(code);
    this.name = 'ProviderError';
  }
}

type ProviderRequest = {
  model: string;
  apiKey: string;
  system: string;
  question: string;
  snapshot: Record<string, unknown>;
  maxOutputTokens: number;
};

/** Provider abstraction: all OpenAI specifics live behind this interface. */
type Provider = {
  readonly name: string;
  complete(request: ProviderRequest): Promise<string>;
};

/**
 * The official OpenAI Responses API adapter.
 *
 * Request:  POST https://api.openai.com/v1/responses
 *           { model, instructions, input, max_output_tokens }
 * Response: { output: [ { content: [ { type: 'output_text', text } ] } ] }
 *
 * The text is read from `output[].content[].text`. The legacy Chat Completions
 * shape (`choices[0].message.content`) is NOT used.
 */
class OpenAiResponsesProvider implements Provider {
  readonly name = 'openai';

  async complete(request: ProviderRequest): Promise<string> {
    const input =
      `Reporting snapshot (JSON):\n${JSON.stringify(request.snapshot)}\n\n` +
      `Question: ${request.question}`;

    let response: Response;
    try {
      response = await fetch(OPENAI_RESPONSES_ENDPOINT, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${request.apiKey}`,
        },
        body: JSON.stringify({
          model: request.model,
          instructions: request.system,
          input,
          max_output_tokens: request.maxOutputTokens,
        }),
      });
    } catch {
      // The provider body is never echoed to the client, and the key is never
      // included in the error.
      throw new ProviderError('AI_PROVIDER_UNREACHABLE');
    }

    if (response.status === 429) throw new ProviderError('AI_RATE_LIMITED');
    if (response.status === 401 || response.status === 403) {
      throw new ProviderError('AI_NOT_CONFIGURED');
    }
    if (!response.ok) throw new ProviderError('AI_PROVIDER_UNAVAILABLE');

    let body: Record<string, unknown>;
    try {
      body = (await response.json()) as Record<string, unknown>;
    } catch {
      throw new ProviderError('AI_PROVIDER_UNAVAILABLE');
    }

    const answer = extractOutputText(body);
    if (!answer) throw new ProviderError('AI_EMPTY_RESPONSE');
    return answer.slice(0, MAX_ANSWER_CHARS);
  }
}

/** Pulls the assistant text out of a Responses API payload. */
export function extractOutputText(body: Record<string, unknown>): string {
  const output = body.output;
  if (!Array.isArray(output)) return '';
  const parts: string[] = [];
  for (const item of output) {
    if (!item || typeof item !== 'object') continue;
    const content = (item as { content?: unknown }).content;

/** The company this caller may read, as proven by the database. */
export type AuthorizedScope = { companyId: string; companyName: string };

/**
 * Decides which companies a caller may read, from membership rows only.
 *
 * This is deliberately a pure function so the security rule can be tested
 * without a database. The caller id and the membership rows both come from the
 * server; the request body is never an input, so a client cannot name the
 * company it wants. An inactive membership is not access, and only 'owner' and
 * 'admin' are accepted: a 'secretary' is refused, matching the Flutter route
 * guard.
 */
export function authorize(
  callerId: string,
  memberships: { company_id: string; role: string; is_active: boolean; user_id?: string }[],
  companies: { id: string; name: string }[],
): AuthorizedScope[] {
  if (!callerId) return [];
  const nameById = new Map(companies.map((company) => [company.id, company.name]));
  const scopes: AuthorizedScope[] = [];
  for (const membership of memberships) {
    if (membership.user_id !== undefined && membership.user_id !== callerId) continue;
    if (membership.is_active !== true) continue;
    if (!(ADMIN_ROLES as readonly string[]).includes(membership.role)) continue;
    const companyName = nameById.get(membership.company_id);
    if (!companyName) continue;
    scopes.push({ companyId: membership.company_id, companyName });
  }
  return scopes;
}

type MembershipRow = {
  company_id: string;
  role: string;
  is_active: boolean;
  user_id?: string;
};

/** Reads only this company's read-only receiving rows for the range. */
async function loadDeliveries(
  admin: SupabaseClient,
  scope: AuthorizedScope,
  range: DateRange,
): Promise<DeliveryRow[]> {
  // Half-open bounds, exactly as the app's analytics repository filters, so the
  // whole `to` day is included and nothing leaks into the next one.
  const fromIso = `${range.from}T00:00:00.000Z`;
  const toIso = new Date(startOfUtcDay(range.to) + 86_400_000).toISOString();

  const { data, error } = await admin
    .from('deliveries')
    .select(
      'id, company_id, recorded_at, status, record_type, total_weight, bag_count, ' +
        'product_name, supplier_name, recorded_by_user_id, ' +
        'delivery_bag_weights(weight)',
    )
    // The company is the SERVER's scope, applied here and nowhere else.
    .eq('company_id', scope.companyId)
    .neq('status', 'cancelled')
    .gte('recorded_at', fromIso)
    .lt('recorded_at', toIso)
    .order('recorded_at', { ascending: false })
    .limit(MAX_DELIVERY_ROWS);

  if (error) throw new ProviderError('AI_DATA_UNAVAILABLE');
  return ((data ?? []) as unknown as DeliveryRow[]).filter(
    (row) => row && typeof row.id === 'string',
  );
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (request.method !== 'POST') return json({ error: 'Method not allowed' }, 405);

  const url = Deno.env.get('SUPABASE_URL');
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !anonKey || !serviceKey) {
    return json({ error: 'AI_NOT_CONFIGURED' }, 500);
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

  // 2. Read the request. `company_id` is rejected outright, exactly as the SMS
  //    function rejects `sender_id`, so a caller can never even attempt to ask
  //    about a company they do not belong to.
  let input: { question?: unknown; from?: unknown; to?: unknown; company_id?: unknown };
  try {
    input = (await request.json()) as typeof input;
  } catch {
    return json({ error: 'Invalid request body' }, 400);
  }
  if (input.company_id != null) {
    return json({ error: 'COMPANY_ID_NOT_ACCEPTABLE' }, 400);
  }

  const question = typeof input.question === 'string' ? input.question.trim() : '';
  if (question.length === 0) return json({ error: 'A question is required' }, 400);
  if (question.length > MAX_QUESTION_CHARS) {
    return json({ error: 'Question is too long' }, 400);
  }

  const admin = createClient(url, serviceKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  // 3. Derive the caller's companies from the database, never from the request.
  const { data: membershipData, error: membershipError } = await admin
    .from('company_memberships')
    .select('company_id, role, is_active')
    .eq('user_id', callerId)
    .eq('is_active', true);
  if (membershipError) return json({ error: 'Could not verify company access' }, 403);

  const membershipRows = (membershipData ?? []) as MembershipRow[];
  const adminMemberships = membershipRows.filter((row) =>
    (ADMIN_ROLES as readonly string[]).includes(row.role),
  );
  if (adminMemberships.length === 0) {
    return json({ error: 'ADMIN_ACCESS_REQUIRED' }, 403);
  }

  const { data: companyData } = await admin
    .from('companies')
    .select('id, name')
    .in('id', adminMemberships.map((row) => row.company_id));

  const scopes = authorize(
    callerId,
    membershipRows.map((row) => ({ ...row, user_id: callerId })),
    (companyData ?? []) as { id: string; name: string }[],
  );
  if (scopes.length === 0) return json({ error: 'ADMIN_ACCESS_REQUIRED' }, 403);

  const scope = scopes[0];

  // 3a. Company AI entitlement.
  //
  // The admin/owner check above is preserved exactly. This adds a SECOND,
  // independent condition: the company itself must be entitled to the AI
  // premium, either through its own free AI trial or through a paid AI
  // subscription. Both are evaluated server-side from the database, so a client
  // cannot claim `aiEnabled: true` to get access.
  //
  // This check runs BEFORE any data is read and BEFORE the OpenAI request, so a
  // company without AI access never spends provider cost.
  //
  // The entitlement is read with the plain query builder rather than the
  // company_entitlements function. That keeps this file free of any RPC or raw
  // SQL call: the assistant still has no way to ask the database a question it
  // was not written to ask, and an unentitled company simply gets an empty
  // result. It is also deliberately forgiving: if the subscription tables are
  // not deployed yet, nothing is found, the check passes, and the assistant
  // keeps working, so the existing AI feature is not broken by rollout order.
  const aiNow = new Date().toISOString();
  const { data: aiEntitlement } = await admin
    .from('company_ai_entitlements')
    .select('status, trial_ends_at, current_period_end')
    .eq('company_id', scope.companyId)
    .maybeSingle();
  const { data: aiSubscription } = await admin
    .from('company_subscriptions')
    .select('status')
    .eq('company_id', scope.companyId)
    .maybeSingle();

  const aiTrialEndsAt = (aiEntitlement as { trial_ends_at?: string } | null)
      ?.trial_ends_at;
  const aiPeriodEnd =
      (aiEntitlement as { current_period_end?: string } | null)?.current_period_end;
  const aiStatus = (aiEntitlement as { status?: string } | null)?.status;
  const subStatus = (aiSubscription as { status?: string } | null)?.status;

  const aiEntitled = subStatus !== 'PAUSED' &&
      (((aiStatus === 'TRIAL' ||
              aiStatus === 'EXPIRED' ||
              aiStatus === 'ACTIVE') &&
          aiTrialEndsAt != null &&
          aiTrialEndsAt > aiNow) ||
        (aiPeriodEnd != null && aiPeriodEnd > aiNow));
  // No AI rows at all means the subscription tables are not deployed yet, so
  // the check is skipped and the assistant behaves exactly as it did before.
  const aiKnown = aiEntitlement != null || aiSubscription != null;

  if (aiKnown && !aiEntitled) {
    return json(
      {
        error: 'AI_NOT_ENTITLED',
        message:
          'The AI Assistant is a premium add-on. Ask an administrator to add the AI Assistant to your subscription to use it.',
      },
      402,
    );
  }

  const range = resolveDateRange(question, input.from, input.to, Date.now());

  // 4. Read the data. This function is read-only end to end: there is no
  //    insert, update or delete call anywhere in this file.
  let rows: DeliveryRow[];
  try {
    rows = await loadDeliveries(admin, scope, range);
  } catch {
    return json({ error: 'AI_DATA_UNAVAILABLE' }, 502);
  }

  const snapshot = buildSnapshot(scope.companyName, range, rows);

  // 5. Only now, with the data already gathered and frozen, call the provider.
  const apiKey = Deno.env.get('OPENAI_API_KEY')?.trim();
  const model = readModel();
  if (!apiKey || !model) return json({ error: 'AI_NOT_CONFIGURED' }, 500);

  try {
    const answer = await provider.complete({
      model,
      apiKey,
      system: SYSTEM_INSTRUCTIONS,
      question,
      snapshot,
      maxOutputTokens: 700,
    });
    return json({ answer, period: range });
  } catch (error) {
    // The provider's own error text is never returned to the client.
    const code = error instanceof ProviderError ? error.code : 'AI_PROVIDER_UNAVAILABLE';
    return json(
      { error: code, message: FRIENDLY_ERRORS[code] ?? FRIENDLY_ERRORS.AI_PROVIDER_UNAVAILABLE },
      502,
    );
  }
});


/** What the Flutter client turns into a user-visible sentence. */
const FRIENDLY_ERRORS: Record<string, string> = {
  AI_NOT_CONFIGURED:
    'The AI Assistant is not configured yet. An administrator must set the OpenAI key and model for this app.',
  AI_RATE_LIMITED: 'The AI Assistant is busy right now. Please try again in a moment.',
  AI_PROVIDER_UNREACHABLE:
    'AI Assistant requires an internet connection. Please check your network and try again.',
  AI_PROVIDER_UNAVAILABLE:
    'The AI Assistant is temporarily unavailable. Please try again shortly.',
  AI_EMPTY_RESPONSE:
    'The AI Assistant did not return an answer. Please try rephrasing your question.',
  AI_DATA_UNAVAILABLE:
    'The AI Assistant could not read your company data just now. Please try again.',
};

    if (!Array.isArray(content)) continue;
    for (const part of content) {
      if (!part || typeof part !== 'object') continue;
      const text = (part as { text?: unknown }).text;
      if (typeof text === 'string' && text.trim().length > 0) {
        parts.push(text);
      }
    }
  }
  return parts.join('').trim();
}

const provider: Provider = new OpenAiResponsesProvider();
