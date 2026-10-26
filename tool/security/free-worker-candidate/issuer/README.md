# Dedicated Master management issuer — OFF candidate

This is additive to the preserved read-proof/attendance/authentication core.
It never repurposes `master.security_collector.read`, incident-read proof, an
attendance entry token, local Face ID boolean, service key or user metadata as
permission to mutate a Worker policy. No existing function is replaced.

## Dedicated authority and immutable command

The new schema `security_management_issuer_private` is unexposed and RLS enabled.
All direct anon/authenticated/service table, sequence and helper privileges are
revoked. Root alone provisions a deployment with fixed company/owner, reviewed
manager public key/key ID/version and default **enabled=false**. Current live
Google/other primary authentication is preserved. The normal attendance
page-entry second-password behavior is untouched.

`prepare_decoy_management_proof(company, command, secondaryPassword)` requires
the existing live nonanonymous SID, allowed account, current enabled global
Master, current company owner/admin membership, exact configured deployment
owner, module flag and a registered secondary credential. The command has only
deployment/action/reason/expected policy and trust revisions. Owner/company/key,
nonce, timestamp and60-second expiry are server generated from trusted state.
Actions/reasons are the original management allowlists, excluding recovery.
The original Worker advances policy revision and epoch together and rechecks
both at commit; expected policy revision binds that epoch without inventing an
unsupported `epoch` field in its capability format.

The actual existing `verify_secondary_password` definition is called. **False
returns normally** as `{verified:false,...}` so its failed-attempt counter and
temporary lock commit. No exception follows false. Locked/missing credentials
do not create proofs. The pre-password binding reads the credential without a
SHARE lock, avoiding two invalid attempts deadlocking on a SHARE→UPDATE upgrade.
Successful proof generation occurs after a new locked binding check. The
token is32 cryptographic random bytes; only its SHA256 is persisted. Actor/SID,
company, dedicated operation, canonical payload bytes/hash, registry fingerprint
and credential fingerprint are fixed with an immutable command UUID/nonce.

`claim_decoy_management_command(proof)` rechecks all live bindings and atomically
consumes the proof into one durable command. A concurrent call gets `pending`;
it cannot select a payload or mint another capability. A10-second signing lease
can resume the **same** immutable command at most3 times before expiry. A
different actor/SID/company/config/credential/current Master/role or disabled
deployment cannot resume or retrieve a signed result. The ledger refuses core
field changes and deletion; signed receipts are immutable. Audit is append-only.

`complete_decoy_management_command` and `fail_decoy_management_command` are
service-only, with an actual service-role plus JWT-role guard. Completion
requires the exact command/lease/payload hash, current bindings and expiry.
It stores only one signature/receipt. A duplicate identical completion returns
the same receipt; different signatures/leases/hashes are rejected. Failure
records are restricted enums, not copied exceptions or secrets. An authorized
service cannot directly read the private proof table through grants.

## Signing resolver adapter

`createManagementIssuer` defaults OFF and contains no endpoint or credentials.
Its database port must bind `claim` to the caller's original authenticated JWT;
`complete/fail` are private server operations. The issuer **never accepts a
claim/payload from HTTP request data**. The trusted resolver gets only the
deployment/key ID/version returned by that verified claim. It must provide a
nonextractable Ed25519 sign-only CryptoKey matching the pinned public key.
The existing audit crypto functions and exact `management.mjs` canonical field
order/domain are reused; arbitrary JSON cannot be signed.

The signature is not returned before durable completion acknowledgement. A
failed key resolver/signing operation, lost completion ACK or malformed ACK
leaves the caller `pending`; retry uses the same proof/command/canonical bytes.
A committed receipt is verified/retrieved without signing again. Re-signing
after an abandoned lease can only yield the same deterministic Ed25519
authorization for the same nonce/payload; exact-once external key-operation
execution is not claimed. The Worker persistently consumes that nonce once.

Each core claim/key-resolution/sign/complete/fail operation has a hard deadline
(default3 seconds, server-configured maximum5 seconds). Cancellation is passed
to ports; ignored/late resolver results cannot reach signing. Late completion
acknowledgements remain pending and are recovered only through the same proof.

## Request-local PostgREST and handler adapters

`management-issuer-transport.mjs` adds an unconfigured request handler and
dedicated transport ports. No listener is installed and OFF performs no reads,
parsing, rate lookup, key resolution or RPC. An enabled handler requires an
explicit trusted HTTPS origin, public API key, server service-role JWT, signing
resolver and rate-limit port. No values are discovered from a request or env.

The request's exact original authenticated bearer is verified with Auth getUser
and reused only for prepare/claim. Its parsed UID/SID/expiry are merely binding
checks, not replacements for Auth verification or live database authorization.
The server bearer is used only for fixed complete/fail RPC routes at the same
pinned origin. Caller-provided payloads, service routes, keys or destinations
are never accepted. Redirects, wrong MIME, malformed/oversized bodies and
cross-origin requests are rejected. Body streams and transport/request/key
operations have bounded deadlines; a whole-request cancellation also prevents
late resolver results from advancing to signing. Responses never include
primary/secondary passwords, bearer tokens or server keys.

This proves adapter behavior using synthetic HTTP Responses. It is not proof
that a hosted endpoint, live caller/session, service JWT, public API key or
external key resolver is correctly provisioned. Independent server rate-limit
storage, secret delivery, exact hosted Auth/PostgREST behavior and real network
delivery still require deployment-specific evidence.

## Verification status

- Isolated PGlite40 cases use the captured **actual** password/session/Master
  helper definitions. The local cryptographic password function is explicitly a
  fixture stub: this proves SQL control flow/counter commit, not real bcrypt.
- Twenty-four Node/WebCrypto/transport tests pass, including actual-workerd acceptance of the
  envelope once by the unchanged management core and persistent nonce rejection,
  OFF/no I/O, malformed binding, key failures, lost/malformed ACK and retry,
  original caller/server credential separation, HTTP/body/rate boundaries,
  hard deadlines and late key/ACK/body results.
- Native PostgreSQL17 with real pgcrypto/bcrypt and two connections is supplied
  for CI: same-proof contention, concurrent false-password counters and live
  session-deletion lock/commit ordering. **Not locally executed.**
- Transport/helper tests are not a full hosted GoTrue→PostgREST→Edge→Worker
  end-to-end proof. No real JWT, secondary password, private key, company record
  or notification was read, created or sent.

## Deployment and remaining activation gates

The SQL is review-only with one transaction, fresh-schema checks,4 current core
body pins, no root configuration rows and no core replacements. It is not yet
the root's full production-catalog/business-digest guarded installer/unused
restoration artifact. It has no public configuration/onboarding endpoint.
The request-local PostgREST caller/service transport adapters are supplied but
not hosted or tested with a real GoTrue→PostgREST deployment. Hosted session/current
feature tests, managed database grants/metadata comparison, root key lifecycle
and independent recovery ceremony, per-deployment enablement, monitoring,
audit-history/retention/backup policy and iPhone confirmation remain explicit
activation prerequisites. No pruning of proof/command/audit history is added.
1000 prepared proofs per actor/day bounds preparation; operational retention
must preserve consumption/nonces and used financial/security provenance.

Master-control APIs must not be exposed until those prerequisites are verified.
This module does not make real honeypot/MTD deployment, actual alerts or Apple
account linking complete. Existing failed production connection attempts are
not retried or bypassed here.
