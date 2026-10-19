# Atomic final visit and invoice chronology

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
