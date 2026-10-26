# MTT – Quản lý bán xe

Continued from `ducmanhsuaxe247-stack/MTT-quanlybanxe` commit `adca5c5e16da239798e9ac3bd8663d8b89c55f23`.
Existing UI, inventory, sales, targets, expenses, reports and JSON backup/import are retained. The old HTML URL redirects to `index.html`. The October 26 backup/export additions were carried forward from the user's saved upgrade.

## Deployment status

The application code is ready for Supabase configuration. Real authentication and multi-device verification require access to the user's Supabase project. No credentials, users, live business data, or remote migrations have been created by this code change. This must not be reported as a working connected business system until the live checks below pass.

## Setup

1. Review and run `supabase/001_mtt_cloud.sql` in the intended Supabase SQL Editor. It creates `mtt_app_state` and audit metadata; it does not copy or overwrite pre-existing business tables. If `mtt_vehicles` / `mtt_sales` already contain real data, plan and verify their migration before importing backups or enabling writes. Existing `mtt_profiles` are reused. This version is for one store per project.
2. Create the intended owner in Supabase Authentication with a password chosen privately by the owner. Set the `owner_email` variable in `supabase/002_owner.sql` privately in the SQL Editor, then run it to approve that exact account. Do not commit personal account details. No default password exists. Sign in using the account email.
3. Set the public Project URL and publishable/anon key in `config.js` for a shared deployment. Alternatively enter them on the login screen for that device. Never include service_role, database passwords or access tokens. Public config is the only data stored in localStorage; authenticated sessions are in memory and end on page reload.
4. Add other Auth users, then insert their `user_id`, `full_name`, `role='sales'`, `approved=true` into `mtt_profiles` through the administrative SQL Editor. The client cannot approve itself or assign its own role. `viewer` users can read safe inventory but cannot sell. Only owners may edit stock, targets, expenses or import/export backups.
5. `node build.mjs` creates `dist/`. Deploy static assets over HTTPS.
6. Sign in from two devices. Verify stock changes, stale-write rejection, staff redaction, logout, unavailable network, and backup restore using test records before production use.

## Persistence and compatibility

The server stores the existing JSON data format with a revision number. Writes use a row lock and expected revision, preventing stale snapshots from overwriting newer edits. Sales calculate cost on the server, deduct stock in the same transaction and use request IDs to prevent duplicate deductions on retry. State polls every 30 seconds while idle; manual sync is available. This preserves legacy text IDs without silently changing existing records. The approach is suited to a small single-store dataset; snapshots and photos are capped at 15 MiB. Larger datasets should be migrated to normalized tables/storage with a separate migration plan.

Existing local data is never uploaded automatically, and sample data is never seeded into Supabase. Export a JSON backup from the old device and explicitly import it as owner. Export current server data before a replacement import. `mtt_sales_demo_v1` remains untouched. Existing files do not gain access to old-origin browser storage just because the new URL is deployed.

## Verification

`tests/cloud.test.mjs` exercises PostgreSQL logic through PGlite with test-only Auth stubs. Install `@electric-sql/pglite` outside the source repository and set `MTT_QA_MODULES` to its node_modules directory. `tests/ui.test.mjs` uses linkedom for offline DOM smoke tests with a mocked Supabase client. These do not replace tests against Supabase Auth/PostgREST on the actual project.

Supabase client: vendored UMD `@supabase/supabase-js` 2.57.4 (MIT), fetched from jsDelivr. Official reference: https://supabase.com/docs/guides/auth/passwords and https://supabase.com/docs/guides/database/functions
