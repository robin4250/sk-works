# Independent notice archive — isolated proof of concept

## Disposable real GoTrue / Native PostgreSQL server proof (2026-10-29)

`tests/archive-readback-server-real-auth.mjs` is a dedicated CI harness using a
fresh CLI-owned Supabase stack, real GoTrue-issued JWTs and actual auth tables,
Native PostgreSQL 17, the unchanged server/client, and the same existing guard
and private registry SQL. It refuses hosted Supabase environment credentials,
checks an empty owned stack and fixed loopback API/DB endpoints, and removes
only that generated stack. Tokens, service credentials and TLS/private keys are
kept inside temporary fixture state and omitted from output. No success Auth
response is mocked: the fixed test-origin bridge forwards the exact bearer to
the real disposable `/auth/v1/user` endpoint and returns its actual response.
That HTTP loopback bridge is a fixture, not production hosted TLS verification.

The new job targets forged-token rejection before pool acquisition, own/foreign/
unregistered objects, real user_metadata lacking Master authority, and true
independent-connection role/session revocations blocked by the server's shared
row locks until its read transaction completes. It checks actual backend PID
exit after client disconnect, transaction-local claim cleanup, a deliberately
discarded response after read commit, and cancelled queued pool acquisition
whose late lease is destroyed before BEGIN. An actual `pg_sleep` diagnostic
under the server's existing statement bound tests pending-query termination.
It does not equate `release(true)` with synchronous server cancellation: native
backend exit is observed separately and may depend on the statement timeout.
Unexpected idle-pool errors fail the job without printing private error detail.

This closes only the actual execution gap when the **new head's CI result is
verified**. Local syntax validation alone is not a GoTrue/Native pass. Registry
records, company/Master association and credentials are synthetic administrator
fixture seeds, not authenticated source-owner enrollment. Production least-
privilege pool/certificate/catalog compatibility, trusted registry population,
Native operational policies, independent custody/WORM/retention and activation
remain incomplete. Original byte objects and the immutable registry are retained;
no source references are released or real notification/data/deployment changed.

## OFF readback server and required descriptor registry (2026-10-29)

`archive-readback-server-candidate.mjs` composes the existing exact-bearer
`createManagementTransport.authenticate()` with the existing live-session and
`security_management_issuer_private.binding` guards. The bounded TLS server
accepts only its fixed host/path and exact request fields. Actor/SID come from
the verified Auth result; body actor, pool, role and user_metadata are never
authority. In one transaction it installs only verified minimal claims and
share-locks an exact saved descriptor/authority/company/owner/deployment record
before any byte restore or signing. It requires the saved owner to match the
verified actor and uses the **saved** company/deployment for both authorization
checks. Existing user/session/account-deletion/Master/company owner-or-admin/
deployment/secondary-credential checks and their shared locks are retained.
After real byte restore/signing it rechecks those guards, JWT expiry and the
monotonic request deadline, commits, then emits the unchanged observation receipt.
It does not grant raw collector-log access or bypass that endpoint's proof flow.

`archive-readback-registry.sql.review-only` is a narrow missing prerequisite:
private RLS-enabled exact records, no client grants, no seed/registration API,
and update/delete/truncate rejection. **Authenticated source-owner population
is absent. An empty or missing registry blocks every read.** The new table is
not proof that the source association is authentic or independently retained.
No production migration is supplied or applied, and no source original is moved,
rewritten or released. Future registry registration/transfer/retention/restore
must be independently reviewed rather than inferred from caller descriptors.

Ten new scoped tests use actual loopback TLS/client/server, PGlite and the exact
existing guard SQL. Auth /user is an independently MAC-checking fixture, not real
GoTrue. Tests cover own success, foreign/changed/unregistered actual byte objects,
forged JWT/metadata/body authority, actual guard denial states, immutable/private
registry, transaction-local claim cleanup, expiry recheck, and timer-starved valid
signer/late-pool callbacks. The timer-only mutant demonstrably accepts a valid
late signature; the absolute monotonic check rejects it before final SQL/commit.
The pool-overrun case rejects and discards the owned lease before BEGIN.

