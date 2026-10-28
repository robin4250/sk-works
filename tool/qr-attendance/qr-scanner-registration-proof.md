# QR scanner registration proof — internal review candidate

This extension connects the existing second-password verifier and private
reauthentication proof ledger to the scanner key-possession registration path.
It does not modify the shared proof issuer, whitelist or consumer. The old
registration primitive is replaced only if its reviewed body hash and owner
match; its OID and existing private ACL are retained. No new public RPC or grant
is added, QR remains OFF, and no attendance is written.

The internal issuer locks the server key challenge, checks the live scanner
manager/session and secondary-password rollout, calls the existing password
verifier, then binds a generated proof hash to exact company/actor/session/device/
canonical key and the current credential fingerprint. Expiry never exceeds the
key challenge or 90 seconds. A wrong password returns NULL and must be committed
normally so the existing failed-attempt/lock counters persist. The request-only
Node issuer commits this result, does not log credentials, and never retries an
unknown outcome or a second call on the same instance. Raw proof delivery is an
internal contract, not a deployed transport.

The dedicated consumer rechecks the live session, QR/secondary rollout and exact
scope, then atomically consumes the proof with the current credential fingerprint.
The existing possession adapter verifies the key signature and combines proof
consumption, scanner registration, audit and challenge consumption in one database
transaction. A later error rolls all of them back. A changed credential, expired
proof, different session/device/key or replay cannot reuse the approval.

Tests reuse actual candidate registration/PoP SQL, the existing bcrypt password
verifier and existing proof-table contract. They cover persistent wrong-password
counters, lockout, proof hash-only storage, signature failure, exact target/session,
credential rotation, expiry, replay, audit-failure rollback, private ACL and (in
Native PostgreSQL) concurrent completion. Auth/session/company permissions and
rollout remain synthetic fixtures: these tests are not real-GoTrue evidence.

Still incomplete: verified JWT-to-request-pool binding for this new issuer,
request rate limits and reconciliation, public transport/client registration,
real-device key custody/user presence, proof lifecycle cleanup, independent
catalog install/restore review, QR attendance mode and the regular attendance
writer/route/photo compatibility. No production or existing account data changes.

## Private challenge delivery and uncertain-result reconciliation

The internal request-scoped challenge adapter now uses the actual challenge issuer and
locked loader, validates exact company/device/canonical key and verified actor/session,
and releases challenge data only after COMMIT. It snapshots all returned scalars before
awaiting COMMIT and rejects further operations on that instance after any attempt.
An uncertain COMMIT does not automatically retry issuance. A separate authenticated
read by exact target retrieves the same live challenge/nonce/expiry without issuing or
extending it. Missing, consumed or expired challenges return no live challenge; this
is not permission to automatically issue again. Read requires the same current live
session, permissions and QR gate, and all functions remain private with no client grants.

The Native proof integration now uses this adapter rather than its handwritten issue
transaction. It tests a deliberately lost COMMIT response followed by exact-target
read, unchanged challenge identity/expiry, no duplicate row, other-session rejection,
missing and expired reads without writes, then the existing password proof and key
possession registration path. Four Node boundary tests and PGlite integration pass.
Native PostgreSQL CI is pending on this commit. Auth remains synthetic in this new
composition; no public/JWT transport, device custody, regular attendance writer, QR
mode compatibility or production deployment is completed by this addition.
