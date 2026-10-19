# Future final-checkout origin receipts (review only)

This is a separate replacement for the unsafe ID/attempt-only candidate in PR1275.
It does not authorize that candidate or backfill historical events.

## Write contract

The existing final-visit BEFORE INSERT trigger writes an immutable private receipt
only immediately after it has itself saved the final visit. A client that saved
an end beforehand leaves no open visit, so the trigger creates no receipt.
The receipt binds company, worker, route, stop, date, shift, arrival/end capture,
checkout, attempt/confirmation time and the server-recorded capture time.
It shares the existing shift lock and transaction; a later checkout failure rolls
all rows back. It has RLS, no anon/authenticated table grants or public insert RPC,
and a trigger rejecting UPDATE/DELETE even for a privileged ordinary statement.
There are no cascading foreign keys: management deletion must retain audit receipts.

The reader requires this exact receipt in addition to the existing ID, attempt,
scope, signature, quantity, site and chronology guards before recognizing the
server's final capture persisted after checkout confirmation.

## Validation and limits

The verifier loads the existing real capture/visit/final-checkout functions in a
simplified disposable authorization fixture, then applies the candidate. It checks
the preseeded-ID attack is rejected, genuine origin is accepted, client writes and
receipt mutations are denied, duplicate checkout is rejected, and a later insert
failure rolls the capture/event/receipt back before a successful retry.
PGlite 0.3.14 passes locally; the dedicated workflow uses PostgreSQL 17.
These are future-origin tests, not a complete production permission or finance audit.

## Production prerequisites

Candidate guards pin the unchanged source-reader and checkout-trigger body hashes.
Owner/ACL/config of the replaced functions must be protected and independently
compared before deployment. A production backup must include definitions, ACL,
triggers, policies and all scoped data. Do not restore an old reader/write guard
and drop or lose new receipts once future records exist. Preserve/export them
and re-evaluate compatibility and source states first.

Existing historical delayed captures stay blocked without a reviewed receipt.
Do not infer or mass-backfill receipt origin from IDs, times, shifts or this
candidate. No production deployment, attendance quantity, invoice recalculation,
feature gate, Auth change or existing signature modification is performed here.