The factory never binds a host automatically. It remains OFF/unhosted, with no
production grant/key/credential or feature change. Least-privilege production
pool/managed catalog compatibility, authentic registry population, real GoTrue,
Native PostgreSQL concurrent locking/termination, caller rate policy and real
authority operation are unverified. PGlite's single-connection expiry mutation
tests final revalidation, not concurrent lock behavior. Deadline/disconnect
discards only an owned pg lease via release(true); this is not proof of synchronous
backend cancellation or external signer cancellation. Late callback results are
refused. Connection/header limits do not constitute complete pre-header TLS or
ingress DoS protection. Results remain `archive_bytes_observed` and
`readback_verified_unattested`, never custody/WORM/retention or source-release proof.

## Authenticated HTTPS readback client (2026-10-29, OFF)

`archive-readback-https-candidate.mjs` connects the existing fresh-challenge
receipt verifier to native Node HTTPS IO. Endpoint, authority, public receipt
key, bearer and optional public CA certificate are trusted construction-time
configuration, copied before asynchronous work. A read call cannot supply a
URL, key, headers, shared agent or TLS override. It makes one POST to that exact
configured endpoint, verifies the certificate/hostname with TLS 1.3 minimum,
never follows Location/redirects, and then uses the existing canonical receipt
verifier to bind the signed response to the captured expected byte descriptor.
The result remains `readback_verified_unattested` / `archive_bytes_observed`.

Request JSON is capped at 2 KiB, response bytes at 4 KiB and response headers at
8 KiB. Wrong content type, compression, duplicate sensitive headers, absent
no-store policy, malformed/truncated JSON and non-200 status fail closed.
The total deadline includes connection/response IO; caller AbortSignal and
either transport/verifier timeout destroy only the request owned by that
operation. There is no retry or shared-agent destruction. A bounded local
admission count rejects excess calls before creating a socket. Errors omit
credentials, response content, configured URL and external failure details.

Ten new tests use actual loopback HTTPS sockets and temporary certificates,
the real byte store and existing Ed25519 observation attestor. They cover CA/
hostname/TLS-version rejection, exact POST/authentication, redirect bearer
non-forwarding, header/declared/stream byte limits, response schema/metadata,
fresh-challenge cached-receipt refusal, mutable configuration/input, independent
request cancellation/admission, deadline and generic authentication failures.
The size tests pause JS deadlines so a missing size cap cannot pass by merely
waiting for timeout. The deadline test advances its JS timer only after the
real TLS server confirms the stalled-body stage, rather than assuming a fast
handshake. Socket close and surviving concurrent operation are checked directly.
These 10 tests plus existing receipt/byte tests pass 32 cases locally; the
dedicated CI result must be checked independently.

This is an outbound client candidate, **not a deployed authority, independent
custody, WORM, retention guarantee or protected checkpoint**. The test host,
bearer, receipt keys and CA are synthetic and same-host. Real endpoint/certificate
and bearer provisioning/rotation, company/caller authorization, trusted signer
and byte-store ownership, operator-independent checkpoints/backups, health/
access-log policy and actual disaster recovery remain unresolved. Local abort
does not prove remote signing was cancelled or that an OS DNS resolver stopped.
No real host, credential, production data or notification was used. No source
pin is released, original deleted, capacity recovered, or feature enabled.

## Signed full-byte readback observation (2026-10-28, OFF)

`archive-readback-receipt-candidate.mjs` connects the byte store's actual restore
to a narrow external-signature boundary. The attestor accepts only the exact
configured authority, a challenge and a snapshotted expected byte descriptor.
It restores and independently rechecks both the full opaque payload hash and
the content-addressed object binding before asking a server-configured signer
callback to sign domain-separated canonical observation bytes. The public key
is pinned in trusted construction-time configuration; request/response keys do
not establish trust and private keys are rejected. Returned signatures and
30-second observation times are verified before any receipt is returned.

