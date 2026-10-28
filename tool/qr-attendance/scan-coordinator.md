# Review-only QR scan coordinator

The coordinator joins the existing Ed25519 challenge verifier to a trusted
transaction adapter contract. It accepts a scanner actor/session from verified
server authentication, an opaque QR token, challenge ID and device signature.
The signed scope and all authority fields are loaded from locked server records,
not accepted from the client. Only the existing normal attendance writer may
produce the receipt. Consumption and attendance must commit or roll back together.

The adapter must acquire the shared QR rollout/settings gate and consistent
device/session/subject/source/challenge locks for the entire transaction, with
bounded waits. Its writer must revalidate company, site/route, source-clock-in,
photo and report rules and use server acceptance time. It must never perform a
remote attendance write inside the transaction. The consume operation must CAS
the unconsumed challenge and bind its immutable receipt. Serializable retry is
the adapter's responsibility and may not repeat external side effects.

Current authorization and the exact signature are still required for a duplicate
scan. A consumed challenge may return its original receipt after expiry but may
never write again. OFF, revoked device, expired scanner session or inactive
subject deny even a duplicate receipt read. Errors must not be logged with raw
tokens/signatures; this function is not a public error response implementation.

Five Node tests use a synthetic serialized adapter to exercise duplicate scans,
failed-consume rollback, revocation/OFF, altered scope/token/signature and caller
buffer mutation. They do not establish PostgreSQL isolation or authorization.

`qr-scan-postgres-adapter.mjs` now implements the transaction boundary on one
PostgreSQL connection: SERIALIZABLE, bounded SQL/lock waits, the existing QR gate,
database-only trusted hooks, COMMIT-before-return and rollback-before-release.
It does not set an arbitrary employee JWT identity to impersonate the subject.
The adapter is request-scoped; verified session initialization and the context,
normal writer and receipt-consume hooks still require authoritative production
implementations. They must use the supplied connection and may not perform
remote writes. Database serialization errors are returned without automatic retry.

The native CI reuses the candidate common QR gate SQL but uses synthetic scanner
authentication, challenge and attendance tables. It verifies failed-consume
rollback, two concurrent scans producing one receipt, explicit same-token retry,
OFF denial and transaction-local claims cleared in pooled connections. It is not
an authorization or real SKO attendance writer test. Existing normal client
attendance inserts run under the worker's own RLS; a scanner cannot simply reuse
that path for another employee. A reviewed authorized QR writer is still needed.

No production context/writer/nonce adapter, challenge issuance, device enrollment,
HTTP endpoint, production grant or activation exists here.
In particular, this does not prove every QR writer calls the master gate.
Native SQL/GoTrue integration, all real writer paths, actual signing keys,
recovery and iPhone operation remain activation blockers. Production stays OFF.
