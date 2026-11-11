# Expense stage 2 offline plan — review candidate

No database client, credentials, endpoint, rollout activation or financial DML is
provided. This package composes existing reviewed SQL without reimplementing its
conversion or negotiation. Original converter SHA256 is
`725ff2533539c63759c92c0bbc45d37c131fa431c421fd76deb127bdff2604d7`;
negotiation SHA256 is `f08628a18891c114c64f7551c33f1139879da3fb1439bac23c8eb54f1995507d`.
Only negotiation's one outer BEGIN/COMMIT pair is removed, after exact hash and
anchor checks. Both originals are retained byte-identically. The two reused
stage1 checkpoint/preparation modules are independently hash-pinned before import.

API: `captureSql`; `buildInstall(before,converterText,negotiationText)`;
`classify(before,after)` returning a state string; `buildUnusedUndo(before,after)`.
CLI modes `capture-sql`, `install`, `classify`, `undo` accept JSON on stdin (except
capture), emit JSON on stdout, and emit only a sanitized refusal on failure.
Install input uses `before`, `converterText`, `negotiationText`. Classify/undo use
`before`, `after`. SQL output is `{sql:...}`; classify additionally returns
`retry_allowed:false`. This module never executes its generated SQL.

Capture uses a fresh read-only repeatable-read transaction, PostgreSQL role,
empty credential input, bounded five-table financial digest, and full metadata
for nine existing functions. Dependency closure recursively follows explicitly
qualified private/public/auth function names in stored bodies and captures every
overload of those names. It includes converter's scope/account/components/math
roots. Dynamic/unqualified function resolution cannot be proven by source scanning;
the deployment operator must review that dependency limit rather than call it a
complete formal dependency analysis. Existing triggers/event triggers, complete
payment policies, schema ACL, role OIDs, all default ACL, normalized relation
metadata and audit metadata are captured. VACUUM statistics alone are excluded.

Install requires exact stage1 sources with the gate constant OFF, no stage2
objects or directional rows, and exact fresh catalog plus financial CAS. It locks
the five business tables NOWAIT, composes both sources in one transaction, and
checks the reviewed reader changes, old metadata/dependency closure and financial
invariance, exact restrictive policy, both gates OFF, new function/audit rights,
audit structure and zero conversions. Unexpected inherited ACL grants cause refusal;
the generator never silently edits default ACL or strips service-role rights.

Undo generation validates the actual observed state, embeds actual OIDs and full
metadata, and produces a separate transaction. At execution it locks business and
audit tables, checks exact actual catalog/financial digest, both gates OFF, no
v2/basis rows and audit empty, restores original reader definitions, drops only
stage2 objects without CASCADE, and requires exact before restoration. Historical
stage1 undo is neither changed nor used after stage2 installation. Any usage or
drift requires separate forward-recovery review.

Validation: isolated PGlite with the actual nine stage1 function definitions,
original migrations and a synthetic fixture passed install → fresh read-only
capture → classification → actual-OID undo → exact before catalog/financial digest.
Nine altered-after cases (financial, v2, audit use, rights, OID, column type, trigger,
policy and gate), two source-pin failures and live SQL undo-CAS refusal passed.
These tests do not prove native transaction disconnects, current production schema
closure, endpoint/session behavior, old-client exclusion or device operation.

Test command: `node verify_stage2.mjs ABS_REPO ABS_PGLITE_MODULE PRIVATE_ORIGINAL_CHECKPOINT PRIVATE_STAGE1_CHECKPOINT`. The test reads
private existing stage1 source-only checkpoints from explicit required argv paths;
it does not copy financial rows into this package. Native fixture/review remains
required before operator distribution. No gates are enabled or drafts converted.
