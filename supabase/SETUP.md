# Supabase setup

The Flutter client is configured for project `simhlgswtlpylpsdwyoy` with its publishable key. The key can be included in a client app; database access is limited by Supabase Auth and the row-level security policies in the migrations. Never put a service-role key in Flutter.

In the Supabase Dashboard, open **SQL Editor** and run these files in order for a new setup:

1. `migrations/202609230001_initial_schema.sql`
2. `migrations/202609230002_multi_company.sql`
3. `migrations/202609240001_company_branding_storage.sql`
4. `migrations/202609240002_recorded_by_identity.sql`
5. `migrations/202609250001_company_sms_sender_id.sql`

For an existing project where earlier migrations are already deployed, run only the new ones. Do not rerun or edit completed migrations. The branding migration requires the multi-company schema from migration 002.

The branding migration adds the `logo_path` company field, a private PNG-only `company-logos` bucket, company-scoped Storage policies, and owner/admin-only company branding updates. Its live deployment has not been verified from this environment.

The recorder identity migration adds nullable recorder IDs to individual bag weights, allows legacy deliveries to remain unassigned, and uses database triggers to set new recorder IDs from `auth.uid()` and reject changes to an existing recorder. It deliberately does not backfill historical rows. Deploy this migration before updating the Flutter app so the client can read and write the new weight column.

## SMS receipts (Sailup)

Migration `202609250001_company_sms_sender_id.sql` adds the nullable `companies.sms_sender_id` column, a check constraint for the Sailup sender ID format, and an owner/admin-only column grant. It reuses the existing `companies_owner_admin_update` RLS path, so no new policy is created and existing isolation is unchanged.

Deploy `functions/send-sms-receipt/index.ts` as the `send-sms-receipt` Edge Function. It needs the standard `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY` secrets, plus `SAILUP_API_KEY`, which is read only inside the function. Never place the Sailup key in the Flutter app.

The function derives the company from the caller's `company_memberships` and the delivery's `company_id`, then reads that company's `sms_sender_id`. The client never sends or chooses a sender ID; a request containing `sender_id` or `from` is rejected with `SENDER_ID_NOT_ACCEPTABLE`. Sailup HTTP 202 is recorded as `queued`, never as `delivered`, and a `sender_not_approved` response is surfaced as `SMS_SENDER_ID_NOT_APPROVED` without echoing the provider body.

Before SMS works, an owner or admin must register the sender ID in Sailup and then save the same value once in the app under **Settings → Company branding → SMS sender ID**, or with `update companies set sms_sender_id = '...' where id = '<company id>';`. Until that value exists and is approved in Sailup, sending a receipt reports `SMS_SENDER_ID_NOT_CONFIGURED`.

## AI business assistant (OpenAI)

The local rule-based assistant has been replaced. `AppRoutes.assistant` (`/admin/assistant`) and its admin gate are unchanged, but the screen now calls the `ai-assistant` Edge Function instead of querying local SQLite, so it requires an internet connection. There is no offline fallback.

Deploy `functions/ai-assistant/index.ts` as the `ai-assistant` Edge Function. It needs the standard `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY` secrets plus two of its own:

```
supabase secrets set OPENAI_API_KEY=<key>
supabase secrets set OPENAI_MODEL=<model id>
```

`OPENAI_API_KEY` is read only inside the function and must never be placed in the Flutter app, in any Dart file, or in Git. `OPENAI_MODEL` is deliberately **not** hardcoded: which models are available and what they cost depends on the OpenAI account, so pin an id that your account can actually call. If either secret is missing the function returns `AI_NOT_CONFIGURED` and tells the user an administrator must configure it, rather than guessing a model.

The function uses the OpenAI **Responses API** (`POST https://api.openai.com/v1/responses` with `model`, `instructions`, `input`, `max_output_tokens`, reading the answer from `output[].content[].text`). Legacy Chat Completions is not used.

Security properties, all enforced server-side:

- The caller is authenticated from the `Authorization` header, and the company is derived from that user's own `company_memberships` rows. A body containing `company_id` is rejected with `COMPANY_ID_NOT_ACCEPTABLE`, so the client can never name the company it is asking about.
- Only `owner` and `admin` memberships are accepted; a secretary is refused with `ADMIN_ACCESS_REQUIRED`, matching the Flutter route guard.
- Every delivery read is filtered to the authorized `company_id`, and the function is read-only: it contains no insert, update, upsert, delete or raw SQL. The model cannot write anything, and its output is only ever returned to the user as text.
- The model receives an already-aggregated JSON snapshot. It never generates or executes SQL, and it is instructed to use only the figures it is given.
- Provider errors are mapped to stable codes and friendly wording, so no provider body and no key ever reach the client.

The `index_test.ts` unit tests cover the authorization rule, the date ranges, the individual/bulk weight and bag calculations, and the Responses API response parsing. Run them with `deno test supabase/functions/ai-assistant/`.

Individual and bulk deliveries are totalled with the same rule the app's analytics repository uses: a weighing-bridge record contributes its stored `total_weight`/`bag_count`, and an individual record contributes the sum of its bag weights, so no delivery is ever counted twice.


Then deploy `functions/invite-company-member/index.ts` as the `invite-company-member` Edge Function. The function needs Supabase's `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY` Edge Function secrets. Keep the service-role key in Supabase only.

New owner accounts are created in the app's sign-up form. If email confirmation is enabled in Supabase Auth, the owner must confirm the email before signing in. Company membership and default products are provisioned by the database auth trigger.

Run the Windows app with `flutter run -d windows`. The publishable client key and project URL are already set as safe client configuration defaults in `lib/app/supabase_config.dart`.
