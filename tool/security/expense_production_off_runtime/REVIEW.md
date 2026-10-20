# Expense default-OFF one-shot orchestration: REVIEW CANDIDATE ONLY

No production transport is included. The command-line entry point always refuses with exit 2 before connection, authentication, marker creation or SQL execution. No password, endpoint, CLI login, PostgREST client or production adapter is read or accepted. The Python functions are a harness for the synthetic transport supplied by tests, **not an approved production operator command**.

## Reuse boundary

Four files are byte-identical to `support/expense-prepare-driver-20261020` at `fa87c9390f6ec08797c74538f9e3fae4d10389e0`, also identical to the successful native rehearsal at `af5ba7bb70cf120047c344f880ef8e3dc25f3686`:

- `expense_default_off_plan.mjs`: 5c4c7acedd93fd2fd162179eb4317c0e170877007346e1a0b404e92c1d51b5b9
- `source/expense_direction_code_checkpoint.mjs`: 9a642ea96fc3d564f6c711c2547da5954310f5fdf7f1448abdef2a0dcfa6197f
- `source/expense_direction_default_off_preparation.mjs`: 5e1401c0271be411ae6d1de9ac8f20432380cd4ebd6db2cc0ccffd46e83fdda8
- `source/expense_payment_direction_v2_20261019.sql.review-only`: 770728fa45176d7bbeb77ebd0610f936659624e4b1287d63bd83e0dd9264fe5a

`offline_generator.mjs` checks those hashes before importing them. It calls the original `buildExpensePlan()` and requires byte equality with the existing private prepared install and actual-after SQL. It does not reconstruct the expense guard or import common-allowance/insurance validators. The original before/SQL/prepare-status files remain unchanged; evidence copies are private. No clone-local SQL, GRANT CREATE fixture adaptation or clone OID mapping is ever used for this candidate.

## One-shot state contract

`review_runner.py` validates the successful private prepare status, source-checkpoint SHA256, generated artifact hashes/lengths and byte-identical regenerated SQL before any attempt. Private roots/directories require ownership and 0700-style permissions; files require ownership and 0600-style permissions. Symlinks, nonregular files, oversized inputs and changes are rejected.

Within an exclusive nonblocking file lock, the single fixed `expense-default-off-install-attempt.json` is created with O_EXCL and fsynced **before** transport submission. A marker in any phase refuses every subsequent install attempt, including a different plan directory. Marker updates use private temporary files, fsync, atomic replace and directory fsync. The runner never deletes or rearms a marker. A crash just after marker creation is conservatively unknown even if SQL was not sent.

The transport may receive exactly one immutable original BEGIN/COMMIT SQL submission. Acknowledged return and exception/timeout/disconnect are kept separate. The runner never retries. It then requests the original READ ONLY actual-after query via a separate transport method. A future adapter must guarantee a fresh dedicated session and `search_path=public` on both execution and observation sessions; this candidate does not provide or prove that adapter.

Read-only observation uses a new private evidence directory. `read_only=on`, complete actual catalog, financial hash, no-v2/no-conversion/no-rollout fields are checked by the original plan module. Exact before state is reported as `before_state_observed`, never as permission to retry. Recognized default-OFF state passes the original `prepareUnusedUndo()` and generates a private `private-production-unused-undo.sql.review-only`, containing **actual observed** metadata/OIDs and exact guards. Undo is never executed by the runner. Unknown/used/drifted states and read failures remain `state_requires_review` with retry false. Raw evidence is private; exception text, SQL and credentials are not printed or copied to public status.

`recover_review_readonly()` cannot call the install method. It preserves the marker, checks attempt artifact hashes, and records a new READ ONLY observation. A definitive before-state observation still does not rearm installation automatically.

## Validation and limits

PGlite 0.3.14 applies the **original** expense plan to a generated v1 fixture, captures actual-after inside its READ ONLY transaction, prepares the original unused undo using actual OIDs, executes that undo in the isolated fixture, and compares original catalog and financial rows. This reuses existing SQL; it is not another deployment implementation.

Thirteen Python tests cover successful acknowledgment, COMMIT disconnect with installed state, disconnect with before state, observation failure and readonly recovery, process exit after durable marker, single-submission/retry refusal, hash tamper, forged hash with changed SQL, symlink/public-file refusal, used-v2 and six drifted-actual cases, concurrent attempts, changed recovery artifacts, actual-OID embedded guard and CLI refusal. Initial test had a fixture assertion assuming numeric OIDs; PostgreSQL JSON represents them as strings. The check now compares the embedded expected-after JSON to the whole actual catalog, without changing product code or guards.

