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
