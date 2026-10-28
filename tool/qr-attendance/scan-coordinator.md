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

## Candidate nonce-ledger connection

The synthetic nonce table has been replaced in the Native coordinator test by
`qr-scan-ledger.sql.review-only` and `qr-scan-ledger-hooks.mjs`.
The private table stores only the token hash, exact scanner actor/session,
company/device, subject worker/user, action/source and bounded expiry. No raw
QR token is retained. The hook locks the matching nonce row, loads immutable
scope and database time, and consumes it once using a conditional UPDATE on the
same transaction connection. The update trigger rejects scope substitution,
receipt replacement and reopening of a consumed challenge. Client table access
is revoked with RLS enabled and no client policy.

The trusted authorization callback cannot override ledger scope, time or receipt
state. It still must authenticate the live scanner and subject, revalidate company,
device public key, site/route/source and hold the relevant locks. It is NOT
implemented by this ledger. The regular attendance writer is also still a
trusted hook; the Native test uses toy attendance rows and synthetic authority.
No ordinary employee JWT is minted to write another person's attendance.

The PGlite test checks wrong actor/session, immutable scope, expired consumption,
single consumption, rollback and table ACL. Native CI exercises the existing
coordinator on this ledger with concurrent scan/retry and failed-consume rollback.
This is a review-only schema candidate, not a production migration or an issuer.
There is no production FK mapping, enrollment/issuance endpoint, authorized
scanner writer or production grant. Private-table ownership is not independent
immutable storage. A privileged owner could delete data; no archival or recovery
guarantee is established. All rollout flags remain OFF.

## Internal scanner context candidate

`qr-scanner-context.sql.review-only` adds a client-private registered scanner
table and a private context loader using the existing live-session helper and
company attendance permission. It locks the authenticated scanner's session,
registration, membership and account rows, and the exact active subject worker.
Accounts that are deleted, banned or anonymous are rejected. Permission is checked
after membership locking; the existing session helper is repeated after lock waits.
The scanner remains the actor: the subject's identity is never minted as a JWT.

This limited subset requires the scanner operator's existing
`can_manage_attendance` permission. It does not elevate an ordinary kiosk user.
No registration procedure, key enrollment, public grant or endpoint exists.
The Node SQL loader passes only locked server-ledger scope and checks the returned
actor/session and Ed25519 public-key encoding before giving context to the verifier.

Native tests use the actual new context and ledger SQL with synthetic Auth/session/
permission fixtures and a toy attendance writer. They do not prove real GoTrue
authorization or the SKO writer. The existing normal evidence schema does not
support `qr` verification mode yet; it is NOT mislabeled as manual/GPS/photo.
QR mode, route/photo/report compatibility, authoritative issuance and the real
regular attendance writer remain unresolved activation blockers. Production stays OFF.
