# SKO Supabase reproducibility

## Current state

The deployed SKO project is healthy and the pre-device security assertions pass, but the repository's oldest migration filenames do not exactly match the production migration history. Some of the earliest production schema was created before the current checked-in migration sequence was normalized.

This does **not** affect the existing production project or iPhone installation. It matters when rebuilding a brand-new Supabase project from zero.

## Historical drift currently expected

Production contains older historical migration names such as:

- `initial_sk_works_schema`
- `harden_membership_and_storage_policies`
- `move_rls_helpers_to_private_schema`
- early LINE webhook / communication-group migrations

The repository later converged those historical shapes through reconciliation migrations such as:

- `20260919010000_reconcile_chat_line_schema.sql`
- later RLS/security hardening migrations

Do not rewrite or delete already-applied historical migrations in production just to make names match.

## Safe Mac-day verification

Run:

```bash
bash tool/supabase_repro_preflight.sh
```

The script is intentionally non-destructive. It performs:

1. `supabase migration list --linked`
2. `supabase db lint --linked --fail-on error`
3. a public-schema `supabase db dump`
4. a Storage-schema diff

It never runs `db reset --linked`, `db push`, `migration repair`, or any destructive SQL.

## Baseline completion after Mac arrives

The generated files under `supabase/baseline/` are review artifacts. After reviewing them, the final reproducibility step is to create a clean baseline strategy using the current Supabase CLI. The preferred current Supabase workflow for remote-only historical changes is `supabase db pull`, but it can update migration history and therefore must be reviewed before it is used against production.

Never run `supabase db reset --linked` against the production SKO project.