The verifier generates a fresh cryptographic challenge for each explicit call,
binds the reply to its exact authority/company/event/revision/snapshot/object/
payload hashes and byte length, and rejects cached replies, changed bindings,
wrong keys/domains, accessors and stale/future observations. Metadata and keys
are copied before asynchronous callbacks. It returns only
`readback_verified_unattested`; the signed statement is `archive_bytes_observed`,
not a retention guarantee, independent custody, source authenticity or release
permit. There is no `passed`, retention expiry guarantee, delete or unpin action.

Twelve new tests use real temporary-file restore and Ed25519 signatures, and
exercise byte loss/corruption, adversarial callback/input/signature mutation,
deadline/unknown signing outcomes, fresh-challenge replay rejection and rollback.
The rollback test retains a newer expected descriptor outside the store and
detects its missing bytes, but also deliberately shows that rollback of both
the store and expected descriptor can still obtain a freshly signed observation
of older bytes. No independent rollback-resistant checkpoint is established.

This remains an unhosted default-OFF boundary with trusted callbacks, **not an
authenticated remote service or independent signer/KMS deployment**. The attestor
does not durably consume a challenge: repeated read-only observation of the
same challenge is possible and explicitly tested. The verifier never reuses a
prior challenge or automatically retries after an unknown result; a subsequent
explicit verification generates a new challenge. Timeout rejects late results
and prevents a late restore from starting signing, but cannot abort a signer or
transport already executing. Pending callback resources, admission/rate limits,
real transport authentication, private-key custody, protected expected-descriptor
checkpoints and operational retention/restore policy still need implementation.
Neither successful signature validation nor a new fresh observation authorizes
source reference release, purge, capacity recovery or production enablement.

## Review-only full-byte retention candidate (2026-10-28)

`src/archive-byte-store-candidate.mjs` adds a default-OFF Node filesystem adapter
for retaining an opaque encrypted export's full bytes rather than only its
digest. It snapshots exact company/event/revision/snapshot-hash/payload-hash
bindings and bytes before IO, bounds each payload to 64 KiB, writes a private
temporary file, fsyncs it, and publishes a content-addressed name with a
create-only hard link. It verifies the entire stored object before directory
fsync and returns only `stored_unattested`. An existing object is never replaced;
a corrupt/symlink/conflicting object fails closed. New revisions have distinct
objects, leaving older originals untouched. Restore checks exact canonical
metadata and all bytes against the caller's expected descriptor. No delete or
source-pin-release method exists. Only each call's own temporary file is cleaned
up; an uncertain post-publication sync leaves the published object intact.

Ten real temporary-filesystem tests cover default OFF, full encrypted fixture
source restore/HMAC reverification after reopening, twelve concurrent replays,
version preservation, asynchronous input mutation, missing/corrupt/oversized
objects, symlinks, partial writes/publication failure and lost directory-sync
reconciliation. Together with the existing source fixture, 14 Node tests pass
locally on Node 24.22.1. The dedicated archive CI's existing test glob discovers
the new tests; its result is separate and must be checked before claiming success.

This is **not independent custody, WORM retention, a production source exporter,
or an authenticated signed storage receipt**. Expected bindings and the encrypted
export must come from the future authenticated source-lock/export path. The
directory and IO adapter are trusted private configuration and must remain
protected from path replacement and operator mutation; the implementation cannot
prevent an operator from changing or rolling back the filesystem. Per-object
size is bounded, but aggregate quota/retention, orphan cleanup after a process
crash, independent protected checkpoints/backups, actual power-loss/hardware
durability, key recovery, ACL/service hosting and atomic source release remain
unimplemented. Tests use same-host temporary files and synthetic keys only.
Nothing is connected to the current manifest, real notification, production
database or deployment. `stored_unattested` must never authorize unpin, purge,
capacity recovery, key activation or production enablement.

