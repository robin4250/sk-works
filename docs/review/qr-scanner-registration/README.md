# Internal scanner registration candidate

This adds an ungranted, review-only registration primitive to the existing QR
scanner context table. An attendance manager may register only their own scanner
key, under a live session and an exact operation proof bound to company, actor,
device and canonical Ed25519 public key. It does not change employee RLS or
impersonate the employee whose QR will later be scanned.

The same key can be confirmed with a fresh proof. Existing device ownership,
company, key and revocation state cannot be replaced by this primitive. Proof
consumption, insertion and registration audit are in one transaction. A failed
audit must undo both the insertion and proof consumption. No proof or private key
is retained in the audit.

**Not available for registration.** The existing proof issuer does not recognize
`qr.scanner.register`; the production consumer must therefore reject it. The SQL
fixture uses a synthetic exact-proof authority solely to test atomic composition.
Issuer/second-password policy integration, device key possession/hardware binding,
cross-actor/kiosk delegation, registration UI, revocation/key replacement,
registration concurrency with membership/permission changes, independent audit
retention, catalog installation/rollback guards and real GoTrue/device tests remain
unimplemented. No public grant, endpoint or enabled feature is added.

The actual QR attendance writer also remains absent: existing verification modes
and photo/route requirements must be reviewed and extended without changing the
meaning of previous attendance. This primitive does not make scans create valid
attendance.

The isolated SQL test reuses the scanner-context fixture and checks exact proof,
wrong company/permission/session/key, replay, revoked device, fixed ownership,
same-key confirmation, audit failure rollback and client/service-role ACL denial.
Auth, permission and proof issuance are synthetic. Local PGlite passed; Native
PostgreSQL is run by the QR master gate workflow. No production change was made.

## Key-possession composition candidate

The separate [key-possession candidate](key-possession.md) now adds a private
server-issued challenge and a Node/PostgreSQL adapter that verifies the requested
Ed25519 key before invoking this exact-proof registration primitive. Registration,
proof consumption, audit and challenge consumption are one transaction. It is
not a public route, hardware-backed device proof or a completed proof issuer.
The primitive by itself still does not verify key possession, and must not be
exposed directly. Existing registration remains unavailable until the genuine
issuer, JWT/request-pool boundary, enrollment/revocation UX and rollout are
reviewed and tested. No production change or feature activation was made.
