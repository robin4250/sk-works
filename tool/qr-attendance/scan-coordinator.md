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

No real database adapter, regular attendance integration, challenge issuance,
device enrollment, HTTP endpoint, production grant or activation exists here.
In particular, this does not prove every QR writer calls the master gate.
Native SQL/GoTrue integration, all real writer paths, actual signing keys,
recovery and iPhone operation remain activation blockers. Production stays OFF.
