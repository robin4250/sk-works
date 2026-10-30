# Explicit order refusal — review only, default OFF

A new received package cannot use the legacy `respond_site_share(false)` path:
that path lacks the immutable original, approval and reply consistency contract.
The legacy guard remains unchanged. Recipient management instead explicitly
confirms `注文を辞退` in a separate dialog. The fixed HTTP command requires
`confirmed: true`, current verified actor/SID/exact company management membership
and master ON; it creates an immutable refusal and exact request operation,
changes only that pending recipient inbox and dispatches deduplicated management
notifications to the original sender in one transaction. No site, acceptance,
seal, signed original, order PDF, financial note or price is created/rewritten.

The refusal shares the **same saved-package advisory lock** as the existing
approval function. An approved package cannot be refused and a refused pending
inbox cannot be approved. A notification failure rolls back refusal, request
operation and inbox state together. Existing originals remain readable with
master OFF. A terminal refusal retires the exact original approval prompt and
sends a `site_order_package` result notification without price/notes/PDF URL.
Device push is not claimed.

The existing identifier-only journal/storage engine is reused with a distinct
refusal namespace and no fabricated preview ID. Failure before durable storage
sends no network mutation. An uncertain refusal survives close/reopen and blocks
both new approval and refusal until explicit fixed `reconcile_refusal` confirms
the same accepted request or permanently cancels an unaccepted one. A fresh live
SID can reconcile its same actor's result; it does not inherit prior write/consent
authority. Neither a negative detail read nor an HTTP error clears quarantine.

Tests cover foreign/sender refusal denial, explicit confirmation, immutable
records, notification-stage rollback, exact replay/no duplicate notices,
approval/refusal mutual exclusion, late cancelled requests, OFF status/original
reads, real SDK ES256 HTTP command composition, persistent refusal quarantine
and the confirmation UI. Native PostgreSQL observes approval holding the common
lock while refusal waits and then rejects after approval COMMIT.

New-session reply-job recovery, durable uncertainty in the later reply worker,
outgoing creation/registered supplier flow, management/site/company entrances,
combined hosted deployment and actual iPhone checks are still unfinished.
This is not a production migration or authorization to deploy/enable anything.
