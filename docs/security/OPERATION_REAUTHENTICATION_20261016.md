# Server operation reauthentication — staged, default OFF

This branch does not deploy SQL, Edge code or enable production enforcement.
It implements a first enforceable server boundary for secondary password
replacement and Master feature changes. It does **not** complete all Master RPC
step-up, prove Face ID to the server, or certify a TestFlight binary.

## Protocol

`reauthenticate-operation` validates the original JWT against Auth `/user`, then
revalidates that user's password using the server-selected phone/email. A
distinct temporary verification session is ended with `scope=local`; its tokens
never reach the app. Only successful cleanup allows service-only proof issuance.
The app's original session is never swapped or signed out by this handler.

The SQL issuer validates the original actor/session in `auth.sessions`, expiry,
account-deletion barrier/restrictions, operation, exact JSON target, rollout and
Master entitlement where applicable. It stores only a SHA-256 hash of a random
256-bit nonce, with a server-fixed 120-second expiry. Consumer routines check
actor, session, operation and target again and atomically consume the proof in
the same transaction as the business operation. Business rollback also rolls
back consumption. No client boolean, JWT-refresh timestamp or GUC is proof.

Operations: `secondary_password.replace` target `{"user_id":"actor UUID"}`;
`master.feature.set` target `{"feature_key":"allowed key","enabled":true}`;
`master.security_incidents.read` target `{"scope":"platform"}` (reserved for the
separate monitoring lane). Helper:
`private.consume_reauthentication_proof(text,jsonb,text) returns void`.

## Compatibility and rollout

Three private gate rows default OFF: `secondary_password`, `master_feature`,
`master_security`. Legacy routines acquire a SHARE lock on their gate so turning
it ON waits for already-running OFF transactions. OFF preserves old callers;
ON prevents direct legacy replacement/feature changes. Legacy secondary first
setup remains possible, serialized per actor, but cannot overwrite a row once
the gate is ON. The new replace API never creates first-time credentials.

The client capability check falls back to old behavior only for PGRST202 (RPC
missing). Permission/network/malformed responses fail closed. Once enabled,
the secondary reset page requires primary password server verification. Native
biometrics continue in OFF mode; they are not advertised as server proof. The
existing login password/SMS recovery remains unchanged: after recovering the
primary password, users can verify it and replace the secondary password.

The Master feature proof API exists, but its settings client is not wired in
this phase; keep `master_feature` OFF. The separate monitoring lane must wire
its proof request/read consumer before `master_security` can be enabled. Other
Master APIs still lack mandatory server step-up and require later integration.

Before applying, review actual function ACLs/schema, capture rollback definitions,
promote the CLI-generated migration name
`20261016105504_operation_reauthentication_proofs.sql` (Supabase CLI 2.121.0,
`migration new`, local unlinked scratch project), deploy/review Edge, validate
credentials and temporary-session cleanup in a separate Auth project, then test
updated clients. Do not switch production gates ON from this branch or CI.

## Verification and limits

Node tests mock Auth/REST responses; they verify failure handling, identity,
cleanup ordering, unchanged operation targets and no credential return. They do
not prove the external Auth service configuration. Dedicated PostgreSQL 17 uses
pgcrypto and synthetic users/sessions to test real function ACLs, proof reuse,
expiry, actor/session/target mismatch, revoked session, deleted-account
restriction, initial setup/replacement, transaction rollback and concurrent
consumers/rollout/session termination. It is not a production HTTP or native biometric test.

Operational limits: proof retention/pruning and per-actor application throttling
are not installed in this phase; Auth service rate limits still apply. Separate
Auth-project testing must check single-session settings: password verification
creates a temporary Auth session and must not invalidate the original one under
the project settings. Such configuration must fail closed before rollout.

## Protected existing accounts and approval boundary

Phone, Apple and Google Auth identities, company IDs, company membership roles,
Master grants and sub-administrator roles are not modified by this code. The
isolated fixture compares all such synthetic rows before install, after operation
and after restoring exact original function definitions and ACLs. It then runs
the original password and Master feature RPCs again. This is a restore rehearsal
of the lane in an isolated PostgreSQL fixture, not a backup or restore of actual
production accounts, Auth configuration, complete database or a normal-admin UI
comparison.

Apple/Google or other OAuth-only users without an established primary password
cannot obtain this password-only server proof. Gates are global per operation
scope, so keep the affected scope OFF while any affected user lacks a verified
alternative. Do not replace their legitimate recovery with client booleans, token
refresh time or a newly assigned role. OFF preserves the existing biometric
recovery and login code. A trustworthy OAuth/provider reauthentication alternative
and its full recovery tests are required before universal rollout. No provider
link, password, ID, role, company, Auth setting or membership is migrated here.

Production changes require the user's explicit approval after a confidential
backup, isolated restore verification, normal administrator UI comparison and a
reviewable report. Passing this CI does not satisfy those operational prerequisites
or grant approval to apply SQL/deploy Edge/enable enforcement.
