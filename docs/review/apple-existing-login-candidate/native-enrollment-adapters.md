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


## Successor-session completion candidate (OFF, internal only)

The real GoTrue successor tests establish that account UID, Google identity and
company data can remain intact while adopting a new same-UID Auth session. They
do not require keeping the original refresh token valid.

`native-enrollment-successor.sql.review-only` adds a separate default-OFF gate
and an ungranted private completion function. It atomically locks the existing
reservation, checks a fresh same-UID successor SID and the exact password/profile,
Google and membership snapshot, checks the reserved Apple subject and owner permit,
then records both original and successor SIDs without rewriting the original SID.
Repeat completion, wrong SID/actor, old/future/expired sessions and changed evidence
are rejected. No tokens, users, sessions, identities or companies are written by
this SQL. Tests use isolated synthetic Auth tables, not a real JWT boundary.

This is NOT a deployed handoff or a new enrollment route. The existing reservation
still uses the old password-isolation review gate; a reviewed primary-password
successor flow is not connected. The broker must independently authenticate the
exact returned successor bearer, bind the issued SID to this reserved operation,
transfer the refresh credential only to the initiating client through a protected
single-use channel, and handle uncertain results without fallback to an invalid
old session. Those broker/client adapters, secure delivery, rollout/restore guards,
concurrent behavior, real-GoTrue SQL composition and iPhone validation remain
unimplemented. There are no service/client grants; keep every enrollment gate OFF.


## Durable successor attempt candidate (2026-10-28, OFF)

The private successor SQL now commits one request-bound attempt before external
Auth linking. Its primary key plus request/advisory locks reject repeat and
concurrent claims. Completion requires this exact actor/original SID/snapshot
claim. A failed or uncertain external result never releases the claim for retry.
The claim revalidates the original live session, account and immutable snapshot;
completion still validates the new same-UID session independently.

`native_apple_successor_db_port.mjs` is an internal request-scoped adapter for a
separately provisioned privileged server pool and trusted exact-bearer verifier.
It commits the private claim before returning it, uses parameterized SQL,
transaction-local service context and bounded SQL/lock waits, rolls back failures,
and permits only one completion call. An unknown COMMIT leaves no reusable local
binding; the durable database claim may already exist and must be reconciled.
No credentials are stored or included in query arguments. Node mocks cover commit
ordering/OFF/foreign claims/unknown commits; PGlite validates exact SQL and Native
CI additionally races two connections. This is not real JWT-to-DB composition.

The adapter has no public endpoint. The following internal broker candidate wires it to the handoff runtime. A trusted
bearer verifier, deployment-scoped pool, durable receipt reconciliation and secure
client delivery remain required. Password successor reservation, rollout/restore
guards and iPhone session adoption are still incomplete. No grant, production
connection or activation was made. Existing account UID/Google/company data is
preserved; retaining an obsolete refresh token is not a requirement.


## Request-scoped successor broker composition (2026-10-28, OFF)

`native_apple_successor_broker.mjs` connects the existing Auth HTTP adapter,
private transactional DB adapter and verified handoff in one request-scoped
composition. It binds and verifies the original bearer using Auth, commits the
durable reserved-request claim before linking, verifies the issued same-UID
successor, completes private SQL bookkeeping and invokes the trusted delivery
sink only after a matching receipt. An unknown delivery is never retried or
rewritten as a held completed request. Failed or unknown completion may hold
only the originally claimed request/actor/SID through the existing SQL, which
cannot change a completed row. Local duplicate invocation is rejected.

All independent gates default OFF. The composition accepts an already-reserved
request and DOES NOT solve primary-password successor reservation or expose a
public route. The delivery sink, deployment-specific privileged pool and key
resolver are externally trusted dependencies, not proof of a deployed service.
The new Node tests execute the adapter modules against synthetic HTTP/DB services:
commit/link/complete/deliver order, denied claim, OFF, lost completion/delivery,
credential non-output and no successor logout. They are not real GoTrue-to-DB
composition, TLS delivery or iPhone adoption tests. Durable reconciliation,
public endpoint authentication/rate limits, rollout/restore, PW reservation and
client adoption remain incomplete. No production setting or grant changed.


## Primary-password successor Auth transport (2026-10-28, OFF)

`authenticatePrimaryPasswordSuccessor` is an internal opt-in port on the existing
Auth transport. It verifies the originally bound bearer, derives the email/phone
only from that verified actor, performs the password login once, and independently
verifies the same-UID, different-SID result and bounded refresh credential. It
retains that new credential for a future reviewed reservation/handoff instead of
logging it out or asserting that the obsolete Google refresh remains usable.
The existing handler and broker do not enable this port. It does not rebind the
Apple link operation, reserve a subject, deliver to a client, or update any password,
Google identity, company or profile. A failed/unknown attempt is never automatically
retried. Any created session is deliberately not revoked to pretend rollback.

The caller must still revalidate the original versus successor company/Google/
credential/profile snapshot atomically in SQL and create the PW-successor-bound
reservation, with failure reconciliation and a safe client handoff. None of those
steps or public endpoint wiring is implemented by this Auth-only change. Same UID
alone is not sufficient evidence of the full enrollment policy. The three new
HTTP-fixture tests and the eleven existing Auth/handler tests pass locally; these
are synthetic transport tests, not a new real-GoTrue reservation proof. All gates
remain OFF and no production configuration or grant changed.


