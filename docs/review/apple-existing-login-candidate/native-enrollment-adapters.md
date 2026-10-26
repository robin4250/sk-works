# OFF native Apple enrollment adapters

These are internal review candidates, not a deployed enrollment endpoint. They
do not change the existing generic reauthentication/proof protocol, attendance
second-password behavior, Apple provider, identity data or company memberships.

## Fresh primary password

`native_apple_password_port.mjs` reuses the password endpoint for the identifier
returned by `getUser` for the exact original bearer. It requires a configured
primary password and a trusted `passwordSessionIsolationReviewed` server gate
**before any password exchange**. That gate is false by default: the actual
hosted single-session/CAPTCHA/session-expiry behavior must first be reviewed and
demonstrated to preserve the original session and its refresh/Face ID path.
An after-the-fact getUser check alone cannot prove refresh-token preservation.

Only a verified distinct temporary session may be locally logged out. No
password, JWT, refresh token or credential-version value is returned to the app.
OAuth-only accounts are unavailable here rather than assumed to have a password.
The attendance second password, Face ID and token refresh are not substitutes.

## Atomic bookkeeping

`native-enrollment.sql.review-only` adds a separate default-OFF private schema.
It requires the previously reviewed owner-policy hook/permit schema; it neither
replaces nor configures that hook. No rollout rows are seeded.

The service-only context reader checks the live original SID, Auth account and
deletion restriction, primary credential version, exact Google identities and
company roles. A separate server-only profile fingerprint binds the existing
Auth email/phone/user metadata without returning those values; concurrent
profile changes invalidate enrollment. Provider/app metadata additions are not
confused with the original user profile. The password fingerprint is internal SHA256 of the stored Auth
credential version; the stored password hash itself never leaves SQL. It is
not a password verifier and cannot be populated from app JSON.

Reservation binds the verified Apple subject/token SHA256 and original actor/SID
to the exact internal context. SQL checks the submitted snapshot text's SHA256
and its semantic equality to the current database snapshot. Subject and actor
transaction locks serialize reservations. The owner-policy protected-user row,
same-UID subject permit, short-lived reservation and audit entry commit together;
failure of any write rolls all four back. Replay hashes stay consumed.

Completion requires the exact reservation bindings, a still-live original
session, unchanged password/Google/company context and an actual same-UID Apple
identity matching the permit. Its success status and audit entry are one
transaction. The ledger does not create an Auth identity or sign-in session.
Only the separately verified GoTrue native link can do that.

Unknown exchange/cleanup/acknowledgement outcomes remain reserved or held. A hold
keeps the subject permit, replay ledger and possibly committed Auth identity;
it does not unlink/delete a real identity to pretend rollback. Review/recovery
must reconcile these states. An expired reservation is not automatically
deleted or made reusable.

`native_apple_enrollment_sql_port.mjs` is constructed per enrollment request.
It accepts an exact-bearer authenticator supplied by trusted server code and
selects UID/SID from that verified result. No caller-chosen UID/SID is sent to
SQL. Its service key stays in server headers. Opaque `sb_secret_` keys are not
placed in bearer headers. All RPCs use one fixed project origin, reject
redirects, bound response bytes and enforce hard deadlines even if fetch ignores
abort. Snapshot context and its fingerprint are never public response fields.

## Verification and remaining boundaries

- Existing 13 real-RSA/synthetic-port enrollment cases and 11 primary-password
  port cases remain successful, including the new pre-exchange isolation gate.
- Nine SQL HTTP-port cases verify selected actor/SID, wrong/expired identity,
  server credentials, exact snapshot serialization, rebinding, response limits
  and ignored-abort deadlines.
- Twelve isolated PostgreSQL WASM cases execute the exact SQL, testing OFF/ACL,
  actual service database role, snapshot/credential/account restrictions,
  same-UID permits, replay, completion, hold and transaction rollback on audit
  failure. A separate Native PostgreSQL 17 job executes the same twelve cases plus a
  real two-connection same-subject race: exactly one reservation/permit/audit
  commits. The fixed localhost fixture URL is checked before any connection.
  This is not a hosted Auth enrollment test.

The earlier official GoTrue v2.197.0 native-link proof is retained unchanged. It
does not yet connect this new SQL lifecycle or prove hosted refresh-session
preservation for fresh-password exchange. Before deployment, this candidate
still needs current schema/catalog guards and the existing complete account/
company access-policy review; current-version Auth integration of this new lifecycle; reviewed unused restoration and retention/recovery operations;
the trusted exact-bearer verifier and native-link HTTP adapter connected to a
bounded authenticated endpoint; hosted native-only/provider/hook and password
session conditions; and the original Google UID/company/session/Face ID tested
on the owner's iPhone. Keep all gates OFF until those conditions are satisfied.

Official references reviewed 2026-10-26: Supabase `signInWithPassword`, native
`linkIdentityWithIdToken`, supported custom access-token hooks, and PostgreSQL 17
`sha256(bytea)`/`convert_to`/`encode`. No production schema or Auth settings were
read or changed by this candidate's tests.
