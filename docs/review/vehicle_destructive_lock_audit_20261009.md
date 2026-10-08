# Vehicle rollout: destructive-operation lock audit

This is a separate draft investigation lane; it must not be merged into main while a lock blocker remains. It does not change production SQL, enable a rollout, or add intentionally failing cases to the previously passing Attendance PostgreSQL Races workflow.

CI checks out the exact previously passing race head `fef8f4caf471887d948c2740e65623c8a70834cb`, validates its Git SHA, copies only its fixture files into the ephemeral workspace, and validates their committed `SHA256SUMS`. The draft contains only this document, the standalone audit script and its dedicated workflow; no unmerged SQL or other race changes are mixed into main. The new script loads those unchanged migrations and the existing main `force_manage_attendance` definition. Only a disposable loopback database named `sko_race_fixture` is allowed. Each invocation destroys and rebuilds its fixture schemas; do not run invocations concurrently in the same database.

## Suspected company cascade cycle

Vehicle starts and meter registration take the company advisory lock before inserting a claim/event whose company foreign key takes a parent `companies` key-share lock. Company DELETE takes the parent row lock before its cascading rollout deletion invokes the advisory-lock guard. Those orders are reversed.

`company-start` and `company-meter` retain the same parent row FOR UPDATE lock acquired by DELETE, then launch a real second-connection vehicle write. The observer must see an actual PostgreSQL Lock wait. The parent-owning transaction then executes the real DELETE and its unchanged FK cascades/trigger. Both outcomes are collected. Any `40P01` or `55P03` fails the test; neither is considered a passing reproduction. The parent lock is a deliberate barrier representing DELETE's first lock, not a substitute implementation or fixture trigger.

This remains a suspected blocker until the actual PostgreSQL run supplies SQLSTATE evidence. No company deletion was attempted on production.

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