## PW-successor snapshot transfer (2026-10-28, internal OFF)

The new private SQL in `native-enrollment-password-successor.sql.review-only`
anchors the original authenticated SID, company/Google/password/profile snapshot,
Apple subject and token hash BEFORE the password login. That intent commits before
the external Auth call and stores no credentials. The internal transfer then locks
the intent, verifies the fresh same-user password SID against the official GoTrue
v2.197.0 `auth.mfa_amr_claims` password record and DB time, compares the snapshot
without SID, and calls the existing reservation SQL inside the same transaction.
A request-bound trace retains the initial SID even if its Auth row is deleted.
The final existing successor receipt references the PW SID; the intent links it
back to the initial SID. Neither a failed audit nor a failed reservation creates a
partial permit/transfer. Replayed intents and changed snapshots are rejected.

`createNativeApplePasswordSuccessorBroker` connects the new Auth password port,
intent/reservation DB adapter and existing durable successor broker. Apple token
verification precedes all password operations; freshness is checked again at slow
boundaries. The order is intent commit -> password login -> snapshot reservation
commit -> durable pre-link claim -> Apple link -> completion -> trusted sink.
All independent gates default OFF, the current public handler never calls this
composition, and the functions have no client/service grants. A failed/unknown
password flow may obsolete the original refresh and require a real sign-in;
there is no fictional rollback/logout or automatic resubmission.

Local validation: 21 PGlite tests succeeded, 4 Native-only tests skipped; the new
Native test races the same PW intent on two real PostgreSQL connections. Node
broker/DB composition tests: 10 succeeded. These are synthetic HTTP and Auth-table
fixtures, not proof of managed Auth schema compatibility, real GoTrue-to-DB
composition or client delivery. The official AMR model source is
https://github.com/supabase/auth/blob/v2.197.0/internal/models/amr.go . Managed Auth
schema/AMR timestamp compatibility, complete session-validity policy, deployment
least privilege/rate limits, immutable delivery reconciliation, client adoption,
owner iPhone/Face ID and recovery remain incomplete. This is not a deployable
production activation or migration. No production settings, identities or company
records were changed.


## Real Auth to PW-successor broker integration candidate (2026-10-28)

`native_password_broker_gotrue_test.go` and the fixture-only Node runner exercise the existing PW-successor broker, Auth HTTP port, PostgreSQL adapter and exact private intent/reservation/claim/completion SQL in one chain. A dedicated workflow reuses the pinned official GoTrue commit and native Apple provider fixture. The Node fetch bridge only maps the pinned project-origin requests to the explicit loopback test server; it does not relax the application's production issuer or origin validation. The issuer string in the disposable fixture is synthetic configuration, not a request to the hosted project.

The added cases require same-UID password and Apple successors, preserved Google identity/profile/company/password snapshot, one completed receipt, one delivery and continued refresh of the final successor, plus wrong-password rejection before native linking. Credentials remain in fixture process memory/stdin and are never printed or persisted. They do not establish real Apple credential acquisition, managed Auth schema compatibility, a least-privilege deployed pool, an actual TLS client delivery/adoption channel or failure recovery. No public route/grant or production change is added. Local Node syntax verification passed; real GoTrue/PG execution is pending the new CI result and must not be reported as passed before it completes.


### Executed official-Auth integration evidence

Head `3c6690524c3f6f511353a487803bc4c95763a920`, workflow `Apple password successor real broker`, run `40657896428`, job `122713309692`: success. Both the successful PW→atomic reservation→durable claim→native Apple→private completion→one in-memory delivery→two final refreshes case and wrong-password rejection case passed against the pinned official GoTrue HTTP and PostgreSQL fixture. The final UID, original Google identity, profile, company record and credential-version snapshot are unchanged.

The integration first exposed an actual Auth-port compatibility defect: a verified singleton audience array was rejected. The port now accepts exactly the existing `authenticated` string or a singleton array containing that same string. Empty, multiple, duplicate, foreign and non-string audiences remain rejected; Auth `/user`, issuer, role, SID and expiry checks remain in place. The 12 Node Auth-port tests passed before CI execution.

A separate fixture issue was isolated using only boolean diagnostics: official `setupAPIForTest` selects bcrypt MinCost and test DB encryption, causing a newly created plain fixture hash to migrate during password authentication. The successful unchanged-credential case now starts with ordinary bcrypt cost and the fixture's configured encrypted-at-rest format. Application credential snapshot guards were not loosened. A real credential hash/encryption migration or password change during enrollment must still fail closed; it may require an explicit fresh sign-in and a new enrollment attempt, and the recovery/user experience is not complete. No automatic retry or password reset was added.

This evidence is not a production activation: the provider is a signed synthetic Apple fixture, HTTPS delivery is replaced with an acknowledged in-memory sink, project-origin requests use an explicit loopback-only bridge, and the DB pool is an isolated privileged fixture. Managed schema verification, deployed JWT→least-privilege DB integration, safe real delivery/client adoption, restart reconciliation and owner iPhone testing remain incomplete.
