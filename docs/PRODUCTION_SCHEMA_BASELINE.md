# Production Supabase Schema Baseline

Verified against the deployed SKO Supabase project on 2026-09-21.

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


## 2026-09-21 pre-device hardening baseline

The following production invariants have now been verified and should be preserved:

- every public table has RLS enabled;
- the `anon` role has no direct public-table privileges and no public SECURITY DEFINER RPC execute privileges;
- all six SKO Storage buckets are private;
- attendance evidence is visible only to the worker or an attendance manager;
- worker documents and qualification certificates are visible only to the worker or a people manager;
- worker / partner-company phone, email, address, and notes are not directly selectable by ordinary authenticated sessions;
- customer billing details require invoice-view permission;
- direct `company_members` reads are self-scoped;
- LINE binding metadata is owner/admin-only;
- direct membership writes are RPC-only;
- the initial owner role cannot be demoted by the permission RPC;
- private Storage buckets have explicit file-size limits;
- authenticated CRUD grants without a matching RLS policy have been removed;
- the current repeatable audit is `tool/supabase_security_assertions.sql`.

The production audit currently returns:

```
SKO pre-device database security assertions passed
```

The repository may still contain historical migration-name differences from the earliest production setup. These are tracked separately in `docs/SUPABASE_REPRODUCIBILITY.md`; do not rewrite already-applied production migration history merely to make names match.
