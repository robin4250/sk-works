# Canonical common payroll: offline deployment observation and unused restore preparation

Review artifacts only. No connection, migration, activation, publication, financial DML, or production observation has been performed by this preparation. The three calculation/publisher SQL units remain unchanged. Root is the sole DDL writer; its existing workflow changes are outside this commit.

## What is prepared

`tool/security/prepare_common_canonical_deployment_review.py` creates SQL files offline, with exclusive file creation and mode 0600. It cannot connect to a database or execute SQL. Candidate source is pinned to these SHA256 values:

| Unit | SHA256 |
| --- | --- |
| snapshot | `8265a81b98414eaa8a8ed92a781f9bfc2235dad5678bd7af24a041e26f09fe03` |
| resolver | `457ea816448c3f0fbf0bd66ae3902d33cca5126293fda0f0d0213ecf04a012b6` |
| publisher | `ca692c956dec5dfbe7ef07e8bfe50cb5cdd172221cf48c94b53953423b534754` |

Generate an observer with `python3 tool/security/prepare_common_canonical_deployment_review.py --observer-output /absolute/private/path/observer.sql.review-only`. This does not execute it. Root must separately review the result before using an authorized database tool. The observer runs in a repeatable-read, read-only transaction as postgres, with an empty search path and a 60-second statement timeout. It creates no database object. Its single JSON result contains:

- Full protected-row counts and SHA256 of ordered JSON rows for payroll statements/adjustments/audit, attendance, individual/company settings, workers/members/companies, and every table in the common, identity, unit, scope, and new canonical private schemas. Only hashes/counts are returned for application rows.
- Complete function definitions, owner and all pg_proc attributes including original ACLs for the related private schemas, payroll authorization/calculation functions, and public common/conditions/attendance-unit endpoints.
- Schema owner/ACL and table owner/ACL/RLS, columns/defaults, constraints, noninternal triggers and policies.
- Limited all-company aggregate counts for positive named legacy slots, existing activation, and their intersection with publications. It returns no company identifiers, rates, or employee rows in this aggregate.

The result is private because function definitions can contain internal implementation details. Do not commit or paste real observations into issues. Preserve the exact JSON and its SHA256 in a private durable checkpoint. An error, timeout, missing column/table, or different source baseline stops the process; do not weaken the observer or guards to force success.

## Installation boundary

Root must compose snapshot → resolver → publisher in one transaction, removing only each unit's outer transaction wrappers. Pin the complete resulting install SQL hash. A failed guard must roll back all three units. Before/after observations must be part of that controlled transaction, using the observer block with its outer read-only transaction removed by the reviewed operator composition; do not run a separate snapshot and describe it as atomic proof.

The newly added private activation tables must be empty and every pre-existing protected row digest unchanged after code installation. Four existing functions are replaced; all existing function attributes, owner and ACL must remain unchanged. Existing dependent functions must also be unchanged. Source hashes do not prove a transitive dependency closure by themselves; the broad observation records that closure for independent review.

“Default OFF” here means code installation inserts no activation/publication/receipt and changes no salary rows. It is not a central kill switch. New authenticated endpoints are callable after installation, and a currently authorized company administrator can explicitly approve activation/publication. Coordinate the deployment boundary and client capability gate. Installing the replacement v1 publisher also intentionally refuses new v1 publishes for positive legacy slots or per-type mode; an already-activated company's old client can therefore be affected before new financial activation. Review the all-company impact counts first. A nonzero affected count needs a concrete rollout decision, not an assertion of unchanged old publication behavior.

## Unused restore template

After independently verifying an actual default-OFF installation, generate the private template with `python3 tool/security/prepare_common_canonical_deployment_review.py --before /absolute/private/path/before.json --after /absolute/private/path/after.json --restore-output /absolute/private/path/unused-restore.sql.review-only`.

Generation refuses unless:

1. The four originals have the reviewed pre-install source hashes and owner postgres; all original pg_proc attributes, including ACLs, are preserved.
2. Added/replaced function bodies match the exact pinned three source units. Only the expected eleven functions, three tables, and canonical private schema were added.
3. Every existing protected table digest/count is identical before/after; all three new activation tables are empty. Existing routines outside the four replacements are identical.

Execution is still a separate, unapproved step. The generated SQL takes deterministic ACCESS EXCLUSIVE locks on all observed protected tables before checking unused status, then demands an exact match to the complete post-install catalog/data observation. This blocks application writers during the guard/restore interval. Root must remain the sole DDL writer; the source/metadata guard is not concurrent-DDL CAS. It restores only the saved original four CREATE OR REPLACE definitions; their saved owner/ACL must already match and remain preserved by CREATE OR REPLACE. It drops exactly the eleven added functions, three empty tables, and new schema with RESTRICT semantics, never CASCADE. An exact comparison to the original complete observation is required before COMMIT.

Any changed publication/receipt, salary, attendance, original setting, role, function, policy, schema or activation state refuses this unused restore. Do not edit its expected observation, delete a receipt/event, disable immutable triggers, or manufacture a “still unused” state. This is not an undo for financial application. A used installation requires a separate reviewed forward correction; do not erase financial or approval history.

## Validation and unfinished work

Six offline guard tests pass: synthetic unused generation, changed pinned source refusal, changed original ACL refusal, used activation refusal, changed publication/receipt refusal, unexpected function refusal. Python compilation and whitespace checks pass. `tool/verify_company_common_canonical_deployment.mjs` now reuses the existing synthetic payroll scope setup and exact canonical baseline. On PGlite's PG17 runtime it passed the observer parser/runtime, three-unit install → generated unused restore → exact original catalog/data observation, then reinstall with newly captured OIDs. It also passed required-table-missing refusal, changed original-row digest refusal, changed function ACL refusal, and used activation metadata refusal, checking that refused restore leaves its complete observed state unchanged. The observer's SQL loop record is named `obsrel` to avoid a runtime collision with the company-rate query's `r` alias. Required baseline table/schema inventories are checked before hashing; missing objects are never silently omitted.

The runner accepts the existing native fixture adapter (`node tool/verify_company_common_canonical_deployment.mjs <absolute pg/lib/index.js> postgres`) only for the owned loopback database `/sko_common_legacy_fixture`, and requires PostgreSQL major 17. Native execution has not been performed locally (Docker unavailable). Root should add a dedicated fresh-db matrix entry to the existing PG17 workflow, run its PGlite command with the locked package path, and then the native command with `SKO_COMMON_LEGACY_FIXTURE_URL` set to the existing loopback fixture URL. The runner forbids private-rate fixture input and removes only its own temporary synthetic observation files. No hosted URL is accepted by its native adapter.

Do not apply the template to production until the native PG17/Supabase-ACL variant and operator review pass. This proof does not establish network lost-COMMIT recovery or mixed financial writer behavior. Financial activation remains a separate stage after actual target preview, approval, client delivery, and final data-flow checks.

The inherited finalized-card gap is corrected in reviewed dependency commit `f408df2ed43ac29b81f3f5786807fd12f59a1607`: finalized_at populated now selects frozen saved items even when workflow remains draft. Its future fixture separately covers nonempty and empty saved snapshots. This preparation synchronizes those exact resolver/publisher files and pins their new hashes; no independent financial SQL edits are introduced here. The original old-unit deployment proof remains recorded in commit `1149538a27af4b524a1e3cb706af7ba893a04501`. The updated three-unit bundle repeated the same PGlite PG17 observer/install/unused-restore, missing-baseline, stale-row, changed-ACL, and used-activation proof successfully. Native CI remains required.
