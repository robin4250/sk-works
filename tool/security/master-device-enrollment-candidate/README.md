# Master device enrollment — safety design candidate

Status: design only, not deployed or enabled. Existing passwords, devices and
access policies must be preserved. Device enrollment must be performed by the
owner after the entire flow and recovery have been tested.

The isolated SQL candidate also contains request, service-only approval and
completion primitives and a separate legacy RPC gate. This is not a complete
security protocol: no verified approval service or independent recovery is
implemented. The legacy gate blocks lock/revoke while enabled, and no secure
replacement is provided yet. The SQL must not be enabled, deployed, or used
for actual device registration. The test identity and passwords are synthetic.
`verified-approval.mjs` is an offline composition candidate only: its adapter
and atomic database revalidation do not yet exist. Secure delivery of the
approval token to the requesting session is also unresolved; it is not a
deployable service or a recovery implementation.

## Existing components to reuse

`tool/staged/master_device_lock_reauthentication.sql` provides a default-OFF
operation proof for device lock, and
`tool/staged/master_last_usable_device_guard.sql.review-only` provides a
candidate last-usable-device guard. Neither establishes that bootstrap, revoke,
or registering an additional device is safe. Check the exact current function
definitions and deployed gates before using either candidate.

The existing bootstrap RPC accepts a master session when there are no active
devices, without server-side second-password proof. A local biometric success
cannot itself be verified by the server: do not treat a client boolean as
evidence. Existing lock/revoke entry points also need server-side enforcement,
including concurrency-safe protection against losing the last usable device.

## Proposed protocol, not implementation

* Keep enforcement OFF until compatible clients and recovery are demonstrated.
  The old RPC must be gated at the database boundary after activation so a
  direct API call cannot bypass the new path.
* Verify a live, non-anonymous master session and deletion/banned barriers.
  Verify the second password using the existing credential checker; ensure
  failure counters commit even when a password is wrong. Never log passwords,
  tokens, recovery codes or private keys.
* Use a short-lived, single-use server-issued challenge bound to the actor,
  live session, action, exact canonical device public key and operation nonce.
  A trusted device must cryptographically approve an additional enrollment;
  a hardware-backed non-exportable private key should require user presence
  where the platform supports it. Client-reported Face ID is not proof.
  The current candidate's service-only approval function accepts an asserted
  verification result. The service that verifies that result does not exist;
  no test of the primitive establishes independent user presence.
* First-device bootstrap has no trusted device to approve it. It requires a
  separately verified, owner-controlled recovery channel and a secure enrollment
  procedure; second password alone must not be presented as biometric proof.
  If those prerequisites are not available, fail closed and preserve recovery.
* Registration and approval consume the challenge atomically, under a
  per-master transaction lock, recording only necessary audit metadata. A
  maximum of three active master devices is a proposed rule subject to legacy
  inventory and recovery compatibility; do not automatically remove any devices.
* Lock or revoke requires an action-specific proof and locks the owner's device
  set before checking the last-usable-device invariant. Recovery is a separate
  audited process, rather than an unchecked bypass. Concurrent requests must
  not revoke all devices.
* iPhone, iPad and Mac identity and key support must be explicitly tested;
  browser access is unsupported until an appropriate secure WebAuthn design,
  origin verification and recovery are demonstrated. Do not infer device type
  solely from a shared iOS platform flag.

## Required verification before activation

Real PostgreSQL tests must cover direct calls to old RPCs, wrong password and
lockout, expired/replayed/foreign-session challenges, actor and device-key
substitution, two concurrent first enrollments and concurrent last-device
revocation, approval by a revoked device, recovery and restart, audit retention,
and an unchanged legacy user/session. Test legitimate iPhone, iPad, Mac and
lost-device recovery on the actual platforms. Verify accessibility, owner
identity, explicit approval, key restoration and clear rollback. Do not activate
or claim 3-device registration is available before these checks pass.

## Session-bound dual-proof composition (2026-10-28)

The isolated `issueDualProofApproval` now requires the existing session-bound
v2 approver signature, rather than accepting a transferable v1 signature.
The requesting device still proves possession of the exact intent key.
Synthetic Node tests reject another active owner session and legacy v1
approvals before the atomic claim is invoked, and retain concurrent single-use
acceptance in the test adapter (7 Node tests pass).

