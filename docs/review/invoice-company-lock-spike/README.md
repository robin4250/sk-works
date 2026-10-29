# Invoice company-lock isolation spike

Review-only synthetic PostgreSQL experiment. This is not an implementation for the app; no public grant, production SQL, trigger, data, scheduling, or real notifications.

The prototype uses a transaction advisory lock scoped to a company. Both the proposed approver and cooperative writer acquire it before accessing business rows, and the approver rereads after obtaining the lock at READ COMMITTED. A disposable PG17 fixture verifies another company can write, a same-company cooperating write waits, an earlier writer's insertion is visible after locking, and a non-cooperating direct write bypasses the lock.

## Blockers before integration

- Inventory every writer and indirect source of invoice calculations, including INSERT, UPDATE and DELETE, existing RPCs, triggers, administrative paths, direct API, server tasks, route, attendance, rates, expenses, seals, plus joins without direct company ID. Verify actual catalog, trigger order, role grants, and transaction boundaries.
- All relevant writers must participate before they lock/mutate any source row, including old and new company on reassignment; missing even one path breaks the invariant. BEFORE ROW triggers may obtain row locks too late and create lock-order deadlocks. Multi-company operations need a consistent deterministic ordering.
- Confirm the complete readiness/finance check and final approval happen in the same transaction and after lock acquisition with a fresh READ COMMITTED statement snapshot. Fail closed on unknown scope and lock errors; no silent retry after uncertain commit.
- Prove the invariant by real concurrent tests for phantom inserts, deletes, updates, move across companies, rollback, long transactions, pooled connections, legacy/direct REST paths, customer scope, rates, route, seal and membership changes. Include the unmodified direct-write bypass as a negative control.
- Evaluate hash collisions as potential unintended blocking (never identity or authorization). Company ID must be obtained from server-trusted data and validated. Measure latency, deadlocks and starvation using realistic volume. Row locks and cross-table operations need separate review.
- Confirm deployment/rollback preserve old app operation and existing data; validate RLS/ACL and real GoTrue, run full integrated candidate and on-device tests before any enablement.

Serializable mode alone is not a replacement without proving the isolation level and participation of every relevant transaction and correct retry semantics. The current production-style global table lock remains untouched; this experiment must not be used to unlock or deploy #1508.


## Fail-fast row-trigger experiment

The isolated fixture also tries a nonblocking advisory lock from a row trigger. A conflicting synthetic update raises SQLSTATE 55P03 instead of waiting while holding a tuple lock; another company and the approver can proceed. This is an experiment, not a production fix: existing clients may display an error, whole statements roll back, current writers, deletes/inserts, changed company IDs, cascades, all source tables and deterministic multi-company scope remain unproven. A retry must start a fresh transaction and may only occur when rollback is confirmed; never retry an unknown commit. The test does not prove absence of other deadlocks or starvation. CI outcome is separate.


## Final row scope after existing triggers

The review fixture now reproduces a later alphabetically ordered BEFORE trigger changing an inserted/updated company after the first guard has accepted a different company. A test-only AFTER ROW recheck rejects the final busy company and rolls back the complete statement. This is not a generic production installer: actual trigger order, nested writes, RLS/ACL, partitions, TRUNCATE, deferred constraints and all real writers still require coverage before replacing global locks. No production data or permissions change.


TRUNCATE coverage: the isolated fixture now demonstrates that row guards do not intercept TRUNCATE. A test-only BEFORE TRUNCATE statement guard refuses the unscoped operation (55000), preserves all rows on rollback, and allows ordinary writes afterward. This is not production table/ACL coverage: actual deployed TRUNCATE grants, owner/service jobs, cascade targets, partitions, trigger disable privileges and maintenance quiescence remain unverified. No GUC/client-provided bypass is added. Reference: https://www.postgresql.org/docs/17/sql-truncate.html