References: Node [filehandle.sync](https://nodejs.org/docs/latest-v24.x/api/fs.html#filehandlesync)
and [fsPromises.link](https://nodejs.org/docs/latest-v24.x/api/fs.html#fspromiseslinkexistingpath-newpath).

This code is not connected to an endpoint, a production database, a real notification, or any deployment. It does not delete or unpin source records, does not reclaim outbox capacity, and is not authorization to enable PR #1494. There is no completed production evidence archive or capacity recovery.

The SQLite adapter accepts bounded terminal-status manifests linked to an existing signed audit record and an independent-anchor receipt. It validates the chain, prevents changed retries, stores each batch transactionally, and refuses to read after detected loss or modification. The synthetic test runs the real existing Worker audit verifier and independent anchor authority in workerd; all keys and records are fixtures.

The input `latestIndependentAnchor` MUST come from a separately authenticated, fresh independent authority. A caller-supplied old but correctly signed receipt is not proof of freshness. That trusted connection is absent. The manifest's original-evidence digest is a signer assertion: this candidate does not export or verify source HMAC records, retain their original bodies or verification keys, or establish that they match a real database. A digest alone is not an independently reproducible source record. Review reasons are free text and may contain sensitive information; strict access and a safe data handling policy are required.

The isolated authority enforces contiguous signed audit history when publishing, but the archive adapter itself does not verify the intervening audit ancestry between archived batches. A fixture with a validly signed, higher-numbered fork demonstrates that the authority rejects it while the archive accepts it if an inconsistent anchor receipt is supplied. This does not imply the authority issues such a receipt. Deploying the archive requires authenticated, fresh authority state and evidence of continuity from a separately retained checkpoint, along with independently durable witness and key custody; neither is provided here.

The review-only `storeNoticeArchiveWithContinuity` entry point additionally validates a bounded suffix of existing signed audit rows from the archive's previous checkpoint to the new head. Synthetic workerd tests cover a fork, missing or reordered rows, altered content, multi-row history, retry and concurrent writes. Validated suffix rows are stored atomically with the batch and survive fixture restart, and a separate review-only strict read verifies every retained row and rejects missing or altered history; neither the rows nor checkpoints are independently held evidence, and the pre-existing `storeNoticeArchive` entry point remains available for fixture compatibility without this check. Neither entry point is exposed in production. A real migration would need to prevent use of the old entry point, establish how complete signed rows are retained and fetched across pruning, authenticate a fresh authority head, prove the persisted checkpoint independently, and test key rotation and recovery.

Production prerequisites include: independently authenticated fresh-head retrieval; a trusted, version-bound source exporter and verification of original evidence and terminal review; real separate custody, backup, key rotation/recovery and restore tests; approved retention and access policies; deletion and reconciliation rules; race-safe transactional source unpin, deletion and capacity recovery after durable verification; retry/backfill and failure alerting; and performance/quota tests. Seven days here is only the minimum against the existing source retention contract, not an approved archive expiry. Nothing is automatically expired. This candidate limits archive batches and rejects writes when full; its full-history verification cost has not been tested at maximum capacity. Keep OFF until all prerequisites are met.

## Synthetic original-evidence experiment

`source-evidence-fixture.mjs` is a Node-only cryptographic experiment, not a production source exporter. It validates the Collector v2 HMAC against fixture metadata, encrypts the original signed envelope with an independent AES-GCM fixture key, and verifies after decrypting with the separate source key. This demonstrates that a digest-only manifest is insufficient and that the source key is still required for later HMAC verification. It is not connected to the archive adapter or independent anchor; there is no database lock, real exporter, durable custody, key isolation, rotation, secure deletion, nonce-volume policy, ACL, or production restore process. The JavaScript JSON parser does not provide the source PostgreSQL ingress duplicate-key / jsonb verification; the real source verifier remains mandatory. Do not use it to unpin, purge, or handle real evidence.

Capacity recovery must also change the notice read path: PR #1494 verifies every inbox row against the source evidence, so purging even a resolved row after unpinning would cause its read to fail. A verified immutable archive record, its review/audit history and command-id replay semantics must remain readable before the source can be safely released. Concurrent review, collection, export, purge, retries and restore need native transaction/race tests; loss-counter backfill must also be designed before claiming coverage is restored.

## Synthetic retirement model

The Node-only evidence fixture additionally exercises key rotation: decrypt
the old ciphertext, verify its original HMAC and expected metadata, encrypt
with a distinct new key, and independently decrypt and verify the replacement.
The old copy remains unchanged. This is not an atomic storage update or a
key-management service; production rotation needs separately held keys,
durable version history, authorization, backup, recovery and deletion rules.

`retirement-model-fixture.mjs` is an in-memory state machine used only to test the desired semantics: terminal review and elapsed retention, matching full snapshot including original evidence and command audit, atomic slot release with history and a retry tombstone, isolated owner/company reads, and exact command replay. It does not use real independent storage, authentication, encryption, network, or SQL, and its `fixture_only` marker is not a trust proof. It must never be deployed. No source or SQL row is deleted and no capacity is recovered by this experiment. Persisted tombstone retention and bounded growth, complete SQL lock ordering and crash/restart/reconciliation, trusted signed receipts and original evidence custody are still to be implemented. Existing PR #1494 also retains queue/publication audit entries separately; the model represents only action history and must not be treated as a complete export schema.

## Durable SQLite transaction experiment

`tests/retirement-sqlite-fixture.mjs` is a test-only simulated ledger. It exercises actual workerd SQLite transactions and durable-object restart persistence using synthetic strings. It demonstrates atomic history insertion, retry tombstone creation, and release of a simulated slot; injected SQL failure rolls back all three, and stale snapshots are rejected. Both simulated source and history are in the same fixture database, so this is **not independent custody**, source verification, authentication, an archived signed receipt, production Postgres locking, or authority to delete real records. It intentionally has no production entry point. The complete external archive/source MAC/anchor trust and end-to-end capacity recovery still require implementation and validation.

The synthetic integration test now connects the fixture Collector v2 HMAC check and encrypted original to the existing signed-audit and independent-anchor implementations and the durable SQLite manifest. It restarts workerd, decrypts a separately written temporary fixture file, rechecks the HMAC, and compares the event, occurrence time and raw-body digest with the signed manifest. The independent authority and file are still test fixtures on one machine; source database jsonb verification, fresh authenticated production witness retrieval, real key custody and archive availability, rollback protection for the encrypted copy, and atomic source release are absent. This is not an end-to-end production security or recovery claim.

## Capacity gap and binding counterexample

The existing #1494 full-outbox branch records a count but no affected event's original recipient or config revision. Two different original owners can therefore produce the same persisted state after configuration changes; a source-only backfill cannot safely infer whom to notify. Because the gap event has no outbox pin, the current seven-day purge can remove it while the counter remains. `tests/gap-ambiguity.test.mjs` demonstrates both cases with a model; it does not exercise production SQL.

`tests/gap-holdback-fixture.mjs` explores a possible alternative with synthetic workerd SQLite only: associate each accepted source with its original recipient and config revision in the same transaction; hold it while capacity is full; refuse purge during hold; backfill only if the original binding still passes the fixture's current-binding check; reject when the separately bounded source fills. The hardcoded fixture capacities are test values, not production policy. A changed binding remains held, not transferred. This is not a migration or deployable code. It lacks real source HMAC/auth checks, Postgres locks and guards, real archive verification and lifecycle, retained duplicate tombstones after source purge, actual upstream retry and operator alerts. The existing sender has a bounded retry policy, so refusal under sustained overload can still lose coverage: a persistent upstream recovery/alert mechanism is required. No gap counter is treated as proof of complete coverage, and this experiment does not authorize unpin or source purge.

## Synthetic independent-head key continuity experiment

`head-trust-fixture.mjs` is Node-only experimental code, not a production authority or endpoint. Synthetic tests bind a fresh nonce, deployment scope, sequence, hash and key epoch to a signed head. Planned key replacement requires signatures by both the old and new synthetic keys over the same previous checkpoint; stale epochs, altered replacement keys, replayed challenges and rollback are rejected. This is planned key rotation, **not lost-key recovery**: an old-key compromise can authorize a replacement and a missing old key cannot produce its signature. An independently authenticated witness, independently durable state, protected keys, recovery after loss or compromise, complete signed audit continuity and the actual authority/transport connection remain unimplemented. Do not use this experiment to enable or recover production.

The isolated test binds a proposed rotation to the actual existing synthetic independent authority's signed latest receipt and verifies both signatures without altering that authority. The production-shaped authority currently validates its saved latest receipt using only its current pinned anchor key, and retains receipts by sequence: replacing its key without a key-history transition would make old/current receipt verification fail. Its initialization also pins the original key. Therefore this experiment performs no switch, and an authenticated, independently witnessed, durable and atomic key-history migration with verification of historical signatures is still required; the old and new keys or historical receipts must not be overwritten or discarded. Lost-key recovery remains unimplemented.

`anchor-rotation-fixture.mjs` adds a review-only planned rotation against the existing authority fixture: both keys sign the transition and previous receipt; one local SQLite transaction retains that transition and prior receipt, installs a re-signed current receipt, and changes the pinned key. Fixture tests exercise authority restart, subsequent publication with the new key, retained-history tampering, and rollback on an injected failure. This is not a production migration: no owner authorization, independent witness, independently durable transition store, backwards compatibility of outside copies, concurrent publish/race proof, recovery from lost or compromised keys, or deployment exists. The candidate re-signs the current anchor receipt, so external verifiers and consumers holding previous receipt/keys have not been migrated; do not enable this path.
The fixture also checks that two simultaneous replacement requests result in one successor and one retained transition; this does not prove concurrent publication and rotation on a deployed service.

The fixture includes an archival verifier that checks exact retained historical receipts against the transition chain and their original signing keys after rotation and restart, rejecting a newly forged receipt signed with a retired synthetic key. It does not make existing archive/client readers rotation-aware, provide freshness, or establish independent custody; new or old receipt bytes must not be treated as current merely because their signature is valid.

A test-only archive-client bridge checks the retained historical receipt against the authority key transition history, reads the strict archive, and confirms the authority head before and after. It demonstrates old receipt readability after rotation and deliberately holds when the authority head has moved. Both actors are synthetic durable objects on one machine; caller-supplied trust, authenticated transport, independent witness, source custody, rotation-aware production clients and atomicity across network boundaries are absent. A before/after check does not prove that a remote authority cannot change or roll back immediately after the check.

`recovery-proposal-fixture.mjs` explores a fail-closed **proposal only**, not key recovery or activation. The isolated authority fixture pre-pins two distinct synthetic recovery/witness public keys; proposal staging checks both signatures, the proposed key's proof of possession, authority scope/checkpoint, a short expiry, and one-use nonce, then stores the proposal in local SQLite while leaving the original authority unchanged. The test exercises unauthorized signatures, expiry, wrong company, concurrent nonce reuse, restart and original receipt preservation. It has no real owner authentication, independently durable witness or recovery signing service, trusted clock, compromise/loss recovery, authority key-history migration, human review, key rotation coordination, independent custody or production route. It must not be used for real keys or deployed, and staged does not mean recoverable.

The test also demonstrates a rollback counterexample: restoring an old local proposal ledger removes the nonce, so the same still-valid signed proposal is accepted again. This simulated deletion is only a test hook and does not touch source records or keys. Restart persistence and uniqueness inside SQLite therefore do not establish replay protection across rollback. Before any production design, use an independently authenticated and rollback-resistant consumed-nonce ledger and reconcile it during restore; if that ledger is unavailable or behind, fail closed. Those controls are not implemented here.

`recovery-witness-model.mjs` is a synthetic in-memory exploration of an independently signed nonce-consumption receipt. A verifier checks scope, proposal hash, nonce, fresh challenge, time, sequence and pinned witness key. Its tests simulate restoring local state and show the separate test ledger still refuses the nonce, and that an uncertain response must not trigger a new recovery. This model does not persist the witness, implement a production transport, reconcile unknown outcomes, establish trusted time, or prove independence. Restoring both stores, dishonest witness signing, local verifier challenge reuse and key compromise remain unsolved. No actual recovery, activation or production access is implemented.

`tests/recovery-witness-sqlite-fixture.mjs` is a separate temporary SQLite file backed by synthetic keys. A test demonstrates rollback before a commit, restart after a committed response is lost, denial of re-consumption, and fresh-challenge lookup bound to the same scope/nonce/proposal. This is only a local fixture on one host; an operator who can roll back or rewrite the witness database can still defeat it. It has no authenticated network transport, verified real clock, separately controlled key custody, independent immutable backup, concurrency/load proof, availability policy, or production deployment. It is not wired into proposal staging or key recovery and cannot authorize recovery.

`tests/recovery-witness-anchor-fixture.mjs` separately models an atomic compare-and-set against a hash-chain checkpoint retained by the caller, using a local SQLite witness file. Restoring the witness to an earlier file or advancing a different fork to the same sequence is rejected if the true checkpoint remains independently available. The test deliberately demonstrates that an actor supplying an old checkpoint can advance a fork: protecting and authenticating the checkpoint is a prerequisite, not a property of this fixture. It is not wired to the signed receipt fixture, staging, a real independently durable checkpoint, or actual authority recovery; dishonest witness responses, lost-response reconciliation, clock trust, two-store rollback and key compromise remain unresolved.


The local fixture now verifies its entire retained nonce chain and its local head within the same transaction before consuming a new nonce. Synthetic tests delete or alter historical rows or the local head and confirm the next operation fails closed. This detects partial loss and modification, but cannot detect a coordinated rollback of both ledger and trusted checkpoint, authenticate a checkpoint, prove independent custody, or provide durable production recovery. The full-history scan is unbounded and its performance has not been established; this remains a test-only experiment, not deployable code.

The signed recovery checkpoint transition validator is stateless: a new regression test shows that two callers given the same valid receipt and stale checkpoint both pass verification. Signature validation alone neither consumes the nonce nor commits a new trusted checkpoint. Any actual integration must atomically compare and advance an independently protected checkpoint and consume the nonce, fail closed when freshness cannot be authenticated, and test retries/crashes across the independent boundary. This synthetic test does not implement those controls or authorize recovery.

The synthetic anchored witness now caps its ledger at 10,000 records and rejects further consumption without changing its checkpoint, and bounds scope to 256 UTF-8 bytes. A 10,000-row local test checks fail-closed capacity; the limit is an experiment, not a production retention, performance, alerting, availability or recovery policy. No data is pruned or exported. Independent authenticated checkpoints, rollback-resistant custody and safe lifecycle handling remain unimplemented.


## Review-only witness transport

`src/recovery-witness-transport-candidate.mjs` implements a bounded HTTPS POST client for signed witness consume/lookup responses. Each call creates a fresh challenge, authenticates with an externally provisioned bearer, forbids redirects, limits response bytes, enforces a timeout, validates the pinned signature and scope, and never automatically retries an uncertain consume. Lookup is a separate explicit operation. Errors deliberately omit credentials and response content.

Tests use a synthetic fetch adapter only; no actual service was contacted. This is not an authenticated production witness deployment: endpoint/bearer/key provisioning, independent custody, rollback-resistant checkpoints, durable outcome reconciliation and recovery activation remain absent. Keep the feature OFF.

## Review-only witness HTTP boundary

`src/recovery-witness-http-candidate.mjs` is an unhosted request handler candidate
for the existing signed-receipt client. It accepts only the configured HTTPS
endpoint and POST, checks the fixed bearer before reading a body, allows only
configured scopes and exact bounded JSON fields, and invokes consume or lookup
once. It enforces body/authority deadlines, verifies the returned signed receipt,
and returns generic no-store failures without credentials or authority details.
A timeout does not establish whether a consuming operation committed; use a
separate lookup and never treat a repeated consume as reconciliation.

The existing client is exercised through this handler and the synthetic SQLite
witness fixture, including a lost committed response and later lookup. These are
same-host synthetic integration tests, not real TLS, independent custody, a
production signing service, or a deployment. The authority's atomic persistence,
separately held key and rollback-resistant checkpoint remain trusted prerequisites.
Credential/key provisioning, rotation, access logs, rate limits, independent
hosting, availability/recovery policy and activation are still unimplemented.
The HTTP handler alone creates no listener, public route, credential, network
call or recovery action. Keep the feature OFF.


## Review-only Node TLS listener

`src/recovery-witness-https-candidate.mjs` connects that same handler to a Node
HTTPS server factory. It does not bind a port by itself. The caller supplies the
TLS key/certificate through protected configuration; the module does not read
server files or print credentials. It requires TLS 1.3, exact configured Host and
path, rejects duplicate sensitive headers, bounds headers and bodies, limits
concurrent requests, closes each connection and enforces a total request deadline.
A consuming authority call is still made at most once and a timeout remains an
unknown outcome requiring a separate explicit lookup.

Four real loopback-TLS tests generate a temporary self-signed certificate and
synthetic signing key, trust that certificate explicitly, and use the existing
SQLite witness fixture. They verify certificate/TLS-version rejection, host/path/
authentication/body limits, admission before authority work, signed consume plus
fresh lookup, and deadline failure without retry. Only the socket address is
bridged to an ephemeral loopback port; configured origin and certificate name
remain `witness.local`. Test TLS keys and ledger files are removed and never
committed. Existing handler/client tests plus these tests pass 16 cases locally.
The existing isolated archive CI picks up the new test via its Node 24 test glob.

This is a listener candidate and same-host TLS test, **not an independent witness
or deployed service**. TLS does not prove authority key custody, rollback-resistant
checkpoint storage, a trusted clock or disaster recovery. Per-client rate limits,
access-log privacy/retention, real certificates and rotation, independent hosting,
operational health checks, key-loss recovery and production activation remain
unimplemented. No production listener was started and no external host was contacted.

## External signer boundary candidate

`src/recovery-witness-external-signer-candidate.mjs` accepts a pinned public key and a server-configured external signer callback, never a private key. It validates and snapshots an exact committed nonce record before requesting a signature over canonical receipt bytes, then independently checks the returned signature and time. Store/signing errors have a bounded wait and no automatic consume retry. Lookup is a separate explicit reconciliation operation.

The tests keep a synthetic signing key outside the store adapter, prove lost-signature-response reconciliation, reject substituted/uncommitted rows and wrong signatures, and reopen a temporary SQLite ledger after a signer failure without consuming twice. Input, row, public-key and signing-buffer mutation tests prevent asynchronous rebinding. The existing Node24 workflow discovers these tests without workflow changes.

This is **not a KMS/HSM integration or independent key custody**. The store callbacks are trusted configuration; a `committed` field is not cryptographic durability proof. The local SQLite fixture can be rolled back by its operator. Real authenticated signer transport, separate operator/key authorization, independent rollback-resistant checkpoint/backup, protected server clock, real restore/loss/compromise policy and actual deployment remain unimplemented. Do not enable production or recovery using this boundary.


## External signer record binding hardening (2026-10-28)

The review-only external signer boundary now snapshots exact own data fields of
caller input and committed store rows, rejecting accessors, inherited bindings
and unknown fields without invoking their getters. Store callbacks are bound at
configuration time, so replacing a public method property later cannot redirect
an in-flight configuration to another store. The prior implementation reproduced
both new regression failures; the fixed external-signer tests pass (7 cases).
This does not turn an untrusted store or signer into an authority: a Proxy can
execute descriptor traps, callback execution is not sandboxed, and the configured
store/issuer still require independent authentication and rollback-resistant
custody. Real KMS, production host, retention/recovery and activation remain
unimplemented. No production operation, real key or external notification ran.
