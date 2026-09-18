# Production Supabase Schema Baseline

Verified against the deployed SKO Supabase project on 2026-09-18.

This document records the production chat / LINE bridge shape so future work does not accidentally reintroduce older prototype table names.

## Active production chat tables

### communication_groups

Core columns:

- `id` uuid
- `company_id` uuid
- `site_id` uuid nullable
- `name` text
- `group_type` text
- `created_at` timestamptz
- `updated_at` timestamptz

### chat_messages

This is the active production chat table.

Core columns:

- `id` uuid
- `company_id` uuid
- `communication_group_id` uuid
- `sender_user_id` uuid nullable
- `sender_display_name` text nullable
- `origin` text
- `body` text
- `external_event_id` text nullable
- `external_message_id` text nullable
- `sent_at` timestamptz
- `created_at` timestamptz

Current production origin values are based on the deployed schema and include `sk_works`, `line`, and `import`.

Do not add new app code against the older prototype name `communication_messages`.

### line_group_bindings

Core columns:

- `id` uuid
- `line_group_id` text
- `company_id` uuid nullable
- `communication_group_id` uuid nullable
- `display_name` text nullable
- `status` text
- `discovered_at` timestamptz
- `updated_at` timestamptz

Production status values are:

- `pending`
- `active`
- `disabled`

The pending state intentionally allows a LINE group to be discovered before it is assigned to a company / SKO communication group.

Do not use the older prototype `is_enabled` column in new code.

### line_webhook_events

Raw webhook staging / deduplication table. This table is written by the LINE Edge Function using service-role access.

It currently has RLS enabled with no user-facing policy. That is intentional while the table remains service-only staging data.

## Deployed Edge Function

The active `line-webhook` Edge Function stores raw LINE events in `line_webhook_events`, resolves only `status=active` bindings, and writes routed text messages into `chat_messages`.

Repository source should stay byte-for-byte or behaviorally aligned with the deployed function before making further bridge changes.

## Migration history warning

Some older checked-in migrations describe the earlier prototype tables `communication_messages` and a required-company `line_group_bindings` structure with `is_enabled`.

Do not rewrite already-applied historical migrations in place.

Fresh-environment reproducibility is provided by `20260919010000_reconcile_chat_line_schema.sql`. It creates the production `chat_messages` shape, aligns the historical LINE binding table to the pending/active/disabled model, and leaves legacy prototype objects in place rather than destructively rewriting migration history.

The older `communication_messages` table remains a historical compatibility object only. New application code and new migrations must treat `chat_messages` as authoritative.

## Security decisions to preserve

- Raw LINE webhook staging is service-role only.
- A LINE group must not route into company chat until its binding is explicitly active.
- Ambiguous or unassigned LINE groups must remain unbound rather than being guessed.
- `create_company(text)` is intentionally callable by authenticated users for first-company onboarding; its SECURITY DEFINER behavior must remain narrowly scoped to that onboarding purpose and should be reviewed whenever the function changes.

## October rollout rule

Until worker, site, communication group, and LINE binding identities are confirmed, LINE-derived attendance must remain preview / candidate data. Do not silently finalize attendance or invoice records from a parsed LINE message.
