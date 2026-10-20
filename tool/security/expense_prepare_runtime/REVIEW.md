# Expense prepare-only driver (2026-10-20)

This candidate does not connect to production, execute prepared SQL, install functions, enable v2 or convert the ¥1,000 draft. No successful fresh Mac checkpoint has been received. Existing verified `wow5lji8` native HTTP/JWT results are reused; they are not rerun here.

## Scope and inputs

The three source files under `source/` are byte-identical to `expense-production-readiness-20261020`. Existing `buildDefaultOffDeployment` and `buildCodeRestore` remain unchanged. No common-allowance-specific role validator is imported. Existing common and insurance objects are neither required to be absent nor touched; this is an expense-only catalog scope.

`owner_prepare_expense_install.py` is a Mac offline wrapper. It selects only the latest owner-private successful `expense-fresh-checkpoint-*`, verifies the status and exact private artifact SHA256, read-only result, exact target count, v2 count and conversion/rollout absence. It pins every JS generator input and source SHA256, refuses symlinks/unexpected source files, uses an already present local Node image resolved to its immutable ID, and runs that image with no network. It does not pull an image. An unavailable local `node:22.21.0` image stops preparation. It uses no DB password or database client. Private fresh code/catalog records and generated SQL must never be uploaded to GitHub/chat/CI.

It creates a new 0700 `expense-prepare-only-*` directory and 0600 files, never overwrites earlier evidence, and copies only a safe summary via pbcopy. Outputs are `private-prepared-install.sql.review-only` and `private-read-actual-after.sql.read-only`. These files are review artifacts, not automatically executed. Native execution of this helper has not been performed.

## Pre-COMMIT contract

The prepared install adds `SET LOCAL ROLE postgres` and an expense-specific guard before the original financial locks/DDL: current role must be postgres, session role must have actual PG17 SET permission, and complete fresh function source/OID/owner/ACL/attributes plus trigger/event-trigger catalog must exactly match the captured original. The unchanged generator then locks five financial tables, checks byte/row bounds, fresh financial digest, no v2/basis/converter/audit/rollout, applies the reviewed default-OFF source, verifies all new source/ACL/metadata and existing object preservation, and asserts business data unchanged before COMMIT. A later actual runner must use a dedicated connection, rollback on errors, and treat disconnect around COMMIT as unknown until a new read proves state. No post-COMMIT common validator may be reused.

The companion read uses a fresh REPEATABLE READ READ ONLY transaction with local postgres role. It captures actual installed catalog and business hash, not inferred OIDs. `prepareUnusedUndo` accepts only the exact reviewed eight source hashes and new-function owner/ACL/config/attributes, unchanged business hash, no v2/basis/converter/audit/rollout. It delegates restoration to the unchanged original generator and wraps it in a transaction with an execution-time rollout guard. Unknown later rollout blocks undo. Existing full actual-after catalog guard blocks subsequent changes; code restoration is not an amount reversal or used-data recovery.

## Verification

PGlite PostgreSQL 17 fixture passes: wrong execution identity refusal before DDL; old function ACL/source/OID drift refusal; wrong recorded owner refusal; full prepare/install with v1 draft and finalized rows; five financial tables unchanged; actual-after read; unknown after source/expanded ACL refusal; later rollout refusal preserving the installed state; successful unused undo returning exact source/OID/owner/ACL catalog; changed business/v2-used undo refusal. Python compilation passes and the driver runtime input hashes are independently checked. This is local fixture proof, not Mac native or production execution.

Run fixture from the existing `sk-works` directory. The fixture explicitly provisions service_role when absent, matching hosted default function grants without depending on a modified fixture copy. Exact verified command in this workspace:

```bash
node ../expense-prepare-driver-20261020/verify_expense_prepare_driver.mjs /workspace/scratch/736d0b1e377d/payroll-preservation/tool/security/fixture_dependencies/node_modules/@electric-sql/pglite/dist/index.js /workspace/scratch/736d0b1e377d/sk-works/tool/fixtures/expense_cost_fixture.mjs
```

It also passes against the original previously used `expense-off-deployment-preparation-20261020/tool/fixtures/expense_cost_fixture.mjs`. No Auth JWT is fabricated for production and no production SQL is included here.

Remaining: fresh checkpoint success; private generated SQL review; dedicated native install-only rehearsal; production default-OFF installation with actual-after evidence and unused undo preservation; converter/header/rollout review and real authorized mutation; target-only -1000 conversion; Release distribution and device PDF/total confirmation. OFF installation alone does not fix the reported amount.
