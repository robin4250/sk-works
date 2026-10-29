# Scanner registration HTTPS composition — default OFF

This candidate connects the existing exact-bearer GoTrue verifier, private
challenge/proof/PoP/receipt adapters and one request-bound pool transaction to
an actual native Node HTTPS request/response pair. The factory starts no
listener and installs no production route, grants, settings or QR rollout.
Only trusted configuration selects the HTTPS public origin, project/issuer,
public API key, private pool and mandatory verified-principal admission port.
No request may choose those dependencies or provide actor/session/subject claims.

The handler requires the real encrypted TLSSocket and original HTTP request/
response pair, one exact Host/Authorization header and one fixed path. It rejects
forwarded-TLS assertions over plaintext, foreign Origin, caller authority fields,
redirects, compressed/over-limit bodies and invalid UTF-8. JSON request bodies
are limited to 8 KiB with a body deadline. Auth verification, admission, overall
request and response delivery are bounded. Admission receives only frozen
verified UID/SID/operation/request ID — never the bearer, password or proof.
Responses are bounded, no-store and generic on failure, with no CORS exposure.

Operations are challenge issuance, **read-only** challenge reconciliation,
second-password proof, signed completion, and **read-only** original receipt
reconciliation. Proof failure commits the existing failed-attempt counter and
returns accepted:false, not a rollback disguised as an authentication failure.
Completion still checks Ed25519 key possession and the original company/live SID
through the existing SQL. The server never adopts an employee/subject identity.

Request IDs correlate responses; they are not a new durable idempotency ledger.
There are no automatic retries. A dropped challenge response is reconciled by
exact target without reissuing/extending it. A dropped completion acknowledgement
is reconciled by the original receipt, without registering or consuming again.
Missing state is unconfirmed, not permission to retry. HTTP timeout does not
cancel a database command already running; its outcome may remain unknown.
A pool lease acquired only after timeout/closure is released before BEGIN or
claim initialization, rather than starting a late registration transaction.
Response finish proves only transport handoff, not client receipt. Lost proof
delivery, durable admission/ingress limits, safe client-side pending-operation
state and restart handling remain activation blockers.

The disposable fixture uses a generated ephemeral certificate with its CA
explicitly trusted by the HTTPS client. It composes actual TLS -> actual GoTrue
-> actual candidate PostgreSQL functions, including wrong-password counter
commit, key signature completion, a destroyed acknowledgement followed by exact
receipt read, no duplicate audit, other UID/SID and revoked-session rejection,
and pooled claim cleanup. Business permission/admission and the privileged pool
remain explicit fixtures; test-only fixed-project HTTPS-to-owned-loopback Auth
mapping does not relax product HTTPS checks. Real-stack CI is required before
these cases are reported passed. Local nine TLS boundary tests plus existing
verifier/recovery tests exercise rejection/deadline paths, not production hosting.

## Canonical attendance remains blocked

Actual source `20261002014011_allow_gps_auto_attendance_verification_mode.sql`
permits manual/location/gps_auto/location_photo, not qr. Existing normal client
capture insertion in `attendance_verification_repository.dart` binds created_by
to the live actor and preserves company/capture/report rules. The reviewed scan
coordinator still has an unimplemented trusted regular-writer hook. Issue #273
does not provide a canonical delegated QR mode/source/FK contract. No mode is
guessed, QR is not relabeled as GPS/manual/photo, worker identity is not minted,
and no attendance table, constraint, migration, source record, signature or
original is changed. Real device key custody, least-privilege hosted pool,
catalog install/restore, all registration routes, photo/route/report compatibility,
attendance writer and owner iPhone verification remain incomplete. All rollout
flags, including individual-document exemption, retain their prior OFF state.