No real connection, TLS endpoint, session role, real PostgreSQL disconnect/COMMIT behavior, native filesystem crash/power-loss behavior, production installation or real data recovery is proven by these tests. No financial amount conversion, gate ON, source negotiation deployment, app distribution or iPhone verification occurs.

## Deliberately unfinished before production

1. A separately reviewed dedicated PostgreSQL transport: fixed project endpoint, TLS verification, exact execution/session role, session-local `search_path=public`, safe nonlogging credential acquisition, clean environment, caller-side timeout, one install submission and fresh-session READ ONLY observation. No generic shell command or arbitrary URL injection.
2. Explicit approval of the exact private checkpoint/prepared artifact hashes and current guards. The fixed target row/hash in the earlier fresh helper must still match; never loosen it to proceed.
3. Isolated **native** tests of the new adapter/state machine: real disconnect around COMMIT, timeout, process termination, concurrent operator, before/after/unknown recovery and marker retention. Earlier SQL clone rehearsal is reused and is not proof of this new adapter.
4. Current private backup/restoration evidence, durable owner filesystem, and a reviewed operator workflow for resolving a permanent marker. No automatic retry/rearm or automatic undo.
5. A private production actual-after capture and unused undo creation only after those conditions are satisfied. OFF install is still separate from negotiation, rollout gates and exact v1 draft conversion.

Until these conditions are satisfied this candidate stays non-executable. It must not be merged into the main feature PR or presented as a production-ready fix.

## Commands (isolated only)

Run from repository root:

```bash
SKO_EXPENSE_PGLITE_MODULE=/absolute/path/to/@electric-sql/pglite/dist/index.js python -m unittest discover -s tool/security/expense_production_off_runtime -p 'test_review_runner.py' -v
python -m py_compile tool/security/expense_production_off_runtime/review_runner.py tool/security/expense_production_off_runtime/test_review_runner.py
node --check tool/security/expense_production_off_runtime/offline_generator.mjs
node --check tool/security/expense_production_off_runtime/create_test_evidence.mjs
```

## Native disconnect CI candidate (not locally executed)

No existing local postgres/psql/initdb/docker/podman was found, so native success is **not** claimed. The existing Expense default OFF preparation workflow gains a separate job with its own empty PostgreSQL17 service. It reuses the unchanged `payroll_scope_native_pg17_runtime.mjs`, fixed loopback URL guard and pinned pg dependency. It does not reuse a populated fixture left by another job.

`native_fixture_transport.mjs` accepts only the fixed localhost disposable fixture URL/user/password/database/port validated by the existing guard **before** importing pg or connecting. It is not a production adapter. The Python native tests strip inherited PG/credentials configuration and provide only that fixed synthetic URL.

Fault cases are deliberately before/after boundaries: (1) hold the final COMMIT after the original transaction body and terminate the real backend from a second fixture connection, proving rollback; (2) complete the real COMMIT then destroy the socket and withhold acknowledgment from the Python runner, proving installed state despite caller failure; (3) acknowledged COMMIT. The runner itself always supplies the unchanged original prepared SQL exactly once. Only the isolated fault-injection adapter withholds the final command in case 1. This is not a claim of a packet drop at a precise instruction inside server COMMIT.

All three cases request actual-after through fresh native sessions with default_transaction_read_only=on plus the original READ ONLY query, assert state classification and permanent marker/retry refusal, and use read-only recovery again after unknown outcomes. Installed cases restore only the actual generated unused undo within the disposable fixture, then compare exact catalog and financial hash. No observation result is mocked in the native test. These tests are a pending CI candidate until the native job has actually passed; syntax/endpoint refusal alone are not native proof. Production CLI remains exit2 and production adapter/approval conditions remain unfinished.

Native-only command, on the dedicated empty CI fixture:

```bash
SKO_PAYROLL_SCOPE_FIXTURE_URL=postgresql://postgres:fixture-only-password@127.0.0.1:5432/sko_payroll_scope_fixture python3 -m unittest discover -s tool/security/expense_production_off_runtime -p 'test_native_recovery.py' -v
```
