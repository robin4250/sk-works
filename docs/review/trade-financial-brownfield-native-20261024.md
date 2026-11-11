# Trade confirmation: financial-trigger boundary fixture

This is a new disposable Native PostgreSQL 17 proof candidate, not a production
installer, central gate or recovered historical proof. It uses the existing
trade fixture as its declared synthetic authorization/seal surroundings, then
adds the financial trigger boundary observed in the production catalog.
No private catalog JSON, system OIDs, identity, financial row or image bytes are
committed. The manifest contains public-source Git blobs and routine body MD5s.

## Source contract

The harness verifies 17 repository source Git blobs before starting the existing
trade fixture. Twenty-one critical existing routine bodies are matched to their
observed source MD5s after setup and again after all cases. Expense finalization
is produced from the original public migration plus the exact reviewed public
v2 patch, rather than rewriting its financial logic in the test.

One pure blocked-status guard's historical Git origin was not found. Its small
observed definition is included in a clearly named fixture-only SQL file after
the integration owner reviewed it for identifiers/secrets. Its exact observed
body MD5 is still required. It is neither a guessed implementation nor a claim
to recover an earlier artifact. No migration or existing financial function
file is edited by this change.

The surname approval wrapper is a separate historical prerequisite source. It
is absent in the actual catalog, while the existing fixture supplies its exact
adapter-pinned source. All four surname tables and the corresponding APIs still
need a bounded prerequisite installation; this proof does not mark them present
in production.

## Planned assertions

1. Preserve a synthetic already-finalized payment certificate of net -1000 and
   its existing positive original-cost consumption through invoice approval.
2. An invoice's separately allocated customer expense remains +1000; approval
   through the actual public confirmation API records the original cost once.
   An identical retry preserves the complete financial/consent state.
3. A later consent-receipt failure rolls back invoice approval, audit and cost
   consumption together. No parallel fake financial writer is used.
4. Actual approval only sets `approval_finalized_at`. The cost trigger sees it,
   but the immutable expense-detail snapshot begins only at actual status or
   `finalized_at` finalization. An explicit fixture status-finalization
   transaction tests snapshot creation and rollback without changing product
   approval behavior.
5. The actual blocked-status guard and a live unverified-route guard refuse
   their respective transitions atomically. The legacy blocked-status guard is
   not falsely described as checking the approval timestamp.
6. Existing invoice/payment rows, old consumption, prior approved consent
   history and all pinned routine bodies remain unchanged.

Route fixture tables are synthetic shapes, and the exercised route case is an
unverified visit with no signed report. This is not a new proof of every valid
route/rate calculation path. Notification insertion is the existing local table
operation; no external producer, push, email, SMS or invitation is connected.

## Limits and status

Node syntax checks passed locally. The first Native run reached the unchanged
child fixture, then failed in synthetic schema setup because this harness
redeclared the three payment columns already supplied by the monthly-review
child. The harness now adds only the missing timestamp; the child and its
source pins remain unchanged. A fresh Native run is required before claiming
the assertions above passed. The existing real-GoTrue proof remains separate;
this harness uses explicitly synthetic claims/session predicates and does not
claim real provider or production RLS/delegation behavior.

The reciprocal API still lacks its reviewed central default-OFF connection and
the actual surname prerequisites. The separate gate design is
`trade-central-gate-design-20261024/docs/review/trade-reciprocal-central-off-prerequisites-20261024.md`.
Source/Native proof does not authorize enabling it or changing live financial
documents. This task makes no production connection or change.
