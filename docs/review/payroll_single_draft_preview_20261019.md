# Single draft read-only preflight candidate

Review-only source; no production SQL was executed and no migration or app wiring is supplied.
Depends on the previously saved single-draft recalculation candidate and the reviewed NULL-category fix.

This closes the missing authenticated source-digest acquisition step. It returns **the current draft**, not a simulated post-recalculation payslip. `projected_calculation` is explicitly null. It never runs refresh, sync, finalization, attendance corrections, settings saves, or DML. The current original row (`before_value`) and its server JSONB MD5 are provided only to the same existing payroll-settings editor authorization used by the apply candidate. This is private salary data: do not log, commit, put in Issue/tracker, or copy it into a public report.

Both private and public entry points revoke default PUBLIC/anon execute. The private definer uses an empty search path, `auth.uid()`, current account-access and existing edit authorization, explicit company/worker/month/statement/revision validation, automatic/unfinalized/draft checks, and final-snapshot refusal. It rereads the full row, final-snapshot state, source digest, and authorization before returning. The public wrapper is invoker. No new RLS policy or table grant is included.

## Intended gated operation

1. Authorized exact-scope preview; confirm current row, company, worker, full month, and revision privately.
2. Save the returned original envelope as a private durable backup with a separately checked integrity hash, restore scope, and approval record. The RPC does **not** save this file or claim that a backup exists: `backup_required=true` and `apply_confirmed=false` remain explicit.
3. Only after actual production prerequisites and explicit approval, call the saved apply API with the exact scope, revision and returned `expected_source`, and explicit confirmation. Old revision/source is rejected. Any error requires a fresh preview; never use finalization as a repair shortcut.
4. Independently compare new draft, audit, and original source/final snapshots. The old function backup does not restore payroll rows. A raw before-row is insufficient by itself to restore all triggered effects, so reviewed data restoration remains a deployment gate.

The MD5 fingerprints are optimistic-concurrency comparisons, not secret tokens, signatures, or permission grants. A preview cannot guarantee that no changes happen after its response. Existing apply API performs source-before/source-after and revision validation again. The response before-digest is informative and is not an extra enforced apply parameter.

## Isolated verification

`tool/verify_payroll_single_draft_preview.mjs` reuses existing synthetic scope setup, real saved calculator migrations and prior exact-draft API. It proves successful preview within `BEGIN READ ONLY`, full original draft/source and audit immutability; editor access and viewer/other-company/anonymous refusal; revision and exact-scope refusal; manual/finalized/snapshot refusal; synthetic source-drift rejection; and preview digest compatibility with the existing apply API. It then runs the saved real-calculator repair and source-preservation assertions. All values are synthetic. No real employee record was obtained.

Native PostgreSQL concurrency, live role-revocation/JWT HTTP behavior, full deployed helper/version comparison, actual before-backup/restore, app UI, user confirmation flow and production deployment are **not** claimed complete. Native PG17 evidence for the older apply API remains separate and is not relabeled as preview evidence. No new build, CI rerun, merge, or TestFlight upload is required by this source-only candidate.

Supabase docs checked 2026-10-19: database functions/security-definer/default EXECUTE and changelog PostgreSQL 15.19/17.11 notice. No ltree, legacy encryption, btree_gist or custom operator usage is introduced here.
