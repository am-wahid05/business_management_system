// Unit tests for the ai-assistant Edge Function's pure logic.
//
// Run with:  deno test supabase/functions/ai-assistant/
//
// The parts of this function that can be tested without a database are the
// authorization rule, the date resolution, the individual/bulk aggregation and
// the Responses API response parsing. They are written as pure functions
// precisely so they can be covered here.
import {
  authorize,
  buildSnapshot,
  deliveryBags,
  deliveryWeight,
  extractOutputText,
  resolveDateRange,
  type DeliveryRow,
} from './index.ts';

const NOW = Date.UTC(2026, 8, 26, 12, 0, 0); // 26 Sep 2026, midday UTC.

function individual(
  id: string,
  weights: number[],
  extra: Partial<DeliveryRow> = {},
): DeliveryRow {
  return {
    id,
    product_name: 'Cocoa',
    supplier_name: 'Kofi',
    recorded_by_user_id: 'user-1',
    recorded_at: '2026-09-26T08:00:00.000Z',
    record_type: 'individual',
    total_weight: null,
    bag_count: null,
    bag_weights: weights.map((weight) => ({ weight })),
    ...extra,
  };
}

function bulk(id: string, total: number, bags: number): DeliveryRow {
  return {
    id,
    product_name: 'Cocoa',
    supplier_name: 'Kofi',
    recorded_by_user_id: 'user-1',
    recorded_at: '2026-09-26T08:00:00.000Z',
    record_type: 'bulk',
    total_weight: total,
    bag_count: bags,
    bag_weights: [],
  };
}

Deno.test('individual delivery weight is the sum of its bag weights', () => {
  expect(deliveryWeight(individual('a', [10, 20, 12.5]))).toBe(42.5);
  expect(deliveryBags(individual('a', [10, 20, 12.5]))).toBe(3);
});

Deno.test('zero or negative bag weights are ignored, matching the app', () => {
  expect(deliveryWeight(individual('a', [10, 0, -5]))).toBe(10);
  expect(deliveryBags(individual('a', [10, 0, -5]))).toBe(1);
});

Deno.test('bulk delivery uses its stored total and bag count', () => {
  expect(deliveryWeight(bulk('b', 500, 20))).toBe(500);
  expect(deliveryBags(bulk('b', 500, 20))).toBe(20);
});

Deno.test('a bulk record is never double counted with bag rows', () => {
  // A weighing-bridge record has no bag rows; if one somehow did, the stored
  // total still wins, so the figure can never be inflated.
  const row = { ...bulk('b', 500, 20), bag_weights: [{ weight: 999 }] };
  expect(deliveryWeight(row)).toBe(500);
  expect(deliveryBags(row)).toBe(20);
});

Deno.test('snapshot totals combine individual and bulk exactly once', () => {
  const snapshot = buildSnapshot(
    'AL-BNC',
    { from: '2026-09-01', to: '2026-09-30' },
    [individual('a', [10, 20]), bulk('b', 500, 20)],
  ) as { totals: Record<string, number> };

  expect(snapshot.totals.totalWeightKg).toBe(530);
  expect(snapshot.totals.totalBags).toBe(22);
  expect(snapshot.totals.deliveries).toBe(2);
  expect(snapshot.totals.individualDeliveries).toBe(1);
  expect(snapshot.totals.bulkDeliveries).toBe(1);
  expect(snapshot.totals.averageKgPerDelivery).toBe(265);
});

Deno.test('an empty period reports zeroes rather than failing', () => {
  const snapshot = buildSnapshot(
    'AL-BNC',
    { from: '2026-09-01', to: '2026-09-30' },
    [],
  ) as { totals: Record<string, number>; byProduct: unknown[] };

  expect(snapshot.totals.totalWeightKg).toBe(0);
  expect(snapshot.totals.averageKgPerDelivery).toBe(0);
  expect(snapshot.totals.averageKgPerBag).toBe(0);
  expect(snapshot.byProduct).toEqual([]);
});

