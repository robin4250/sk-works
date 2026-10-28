# Scanner key possession before registration — internal review candidate

The existing own-scanner registration primitive now has a separate private,
server-issued challenge ledger and a request-scoped Node/PostgreSQL adapter.
The manager signs with the canonical Ed25519 private key requested for their
scanner. Company, actor, live session, device, public key, challenge ID, random
server nonce and exact deadline are covered by a domain-separated signature.

The issuer checks the existing live-session and attendance-manager helpers.
An active challenge for the same exact session/device/key is returned unchanged
on issuance retry; changing the key or company is refused. Completion locks
the server record, rechecks session/permissions and database time, verifies the
signature before invoking existing exact-proof registration, then consumes the
challenge and commits. Registry, operation proof, audit and challenge changes
rollback together. Concurrent completion can return at most one success; a
serialization failure requires explicit reconciliation/retry, never automatic
re-registration with a new challenge. Lost completion responses need a separate
safe status channel, which is not provided here.

All new tables have RLS and no client/service-role access. Functions are private
and ungranted. The `qr.scanner.register` reauthentication proof issuer remains
unsupported and therefore fails closed. No endpoint, registration UI or feature
activation is added, and no attendance is written. This is possession of a key,
not evidence of hardware-backed storage, device identity or user presence.

Node tests cover domain/key/actor/session/nonce/expiry substitution, no proof
consumption on bad signatures, rollback on consumption failure and mutation of
the incoming signature buffer. PGlite composition reuses the real registration
SQL with synthetic Auth/permission/proof authorities and checks successful
registration, same challenge reuse, replay, foreign session, expiry, ACL and
audit-failure rollback. A Native PostgreSQL CI runner adds concurrent completion.
Neither test establishes real GoTrue authorization or real-device key custody.

Before use: integrate the genuine proof issuer and second-password policy,
verified JWT-to-request-pool boundary, enrollment/revocation/retention/rate limits,
independently reviewed catalog install/restore guards, hardware/device UX and
actual client registration. Regular QR attendance mode/writer compatibility is
still unfinished. Production, existing accounts, signatures and data are unchanged.
