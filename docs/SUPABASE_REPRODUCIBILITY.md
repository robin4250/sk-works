# SKO Supabase reproducibility

## Current state

The deployed SKO project is healthy and the pre-device security assertions pass, but the repository's oldest migration filenames do not exactly match the production migration history. Some of the earliest production schema was created before the current checked-in migration sequence was normalized.

This does **not** affect the existing production project or iPhone installation. It matters when rebuilding a brand-new Supabase project from zero.

## Historical drift currently expected

As verified on 2026-09-21, production has historical migration names that are not present as same-named files in Git:

- `initial_sk_works_schema`
- `harden_membership_and_storage_policies`
- `move_rls_helpers_to_private_schema`
- `add_line_webhook_event_staging`
- `add_communication_groups_and_line_bindings`
- `allow_line_webhook_service_inserts`
- `line_webhook_event_deduplication`
- `chat_message_line_external_dedupe`

The repository has early replacement/reconciliation files whose names do not appear in the remote history under the same names:

- `add_communication_chat`
- `add_line_bridge_foundation`
- `add_qualification_certificate_storage`

The repository later converged the production chat/LINE shape through `20260919010000_reconcile_chat_line_schema.sql` and subsequent hardening migrations. Newer security migrations from the pre-device hardening period are present in both the deployed schema and Git history by behavior, even when their generated remote timestamps differ from the checked-in filename timestamps.

These name differences are historical tracking drift, not evidence that the deployed schema is currently missing the corresponding tables or policies.

Do not rewrite or delete already-applied historical migrations in production just to make names match.

## Safe Mac-day verification

Run:

```bash
bash tool/supabase_repro_preflight.sh
```

The script is intentionally non-destructive. It performs:

1. `supabase migration list`
2. `supabase db lint --linked --fail-on error`
3. a public-schema `supabase db dump`
4. a Storage-schema diff
5. a direct Storage bucket metadata snapshot when `psql` + `SUPABASE_DB_URL` are available, because bucket changes are a documented `db diff` limitation
6. the production `tool/supabase_security_assertions.sql` audit
7. semantic capability markers for configurable approvers, employee onboarding, admin initial setup, nearest-station support, and the private onboarding-document bucket

It never runs `db reset --linked`, `db push`, `migration repair`, or any destructive SQL.

## Baseline completion after Mac arrives

The generated files under `supabase/baseline/` are review artifacts. After reviewing them, the final reproducibility step is to create a clean baseline strategy using the current Supabase CLI. The preferred current Supabase workflow for remote-only historical changes is `supabase db pull`, but it can update migration history and therefore must be reviewed before it is used against production.

Never run `supabase db reset --linked` against the production SKO project.


## Latest semantic baseline

Migration names can drift historically, so current reproducibility is not judged by filenames alone. The preflight also verifies the deployed schema contains the latest required SKO capabilities:

- configurable company approval assignees
- employee invitation/onboarding state
- admin initial setup progress and company rate settings
- nearest-station field on sites
- private employee onboarding document Storage
- invite-time sub-admin / approval-assignee intent columns and the 3-person approver limit guard
- full pre-device database security assertions

This lets historical migration-name drift remain documented without using destructive `migration repair`.