Deno.test('a secretary is refused, an admin is allowed', () => {
  const scopes = authorize(
    'user-1',
    [
      { company_id: 'c1', role: 'admin', is_active: true, user_id: 'user-1' },
      { company_id: 'c2', role: 'secretary', is_active: true, user_id: 'user-1' },
    ],
    [{ id: 'c1', name: 'AL-BNC' }],
  );
  expect(scopes).toEqual([{ companyId: 'c1', companyName: 'AL-BNC' }]);
});

Deno.test('an inactive membership is not access', () => {
  expect(
    authorize(
      'user-1',
      [{ company_id: 'c1', role: 'owner', is_active: false, user_id: 'user-1' }],
      [{ id: 'c1', name: 'AL-BNC' }],
    ),
  ).toEqual([]);
});


Deno.test('today resolves to a single day', () => {
  expect(resolveDateRange('How much today?', null, null, NOW)).toEqual({
    from: '2026-09-26',
    to: '2026-09-26',
  });
});

Deno.test('yesterday is the day before', () => {
  expect(resolveDateRange('what about yesterday', null, null, NOW)).toEqual({
    from: '2026-09-25',
    to: '2026-09-25',
  });
});

Deno.test('this month starts on the first and ends today', () => {
  expect(resolveDateRange('this month total', null, null, NOW)).toEqual({
    from: '2026-09-01',
    to: '2026-09-26',
  });
});

Deno.test('last month is a whole previous month', () => {
  expect(resolveDateRange('last month', null, null, NOW)).toEqual({
    from: '2026-08-01',
    to: '2026-08-31',
  });
});

Deno.test('this year starts in January', () => {
  expect(resolveDateRange('this year', null, null, NOW).from).toBe('2026-01-01');
});

Deno.test('an unrecognised question defaults to today', () => {
  expect(resolveDateRange('tell me about cocoa', null, null, NOW)).toEqual({
    from: '2026-09-26',
    to: '2026-09-26',
  });
});

Deno.test('an explicit range is honoured', () => {
  expect(resolveDateRange('anything', '2026-01-01', '2026-01-31', NOW)).toEqual({
    from: '2026-01-01',
    to: '2026-01-31',
  });
});

Deno.test('a reversed explicit range falls back to today', () => {
  expect(
    resolveDateRange('anything', '2026-01-31', '2026-01-01', NOW).from,
  ).toBe('2026-09-26');
});

Deno.test('an over-long explicit range is clamped', () => {
  const range = resolveDateRange('anything', '2020-01-01', '2026-01-01', NOW);
  // 366 days inclusive, counting from 2020-01-01.
  expect(range.to).toBe('2020-12-31');
});

Deno.test('text is read from output[].content[].text', () => {
  expect(
    extractOutputText({
      output: [
        { type: 'reasoning', content: [] },
        { type: 'message', content: [{ type: 'output_text', text: '400 kg.' }] },
      ],
    }),
  ).toBe('400 kg.');
});

Deno.test('multiple text parts are joined', () => {
  expect(
    extractOutputText({
      output: [
        {
          content: [
            { type: 'output_text', text: '400 kg ' },
            { type: 'output_text', text: 'received.' },
          ],
        },
      ],
    }),
  ).toBe('400 kg received.');
});

Deno.test('a legacy chat-completions payload yields no text', () => {
  // The function must not fall back to the old shape.
  expect(extractOutputText({ choices: [{ message: { content: 'nope' } }] })).toBe('');
  expect(extractOutputText({})).toBe('');
});

Deno.test('a membership belonging to another user is ignored', () => {
  expect(
    authorize(
      'user-1',
      [{ company_id: 'c1', role: 'admin', is_active: true, user_id: 'user-2' }],
      [{ id: 'c1', name: 'AL-BNC' }],
    ),
  ).toEqual([]);
});

Deno.test('an unknown caller is authorized for nothing', () => {
  expect(authorize('', [], [])).toEqual([]);
});
