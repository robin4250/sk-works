# Archived processor: offline orchestration verification

Verified on 2026-10-08 against the archived, unchanged
`account-deletion-worker/account-deletion/processor.mjs` using Node's built-in
`node:test`. No production deployment, database operation, endpoint request,
mail delivery, account deletion, or release flag change is performed.

```sh
node --test docs/recovery/account_deletion_source_20261008/verification/processor_tests.mjs
```

Result: **124 tests passed, 0 failed, 0 skipped**. The final audit confirmed
**0 network attempts**. `globalThis.fetch` is replaced by a rejecting function
before importing the processor. Only the pure processor module is imported;
`index.ts` and persistent adapters are never executed. Every job, target UUID,
policy version, plan digest, and adapter result is synthetic and held in memory.

Covered behavior:

- Job identifier validation and required ports stop processing before claim.
  An unavailable claim returns busy; a claim rejection propagates before any
  lifecycle operation.
- Invalid plan identity, policy, digest, and completed-step prefix fail before
  eligibility or destructive adapters. Missing, reordered, duplicated, skipped,
  unknown, and overlong completed-step prefixes are exercised.
- Eligibility is required to return exactly `true` on every attempt, including
  retries with a persisted prefix and an already fully completed prefix.
- The eight adapters execute in the reviewed order, each preceded by renewal
  and followed by checkpoint persistence. Every adapter receives the claimed
  job and a stable job-ID/step idempotency key.
- Each adapter's false, undefined, truthy nonboolean, and rejected result stops
  subsequent adapters and records only the current failing step.
- Renewal and checkpoint loss at every step returns `lease_lost`; rejection
  records the current failure and stops subsequent effects. No success result
  is returned after lease loss.
- Every completed prefix length skips its already recorded adapters. When an
  adapter succeeded but its checkpoint was lost, retry uses the same key for
  that adapter while skipping the persisted prefix.
- Unconfirmed completion is never reported as completed. Rejected completion
  reports failure. An asynchronously rejected failure-recording port is
  suppressed without exposing the underlying exception contents.

These tests verify the coordinator's behavior with in-memory ports. They do
**not** establish live JWT validation, database RLS, lease ownership or expiry,
atomic checkpoint persistence, reviewed-plan digest computation, adapter
idempotency under concurrency, record retention, provider credential revocation,
Storage erasure, Auth removal, verification receipts, or delivered completion
messages. The processor checks the digest format; these tests do not claim it
recomputes or independently validates the plan's contents.

Failure-recording suppression is tested for the asynchronous port contract
used here; synchronous exceptions or non-Promise returns from that port are not
claimed to be suppressed. Arrays used in persisted job fixtures are dense
arrays, as returned by JSON; this is not validation of arbitrary JavaScript
object prototypes or sparse arrays.

The production intake and lifecycle release guards remain disabled. Passing
these offline tests does not authorize enabling the deletion feature or imply
that a real user account has been deleted successfully.
