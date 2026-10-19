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

Native PostgreSQL concurrency, live role-revocation/JWT HTTP behavior, full deployed helper/version comparison, actual before-backup/restore, app UI, user confirmation flow and production deployment are **not** claimed complete. Native PG17 evidence for the older apply API remains separate and is not relabeled as preview evidence. This candidate does not require a TestFlight upload. Its integration head receives the dedicated isolated CI below; prior source results do not substitute for that head.

Supabase docs checked 2026-10-19: database functions/security-definer/default EXECUTE and changelog PostgreSQL 15.19/17.11 notice. No ltree, legacy encryption, btree_gist or custom operator usage is introduced here.

## Additional dependency guard and native verification

The installation candidate now requires the exact saved fingerprint and single-draft apply function bodies, both VOLATILE security definers. A name/signature alone is insufficient. Each deliberately drifted dependency is rejected before a preview endpoint is created, followed by restoration of the synthetic original. Other production helper definitions, owners, ACLs, policies and runtime JWT behavior still require the separate live prerequisite review; these two guards do not certify the entire dependency closure.

The earlier preview head `9456aedf3e0ed9f014ee9c8b995be97eb8eedce8` passed native PostgreSQL 17 verification in run `39178754678`, job `117826837384`, as well as its PGlite fixture. This establishes native read-only invocation and the isolated refusal/preservation matrix, not native concurrent preview/writer behavior or live JWT access. The added body guards pass locally in PGlite; their new source head must receive its own automatic native result before being recorded as native-verified.

## Integration with the saved apply candidate (2026-10-19)

The SQL and verifier are reused from source `73d4dab5ef75830f316524bb26d2d58bba27cbde`, without changing their function bodies or assertions. This integration depends on PR #1256 and adds its own fresh PostgreSQL 17 service job. PGlite and native read-only invocation, dependency-drift refusal, authorization/scope/revision refusal, original-row/audit preservation and compatibility with the apply digest are rerun on this head. Results must be read from that head's workflow.

The public endpoint remains review-only: it is not placed in a deployment migration, invoked against production, or wired into the application. A separately saved limited production checkpoint is not a full dependency/side-effect backup or a tested restoration. No actual salary data, identities, checkpoint contents, or authentication credentials are included here. Native concurrent preview/writer and real JWT/Data API behavior remain separate work.

## Concurrent read-only verification schedule

A new native verifier observes a real lock wait during the second source digest of the preview request, while that request remains in READ ONLY. Only a disposable fixture wrapper uses local configuration and an advisory lock to schedule the wait. A second connection commits a non-cooperative source change, then a separate schedule revokes company membership. The verifier requires 40001/42501 respectively and unchanged payroll row, audit, attendance/settings and final snapshots, restores the original helper, rejects repeatable-read and permits a normal read-only request. This new head needs its own native success before those schedules are counted as verified. It does not prove real JWT/Auth behavior or prevent changes after a successful response.
