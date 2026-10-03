# Supabase setup

The Flutter client is configured for project `simhlgswtlpylpsdwyoy` with its publishable key. The key can be included in a client app; database access is limited by Supabase Auth and the row-level security policies in the migrations. Never put a service-role key in Flutter.

In the Supabase Dashboard, open **SQL Editor** and run these files in order for a new setup:

1. `migrations/202609230001_initial_schema.sql`
2. `migrations/202609230002_multi_company.sql`
3. `migrations/202609240001_company_branding_storage.sql`
4. `migrations/202609240002_recorded_by_identity.sql`

For an existing project where migrations 001, 002, and 003 are already deployed, run only the new `202609240002_recorded_by_identity.sql` migration. Do not rerun or edit completed migrations. The branding migration requires the multi-company schema from migration 002.

The branding migration adds the `logo_path` company field, a private PNG-only `company-logos` bucket, company-scoped Storage policies, and owner/admin-only company branding updates. Its live deployment has not been verified from this environment.

The recorder identity migration adds nullable recorder IDs to individual bag weights, allows legacy deliveries to remain unassigned, and uses database triggers to set new recorder IDs from `auth.uid()` and reject changes to an existing recorder. It deliberately does not backfill historical rows. Deploy this migration before updating the Flutter app so the client can read and write the new weight column.

Then deploy `functions/invite-company-member/index.ts` as the `invite-company-member` Edge Function. The function needs Supabase's `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY` Edge Function secrets. Keep the service-role key in Supabase only.

New owner accounts are created in the app's sign-up form. If email confirmation is enabled in Supabase Auth, the owner must confirm the email before signing in. Company membership and default products are provisioned by the database auth trigger.

Run the Windows app with `flutter run -d windows`. The publishable client key and project URL are already set as safe client configuration defaults in `lib/app/supabase_config.dart`.
