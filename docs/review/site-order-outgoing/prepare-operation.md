# Unsigned prepare operation barrier (review only)

This candidate extends frozen PR 1668 without changing its SQL or the existing
financial, consent, signature, job, revision or receipt functions. It is not a
production migration and is not installed by an application release.

The new `site_order_outgoing_private` namespace owns two append-only tables:
`prepared_operations` contains identifiers and digests; `prepare_retirements`
contains a permanent tombstone for the actor's request. The only new foreign key
is between these new tables. No body, PDF, seal bytes or access token is stored
in either table. Financial input remains RAM-only on a future client; canonical
document revisions remain the existing server-side source of truth.

`prepare_order` stages an unsigned revision through the unchanged canonical
prepare function and binds the local ID in the same transaction. It verifies
current source and seal digests and records a request receipt. Exact retries
reuse the receipt; changed IDs/body/source/session are rejected. Persisted
staging is not signing or consent. Canonical server-body preview and a fresh
explicit review must follow preparation.

`retire_prepare` is an explicitly confirmed stop for this unsigned prepare
request, not cancellation of an order. A permanent tombstone blocks late HTTP
preparation through this purpose. Retirement requires the same actor/company,
current live session and current management permission, including while the
feature is OFF. A new session may stop its actor's unsigned request but cannot
rewrite its recorded session, replay its preparation, or revive a signed job.
Already advanced consent/job state returns `advanced`, `retired=false` and
`order_cancelled=false`; it is never reported as a successful cancellation.

`operation_status` reports IDs and digests only. `not_observed` and a lost COMMIT
acknowledgement remain UNKNOWN: keep the durable ID-only journal and never
automatically resend, prepare again or clear it. Only an exact confirmed
tombstone supplies a definitive retired receipt. `require_unsigned_prepare`
is the transaction guard a future dedicated consent wrapper must call before
existing preview/decision functions. It does not itself sign, render or send.
Existing legacy financial-purpose rights are not globally cancelled or changed.

Pair identity locks precede operation, site-scope and canonical-document
advisory locks. The Native fixture observes four actual two-connection waits:
retire versus late prepare in both orders, and retire versus guarded consent
in both orders. The fixture also verifies immutable original rows/functions,
rollback after late insertion failure, new-session behavior, OFF retirement,
role denial and installation rollback for dependency/default-ACL drift.

The separate `/site-order-workflow/outgoing` HTTP purpose has a bounded 64 KiB
wire request and 32 KiB canonical body. Legacy requests retain their 4096-byte
cap. Only fixed parameterized prepare/status/retire commands are accepted;
the existing project verifier and dedicated transaction connection are reused.
No client SQL/company/actor identity is accepted. COMMIT-ack loss returns UNKNOWN
without a rollback/retry. New module imports introduce no dependency versions.

The combined transport fixture uses actual ES256 verification with the pinned
SDK, real SQL transactions and synthetic Auth. It deliberately drops the
acknowledgement after real prepare and retire commits, then reconciles by
status without replay. Foreign actors see no operation, worker role cannot
retire even with forged owner metadata, and invalid signatures/extra company
keys fail before opening a connection. All connections close and LOCAL claims
reset. This remains isolated evidence, not hosted GoTrue.

Remaining: the production
dependency/catalog composition, durable client ID journal and RAM editor wiring,
dedicated guarded consent, actual storage/PDF/send integration, independent
review, deployment approval, Release installation and iPhone verification.
Synthetic Auth/fixture success is not real GoTrue, production or device proof.
