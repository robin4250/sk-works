# Draft: first-install stop-ready birthday protocol

Review-only source. No production, feature enablement, Auth, main or device changes. Frozen predecessor1688 /5bc2d502d85b62aff689e3d5480846ea9696bfc7 is preserved. This is **not a safe direct stop or upgrade for deployed5bc**: its already-running writers do not participate in the new admission barrier.

## Separate phases

1. `quiesce-before-first-dob.sql.review-only` exactly guards the original pre-birthday five functions, caller/dependency graph and absent birthday column. It closes EXECUTE on public save/decide and private apply in a committed transaction. **This temporarily stops all personnel writes, including nonDOB**, while retaining readers/data. It requires a separate explicit maintenance approval; none exists.
2. `install-first-stop-ready.sql.review-only` requires those closed ACLs/original definitions, no other client-backend transaction and no prepared transaction. It does not cancel or terminate anything. On refusal it leaves the separately committed maintenance closure in place. After verified drain it installs five stop-ready functions and a nullable date column without backfill, then restores exact public authenticated/service_role entry grants; private apply remains owner-only. Installing this phase publishes writable version2 and is a functional enablement requiring its own explicit approval.
3. `stop-after-ready.sql.review-only` requires the exact stop-ready catalog. It acquires exclusive admission and drains existing shared holders. Only the two readers change to readonly version1; all three writer bodies/ACLs remain byte-identical. Ready writers acquire global shared admission before worker/request locks and recheck current writable version after waiting. Therefore cached no-op/proposal/approval calls must reject DOB after stop, while valid nonDOB work and explicit reject remain usable. The content digest stays the same for unchanged content: capability and content are separate.
4. `reopen-before-dob.sql.review-only` is an optional separately approved **zero-DOB-use effective-rights restoration** if first installation is abandoned. It requires the original five bodies and absent date column. It neither drops/recreates functions nor updates system catalogs. Restoring the original implicit PUBLIC execute yields an explicit default ACL array instead of physical NULL; normalized grantor/grantee/privilege/grant-option rights must match exactly. Old NULL guards are not weakened: a future retry needs fresh catalog evidence and approval. This path refuses after READY or any use; it never deletes the date column, data, proposals or history.

STOP does not erase or auto-reject pending DOB originals. Both supersession paths retain pending proposals with any `birth_date`, `_birth_date_cas` or `_birth_date_mode` marker while readonly; ordinary version2 reject-all behavior remains unchanged. The conditional exists in Ready before STOP so queued cached nonDOB calls also preserve DOB pending. Explicit rejection is a separate permitted user action. No automatic resume/retry or old unknown-job revival is implemented.

## Verification scope

The harness reuses only the hash-pinned synthetic personnel bootstrap, not the older suites. Each scenario gets a fresh disposable database:

```sh
node tool/security/personnel_birthday_stop_ready/verify.mjs <guarded-adapter-or-PGlite-module> stop
node tool/security/personnel_birthday_stop_ready/verify.mjs <guarded-adapter-or-PGlite-module> zero-use-reopen
```

Local PGlite scenarios pass; they are not concurrency evidence. Dedicated Native17.6 CI is pending. Native schedules prepare an original named plan before committed closure, reject its later execution, refuse undrained/prepared transactions, prewarm four Ready named plans, observe exclusive/shared advisory waits, then require old cached DOB calls to reject and cached nonDOB to preserve complete DOB request/proposed/quorum/approval snapshots. STOP data invariance, readonly values/digest, two-approval pending denial, nonDOB self supersession/approval, explicit rejection, and owner-only direct DOB apply (date/null) are asserted. Recovery compares effective ACL and original state while recording the physical ACL difference. Runner, PostgreSQL process and data owner must be nonroot; no local root-initdb workaround is used.

These are evidence groups, not an invented independent-test count. No Native, whole-CI, production or device success is claimed before actual results are read.

## Remaining boundaries

All metadata/source/hash/caller guards must be rechecked against a future approved target. Static names and stored dependencies cannot exhaust dynamically constructed SQL. Trusted owner/service direct DML is outside client-RPC admission and must be held during maintenance. Bank rows are a synthetic preservation projection, not banking authorization/trigger/Storage proof. Real authentication and device confirmation remain separate. The original5bc source, current guide/document A/B approval scope, individual-document exemption setting and unrelated feature switches are not modified.