This is not an operational enrollment service. The trusted database adapter,
atomic session/device revalidation, secure delivery, existing-device key
migration, first-device recovery and real platform proofs remain unimplemented.
No production settings, passwords, device registrations or DB were changed.

## Trusted clock contract (2026-10-28)

Dual-proof composition no longer accepts a request-supplied `nowMs`. It requires
`databaseNowMs` from the trusted context; missing or invalid time is rejected.
Tests show a forged request time cannot revive an expired intent. A real adapter
must obtain this time from the database and check a fresh database time again
inside the locked atomic claim, alongside current sessions, devices and nonce.
The synthetic adapter only demonstrates the interface: neither a real database
adapter nor first-device recovery/key migration is implemented. Keep OFF.


## Pending public-key migration inventory (review only)

`key-migration-proposal.mjs` accepts canonical P-256 SPKI public PEM only and
hashes that exact PEM, matching the current intent hash contract. A legacy random
device identifier is never interpreted as a key. The authoritative owner/device
snapshot must come from the future locked server adapter, not request metadata.
The SQL stores only `pending` proposals: no active/trusted state, client grant,
registration endpoint, approval or migration of existing devices is provided.
SQL itself does not verify cryptographic key validity or proof of possession.
The private device FK intentionally rejects device deletion while evidence is
referenced; retention, safe cancellation and owner/device deletion compatibility
are unresolved and must be designed before deployment. Node and SQL tests use
synthetic identities only. Real public-key custody, user-presence verification,
atomic approval, bootstrap/recovery and platform testing remain incomplete.


## Pending-key storage adapter candidate

`key-migration-pending-adapter.mjs` uses a trusted PostgreSQL pool and a single transaction to reuse the existing live-session and master checks, lock the owned device, validate canonical P-256 material, and persist only a pending proposal. It does not install caller JWT context, expose an endpoint, grant a role access, activate a key, or make legacy devices trusted. The pool must carry independently verified auth context and the required private privileges. The adapter has only mock database tests so far; actual PostgreSQL/GoTrue, concurrency, pool-context isolation and production ACL verification remain required. A commit failure is returned as unknown and is never automatically retried. An explicit identical retry reads the same pending record.

## Pending adapter contention bound

The internal pending-only adapter applies transaction-local 1 second lock and
5 second statement timeouts before identity/device reads. A busy device causes
rollback and an error; the adapter does not automatically retry an uncertain
write. The native PostgreSQL fixture holds a device lock, verifies timeout with
no pending row left behind, then explicitly retries after releasing the lock.
This does not implement trusted key activation, independent owner approval,
key migration or recovery. Production remains unmodified and OFF.

## Key-migration possession prerequisite (review only)

`key-migration-possession.mjs` verifies a purpose-separated P-256 signature over
an exact migration proposal, owner session, device, key hash, nonce and bounded
server-issued challenge. The result stays `pending`; generating a key and signing
with it never identifies its holder as the owner or approves migration. Three
synthetic tests reject substitutions, expired/consumed challenges, ineligible
devices, invalid intervals and another signature purpose.

The trusted challenge issuer, database-backed nonce storage/atomic consumption,
second-password/independent owner approval, platform key custody and the actual
migration adapter remain unimplemented. This verifier is not connected to the
pending storage adapter or an endpoint and cannot activate or replace a key.


## Proof-to-pending atomic candidate (not key approval)

`key-migration-proven-adapter.mjs` joins the existing key possession verifier to a server-owned, row-locked challenge and pending proposal in one PostgreSQL transaction. It reads time from the database, rejects replay/expiry/foreign sessions before insertion, rechecks the live owner session and expiry before consuming the nonce, and rolls both pending insertion and consumption back on failure. An identical consumed challenge is rejected rather than automatically resent. The existing unproven inventory adapter remains an inventory-only candidate; neither path grants signing authority or activates a key.

`key-migration-challenges.sql.review-only` is a private RLS-enabled table with no client grants. Trusted challenge issuance/delivery, independent owner approval, retention and owner/device deletion compatibility, hardware-backed keys, production integration and recovery remain unimplemented. A synthetic-auth PostgreSQL CI races two connections and requires exactly one proof consumption. Local Node and PGlite tests are synthetic, not actual owner or device enrollment. No endpoint, public grants, activation or production changes are introduced.


## Internal challenge issuance candidate

