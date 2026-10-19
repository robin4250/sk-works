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
The preguard also pins each replaced function owner to postgres, its exact
owner-only ACL, empty search_path config, SECURITY DEFINER and original
volatility (stable reader / volatile checkout). It requires postgres as installer.
Drift in any of these properties aborts before mutation; the verifier exercises
volatility and pre-existing service-role grant drift. This guard covers those two
function bodies and metadata, not every dependency, trigger or schema object.
The observed old ACLs were already owner-only, so explicit service-role revocation
is a no-op for those observed functions; a changed old ACL fails rather than
being silently normalized. Other production dependencies still require review. A production backup must include definitions, ACL,
triggers, policies and all scoped data. Do not restore an old reader/write guard
and drop or lose new receipts once future records exist. Preserve/export them
and re-evaluate compatibility and source states first.

Existing historical delayed captures stay blocked without a reviewed receipt.
Do not infer or mass-backfill receipt origin from IDs, times, shifts or this
candidate. No production deployment, attendance quantity, invoice recalculation,
feature gate, Auth change or existing signature modification is performed here.

## Creation-default and service-role protection

The candidate explicitly revokes table/function privileges from `service_role` as
well as PUBLIC, anon and authenticated. A final ACL guard rejects every non-owner
grantee on the ledger, new append-only trigger function, reader and checkout
trigger function; unknown creation-default grants abort the entire transaction.
The verifier seeds table/function default grants for service_role and separately
for an unexpected role. Unknown table and unknown function grants each cause a
clean rollback. With only known service defaults seeded, installation succeeds,
service_role retains BYPASSRLS but has no INSERT privilege, and a direct VALUES
INSERT is denied at the table privilege boundary. PostgreSQL 17 runs this test.

Unknown function-default grants are tested against the newly created append-only
function. CREATE OR REPLACE of the two existing functions preserves their old
ACLs and does not acquire new function defaults.
