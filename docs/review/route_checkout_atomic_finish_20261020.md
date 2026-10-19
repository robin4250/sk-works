# Atomic final visit and invoice chronology

**BLOCKED: origin ambiguity remains unresolved. Do not deploy this candidate.**


A final visit ends inside the clock-out BEFORE INSERT trigger. Its `recorded_at`
uses the database clock after the checkout's `confirmed_at` has been assigned.
The signed-checkout source reader previously rejected this valid final visit.

The review-only candidate replaces only
`private.route_signed_checkout_sources(uuid,date,date)` after checking its current
body MD5 is `657a3e0a3511f600e440e23026d8a73d`. It retains the existing signature,
security mode, owner, grants and source/scope/signature checks. No source row,
attendance quantity, approval, saved invoice or feature gate is changed.

For a capture persisted after checkout, eligibility requires the exact checkout
ID as the end capture ID, equal attempted timestamps, and an attempted timestamp
between visit arrival and checkout confirmation. This is recognition of an
existing atomic event, without a time allowance for unrelated captures.

## Verification

The existing complete signed-checkout/invoice SQL verifier applies the candidate
in its disposable fixture and covers a 31.379 millisecond persistence delay,
mismatched attempt rejection, unrelated ID rejection, actual one-per-customer
invoice totals, unchanged source quantities and approvals, denied actors,
unsigned/missing source guards, and finalized invoice preservation.
The original full function definition is restored exactly in the fixture, including
OID, owner, ACL, configuration, security mode and volatility; the old defect is
reproduced after restore and repaired after reapplication. PGlite 0.3.14 passes locally. The existing CI runs the same verifier against
PostgreSQL 17, including concurrent refresh/finalization protection.

## Deployment boundaries

This file is a review candidate, not an applied migration. Production reads found
an editable automatic October invoice. Its saved source-pending flag is false,
although the current source helper rejects the atomic final capture. A successful
reader repair alone does not recalculate that saved draft. Registered financial
rates, all remaining source issues, actor authorization and the exact saved draft
must be reviewed before using the existing refresh RPC.

The separate day with punches but no confirmed attendance quantity remains
unresolved. This change must never fabricate a workday or connect an unrelated
report. Current original function metadata and full definition must be saved,
then exact owner/ACL/definition restoration rehearsed before production use.

## Unresolved counterexample and smallest safe direction

`tool/verify_route_atomic_identity_counterexample.mjs` loads the existing real
visit/capture/clockout functions in a disposable fixture. An authorized worker
first saves a visit-end command with a UUID chosen for a future checkout, sets
its attempt to the arrival's server-recorded time, then inserts that checkout
with the same UUID and claimed attempt/confirmation time. No final visit remains
open when the checkout trigger runs, so it did not create this end capture.
Nevertheless, the proposed identity/attempt predicate accepts the pair. The
reproducer explicitly prints UNRESOLVED; its success means the counterexample
was reproduced, not that the candidate is safe. The fixture uses its existing
simplified authorization schema, while live read-only inspection separately
confirmed authenticated INSERT on attendance verifications, no trigger assigning
server confirmation time, and no direct capture/event table writes.

Capture/event authenticated INSERT/UPDATE/DELETE are denied in production,
post-checkout new saves are rejected under the common shift lock, and raw capture
updates other than report linking are forbidden. Those controls prevent late
insertion but do not prove trigger origin for preseeded IDs.

A safe future implementation should record final-checkout origin in a private,
append-only server-only ledger from inside the existing final-visit trigger. The
ledger must bind checkout, shift, capture, worker, company and immutable attempt
values in the same transaction, with no authenticated insert RPC/grant. The reader
can then recognize only a ledger-backed exact pair. Distinct-ID capture writes,
rollback, retry, source-lock races and direct ledger-write denial need tests.
Historical events must not be automatically backfilled from matching IDs/times;
they require separately reviewed evidence. This broader write-path change is not
included here and requires coordination with the production owner.