`key-migration-challenge-issuer.mjs` now issues the key-possession challenge
inside a bounded transaction after checking the authoritative owner session,
master role, owned unlocked device and canonical P-256 key. A device row lock
serializes issuance, one unconsumed live challenge per device is permitted, and
nonce/ID are server-generated while both timestamps come from PostgreSQL.
The exact existing signing payload is checked before commit. A challenge grants
no key trust, approval or activation. Unknown issuance must not be silently
retried; the candidate refuses replacement until the active challenge expires.

PGlite covers issue/sign/proof-to-pending/replay and scope refusal. A separate
Native PostgreSQL CI runner covers two concurrent requests producing exactly
one active challenge. Its auth context is synthetic, not a real owner approval.
This internal adapter has no public endpoint, client grants, secure delivery,
second-password/user-presence proof, bootstrap/recovery or key activation.
Owner confirmation and the remaining production deployment conditions are still
unimplemented. Do not enable or register real devices using this candidate.

## Original challenge readback (review only)

`key-migration-challenge-delivery.mjs` supports an explicit readback after an
uncertain issuance response. In a bounded transaction it rechecks the live master
session and owned unlocked device, then returns only the original unconsumed,
unexpired challenge for that exact canonical key and requesting session. It does
not generate a nonce, extend expiry, write state, consume proof or activate a key.
The existing issuance runner checks repeated readback equality, another actor,
session/key substitution, consumed/expired challenge and locked-device refusal.
PGlite uses synthetic auth and does not establish production identity assurance.

This is an internal read adapter, not public delivery: no HTTP endpoint, client
grants, second-password proof or independent owner approval is added. A trusted
transport must bind request authentication and response delivery to the exact
original owner session, prevent caching/logging, and be reviewed before exposure.
No production database, password, device registration or signing key is changed.


## Internal password-verified issuance (review only)

`issuePasswordVerifiedMigrationKeyChallenge` composes the existing second-password verifier with challenge issuance in the same bounded transaction. It returns `accepted:false` normally on a wrong password and commits the verifier's failure counter; rolling back that rejection would disable lockout. A locked credential rejects issuance. A correct password permits only a pending key-possession challenge, with existing password hash and device identifier unchanged. The older low-level internal issuer is retained for isolated fixture compatibility, remains non-public and must not be exposed as a password bypass.

PGlite synthetic-auth tests confirm five wrong attempts persist the counter and lock, locked credentials cannot issue a challenge, and successful verification after synthetic lock expiry resets the counter and issues the bound challenge. The existing Native PostgreSQL issuance runner now exercises the same checks using the existing SQL password verifier. Native CI is pending for this revision. This is not independent owner approval, biometric evidence, public delivery, key activation, migration or recovery. A public flow must bind independently verified auth and credentials securely, gate all lower-level paths and be tested before exposure. No production changes were made.


## Review-only challenge request boundary

`key-migration-challenge-http-candidate.mjs` connects HTTPS POST request parsing to the existing password-verified issuer and exact-session readback. Actor, session and a request-scoped authenticated database pool come only from an independently verifying service adapter, never body fields. It rejects extra fields and oversized bodies, uses no-store responses and generic errors, and has a bounded request deadline. A timeout can leave an unknown database outcome; it never retries issuance, and the separate read action reconciles the original nonce without extending its lifetime. The existing password failure counter commits on an ordinary rejection. No password/token/database error is returned to the caller or logged by this module.

Six Node boundary tests and the existing SQL issuer/readback composed through the handler in PGlite succeeded. The Native issuer job now checks the same composition. Authentication is a fixture in these HTTP tests: actual JWT-to-request-pool binding, deployed TLS/origin/abuse controls, owner approval, key activation, migration and recovery remain incomplete. No route, public SQL grant or production change is added. A caller-provided verification function is not itself proof of identity; this module must not be exposed until the trusted adapter and real boundary tests are complete.


The existing disposable GoTrue boundary runner now also routes real `/auth/v1/user`-verified JWTs through the request handler and a one-connection, transaction-local claims pool. It exercises wrong-password counter commit, password-verified issue, exact original challenge readback, duplicate issuance refusal, forged JWT rejection before pool acquisition, foreign-user/metadata impersonation refusal, and expired/deleted session refusal with no pool claim residue. This revision adds the real-stack CI test; its result must be confirmed separately. Master/device ownership and HTTP hosting remain fixtures, and no public endpoint, owner approval or key activation is provided.
