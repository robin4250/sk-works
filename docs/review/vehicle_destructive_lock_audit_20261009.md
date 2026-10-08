# Vehicle rollout: destructive-operation lock audit

This is a separate draft investigation lane; it must not be merged into main while a lock blocker remains. It does not change production SQL, enable a rollout, or add intentionally failing cases to the previously passing Attendance PostgreSQL Races workflow.

The historical run below used the exact previously passing race head `fef8f4caf471887d948c2740e65623c8a70834cb`. The rerun now validates this branch's committed `SHA256SUMS` and uses verbatim SQL from reviewed source commit `fb572a1` in `sk-works-company-lock`: claim, group checkout and meter migrations. This avoids accidentally retesting the known-broken historical snapshots. The scripts still load the existing main `force_manage_attendance` definition. Only a disposable loopback database named `sko_race_fixture` is allowed. Each invocation destroys and rebuilds its fixture schemas; do not run invocations concurrently in the same database. No production migrations or flags are changed.

## Suspected company cascade cycle

Vehicle starts and meter registration take the company advisory lock before inserting a claim/event whose company foreign key takes a parent `companies` key-share lock. Company DELETE takes the parent row lock before its cascading rollout deletion invokes the advisory-lock guard. Those orders are reversed.

`company-start` and `company-meter` retain the same parent row FOR UPDATE lock acquired by DELETE, then launch a real second-connection vehicle write. The observer must see an actual PostgreSQL Lock wait. The parent-owning transaction then executes the real DELETE and its unchanged FK cascades/trigger. Both outcomes are collected. Any `40P01` or `55P03` fails the test; neither is considered a passing reproduction. The parent lock is a deliberate barrier representing DELETE's first lock, not a substitute implementation or fixture trigger.

Actual PostgreSQL 16.15 run `37815352048`, head `bff8b4387a906db27669c4003541bd7de407eae9`, reproduced this blocker in both company scenarios with SQLSTATE `40P01`. No company deletion was attempted on production.

## Existing authorized attendance corrections

`admin-meter` uses the existing authenticated admin RPC and exact original permission checks. A claim row lock representing its deletion cascade holds the meter contender until the actual correction deletes the linked source. The waiting meter must explicitly reject its now-missing claim, leave no event and keep the old vehicle baseline. In the reverse ordering, a fully committed event must survive the correction byte-for-byte and the vehicle baseline must stay at its committed value. This distinguishes an immutable retained event from a successful active-claim replay after the source has been replaced.

The helper permission/schema definitions are synthetic fixtures; this does not prove all production RLS or company-retention policies. UI approved correction flows and full account deletion remain separate work.

## Running

With the existing PostgreSQL race runtime and loopback fixture URL configured, run each scenario independently:

```
sha256sum --check tool/fixtures/attendance_race/SHA256SUMS
node tool/audit_vehicle_destructive_lock_interleavings.mjs /path/to/pg/lib/index.js company-start
node tool/audit_vehicle_destructive_lock_interleavings.mjs /path/to/pg/lib/index.js company-meter
node tool/audit_vehicle_destructive_lock_interleavings.mjs /path/to/pg/lib/index.js admin-meter
```

Local Node syntax and diff checks pass. The sandbox cannot start a nonroot PostgreSQL service. No actual two-connection results are claimed; the dedicated workflow runs each scenario in a separate disposable PostgreSQL service with fail-fast disabled, so a company deadlock does not suppress the independent admin case. Root authorized saving this draft for investigation. A failing case must remain failing until a reviewed implementation resolves the underlying lock order.

## Actual PostgreSQL results

Run `37815352048` checked exact fixture provenance and used PostgreSQL 16.15.

| Scenario | Job | Result | Evidence |
| --- | --- | --- | --- |
| company-start | `113442460789` | Failure, blocker confirmed | Actual `transactionid` Lock wait; start rejected `40P01`; DELETE completed. Server log identifies claim company FK KEY SHARE versus rollout advisory lock. |
| company-meter | `113442460246` | Failure, blocker confirmed | Actual `transactionid` Lock wait; meter rejected `40P01`; DELETE completed. Server log identifies event company FK KEY SHARE versus rollout advisory lock. |
| admin-meter | `113442460680` | Success | Existing authenticated admin correction wins: pending meter explicitly rejects with no event/baseline change. Meter first: committed immutable event and 1050km vehicle baseline survive correction. |

The workflow failure is intentionally retained as truthful evidence of the unresolved implementation problem. No expected result, permission check, SQL definition or destructive fixture guard was weakened. The older independent race checks remain separate evidence. Company-parent locking must be resolved and this same strict investigation rerun before treating the staged vehicle feature as safe to enable. These tests do not authorize or perform production company deletion.

## Parent-lock correction rerun

The reviewed correction takes `companies FOR KEY SHARE` before the company advisory lock. The same strict destructive scenarios remain, and now additionally require DELETE to commit, the contender to explicitly reject the deleted company with SQLSTATE `P0001`, and no surviving company/claim/event row. Historical `40P01` evidence is retained above. Manifest and local Node/diff checks pass; actual PostgreSQL rerun results are pending and must not be represented as successful before CI finishes.
