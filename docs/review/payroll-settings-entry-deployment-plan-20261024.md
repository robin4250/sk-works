# Payroll entry backend deployment preparation

Prepared after PR1337 head `4d2c8de78947af7e53823e84c5c7438ef4b5d444`. No production changes were performed by this task.

## Read-only observation

`tool/security/payroll_settings_entry_observation/catalog.read-only.sql` is one catalog-only `WITH … SELECT`. It reads no application or Auth rows. It records the existing two writer tables and their ACL/RLS/columns/constraints/indexes/triggers, resident-tax tables, relevant authorization/writer routine definitions/attributes/source hashes and new-object absence. Root should execute it, save the result privately, and compare the actual authorizer, writer order and triggers before creating an install artifact. Any unexpected dependency or partially present candidate must stop automatic installation.

## Partial rate defaults: exactly four new functions

The current candidate adds **two private functions and two public invoker RPCs**, not two functions total. Existing authorization is reused. No schema, table, policy, existing function definition, role or grant is changed by the candidate; EXECUTE is applied only to the four new function objects. The install has no INSERT/UPDATE of application rows: the writer statements live inside the new function body and run only from a later legitimate user's explicit save.

Before applying, root must verify that the existing private schema, authorizer, companies/rate table definitions, null/default rules and triggers match the reviewed assumptions. The candidate reads six numeric values from companies/rate settings. It updates only companies.tax_rate/default_welfare_rate/updated_at and the rate table's four unit amounts/updated_by/updated_at. It never copies or updates the old three allowance names/amounts/units.

For a bounded installer, reuse the already reviewed checkpoint-bound generator pattern from the PNG/common installers: fixed candidate hash; fixed namespace/routine inventory; a transaction; bounded lock/statement timeouts; company→rate table lock order; same-transaction protected catalog and canonical row count/hash observations; apply the reviewed unit body; assert existing catalog/rows/ACL/RLS/routines unchanged and exactly four new definitions/privileges. Preserve the full original private observation and postflight receipt. Do not claim an executable installer exists yet.

An unused restore may drop only those four new functions, after exact candidate source/ACL attributes and unchanged original writer tables are rechecked. Without a durable use receipt, unchanged values do not prove the write API has never been used. Therefore label this a bounded code removal, not a financial rollback, and do not offer it as safe after real saves. Once legitimate saves happen, preserve history and use a forward fix. No restore may rewind companies or rate data.

The synthetic Native PostgreSQL fixture succeeded on the preceding PR head: it verifies six-field save/CAS, original allowance preservation, exact retry, stale/invalid/foreign/employee rejection and actual authenticated wrapper calls. Its authorizer is a fixture stub, not proof of the production authorizer or RLS.

## Existing annual resident tax backend

Reuse `docs/candidates/resident_tax_annual_20261020.sql.review-only`, not a new annual storage design. Its installation creates one private schema, four private tables and fourteen functions (eleven private, three public read/save/undo wrappers). Existing tax schedule and payroll refresh functions are called at later explicit row updates; installation itself does not migrate tax amounts or mark employees confirmed.

The candidate already rejects unknown default ACLs and pins three source hashes: `resident_tax_private.save_state(uuid,uuid,bigint,text,text,jsonb,boolean)` → `0607111ec8cc09f32e6173df60ec4324`; `resident_tax_private.resolve(uuid,uuid,date)` → `9eee6842f1749d3133e5d6306de37f27`; `payroll_scope_private.lock_scopes(jsonb,boolean)` → `1bce36e2e59eeb8e0144c5743b8ea800`. Verify those exact live definitions/owners/search paths/ACLs and all transitive table/authorization dependencies. A mismatch is a blocker, not permission to replace existing functions with old versions.

Existing `tool/verify_resident_tax_annual.mjs` reuses the actual payroll-scope fixture and covers subset updates, explicit zero/same values, twelve-month exceptions, future-year boundaries, finalized/manual preservation, source CAS, retries, old-state undo and failure rollback. Reuse its existing PGlite/PG17 workflows. The current parent observation reported public annual read/save/undo routines absent; the fresh catalog query must confirm this before deployment.

A bounded annual installer must protect existing company/worker/payroll/resident state/entries/history and relevant payroll-finalization/refresh dependencies under the reviewed ordering, allow only the expected new schema/tables/functions, and verify zero initial confirmations/batches/changes/undos. An unused restore can only remove the new annual objects if all four tables remain empty and definitions/privileges and original tables match the protected checkpoint. It must never delete used annual audit data or undo actual tax updates. Runtime row undo is the existing audited, actor-bound RPC and is distinct from unused installation removal.

## Remaining gates

Fresh actual catalog review, transitive authorizer/trigger source review, protected financial count/hash checkpoint, exact-source native installation/restoration proof, reviewed deploy artifact, root production application, postflight and actual owner/iPhone use remain incomplete. UI merge alone does not make the partial-save or annual-tax backend operational.

## Checkpoint-bound generator candidate

`tool/security/prepare_company_rate_defaults_install.py` now prepares offline SQL from the normalized private checkpoint, the fixed four-function source hash and the observed source manifest. It repeats the same observer before and after under company→rate locks, rejects changed originals and unexpected function ACLs, and writes a new private file exclusively with mode 0600. Its code-removal mode requires unchanged original rows/catalog and exact new definitions. It never rewinds application rows and does not establish that an API was never used.

The existing native job now includes the actual legacy identity migration and the observed identity, unit-alias and tax trigger bodies. Authorization remains synthetic; the invoice-refresh leaf is a fixture recorder, not proof of full invoice recalculation. The installer proof tests stale checkpoints, late transaction failure, unknown default ACL rejection, zero writer-row effects on installation, exact unchanged-data code removal and refusal after a legitimate data save. These extensions are pending native CI; generated private SQL must not be treated as executable proof until they pass. Production application and owner/iPhone use remain separate gates.

## Actual catalog follow-up

Root's catalog-only observation was strictly parsed from the tool's bounded JSON envelope and saved privately. The four partial functions and annual objects are absent. The existing common authorizer is stable/security-definer with an empty search path; it calls its session verifier and permits editing only for owner/admin. The session verifier checks the authenticated/non-anonymous actor, account access and a matching unexpired auth.sessions entry. It is reused unchanged. All three annual pinned hashes match the current definitions.

The live companies columns are numeric(5,2) for tax and numeric(6,3) for welfare. The candidate now rejects surplus precision instead of allowing a database-rounded save to fail the client's exact receipt comparison. This is input validation, not automatic rounding or conversion.

Runtime scope correction: the old company_rate_settings UPDATE triggers also update adopted allowance identity version/history and compatibility observations, even if the old three values are unchanged. Updating the companies tax column triggers existing invoice refresh even when its numeric value is unchanged. The new six-field setter preserves those existing triggers; it does not disable or replace them. Thus direct assignments target six values/timestamps, but it is inaccurate to promise that no existing dependent history or refresh runs on a later legitimate save. Installation itself only creates the four functions and runs no application UPDATE.

checkpoint.read-only.sql reuses the same catalog fields and canonical JSONB row-digest pattern, normalized to an empty search path, UTC and ISO date style. It reads only the companies and rate writer tables to return count/SHA256, never their values, and reads no Auth rows. It must be run and saved privately before preparing a bounded install. Namespace and all authorizer/trigger source fingerprints are included. This is a read-only checkpoint, not a backup or a completed install/restore artifact. The wrapper uses READ ONLY and ends with ROLLBACK; an installer must repeat the same normalized observer in its own bounded write transaction under company→rate locks and compare the protected checkpoint before and after.
