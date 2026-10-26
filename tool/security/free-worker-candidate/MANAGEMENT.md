# Companion management and signed-audit core — no live issuer or endpoint

This continues PR1440 without deploying it. Main/base and the successful first
11 runtime tests are retained; no auth/DB/app file outside this candidate is
changed. The public Worker still rejects all manager/operator routes. The
companion functions below must not be exposed until root connects an actual
Master/session-bound issuer and independent recovery/anchor trust.

## Implemented and exercised in actual workerd/SQLite

`initializeSecurity(storage,config)` accepts only configured public Ed25519
keys and fixed deployment/owner/company identities. Management, recovery, audit
and independent-anchor keys must differ. Configuration mismatches fail closed;
no key is discovered from requests, SKO credentials, the environment or the DB.
Private keys in tests are generated ephemeral fixture keys only. A real key
provisioning/recovery ceremony is still absent.

`applyManagedCommand(storage,{envelope,now,auditKey})` verifies a canonical
Ed25519-signed management capability under the pinned issuer public key. Exact
fields bind deployment, owner, company, action/reason, policy/trust revision,
nonce and a maximum five-minute validity. Other identities/scopes, future or
expired tokens, added fields, bad signatures, stale revisions and replay refuse.
The issuer must itself authenticate the current real Master and session. A
signature proves this issuer's statement; this module alone does not prove
GoTrue/Face ID/second-password authentication or revocation.

The existing policy transition statements are reused through an internal
transaction helper. Nonce consumption, the actual policy/epoch change, signed
audit insertion and management-key registry change commit in one SQLite
transaction. Async signature work happens before the transaction and the
policy/audit/trust snapshots are rechecked at commit. Actual concurrent commands
accept once; a failing signed-audit INSERT rolls back nonce and policy together.

False-positive release is a new signed command/revision/epoch with a reason,
not a historical rollback. Old public decoy capabilities remain invalid. This
does not change attendance's page-entry second-password behavior or prompt for
an attendance password per edit.

## Key loss and restart boundary

A separately pinned recovery public key can authorize only `recover_manager`.
The command binds the next manager public key/version, exact trust/policy
revision and owner/company. It records the recovery, advances trust revision
and policy epoch, and leaves admission **OFF**. It does not turn access back on,
reuse the old key ID or clear prior nonces/evidence. Old manager signatures are
rejected. The recovery private key must be separately held; this code does not
put it into the public Worker or fake possession of a real recovery factor.

Policy/trust/audit/nonce state is durable SQLite. Restart verification checks
the signed chain and an independently retained minimum anchor. A rollback below
that externally retained sequence/hash refuses. Passing an old/empty anchor is
not a substitute for retrieving the latest independently trusted one. Production
startup cannot be enabled until that provider is connected and tested. Same-DO
storage alone is not an independent anti-rollback authority.

## Signed audit and bounded retention

The new management/recovery/retention chain records canonical bytes, sequence,
previous hash, SHA-256 current hash, Ed25519 signature/key ID, owner/company,
reason and before/after revisions. It uses a dedicated audit key. Real Workers
verification detects altered bytes, broken sequence, missing records, head
mismatch and rollback below an independent anchor.

`acceptIndependentAnchor` verifies a separate anchor signature and advances only
to a locally matching sequence/hash, preserving its signed receipt. Anchor
private keys never belong in the public Worker. A host/account/root compromise
that controls both signer and independent authority remains outside this proof.
Signatures do not make logs absolutely tamper-proof.

`pruneAnchoredAudit` defaults to 30 days (accepted range 1–90 days). It removes
only the expired prefix already covered by an independently signed anchor. It
appends a signed retention record and keeps a separately signed prune marker in
the same transaction. Fresh/unanchored rows remain; key loss, anchor mismatch,
chain errors and capacity exhaustion refuse rather than silently deleting
evidence. The prune marker preserves chain verification after prefix removal.

This companion signs **management/recovery/retention** records only. The
original observation/outbox seven-field body and legacy control metadata have
not been silently relabeled as this signed chain. Observation retention,
independent anchor export/storage, actual alarm scheduling and real notification
delivery still require explicit integration. Current durable nonce/audit
capacities remain bounded and can require operator maintenance; no automatic
paid upgrade is added.

## Verification and unfinished integration

Eight new actual-workerd tests cover signed management, all identity/time/scope
denials without writes, CAS and real SQLite trigger failure, false-positive
release, audit tamper detection, restart/independent-anchor rollback refusal,
separate recovery-key rotation and anchored retention. All passed locally before
publishing the next dedicated CI head. Ephemeral fixture control/inspection
exists only in `tests/management-fixture.mjs`, never the production module graph.

Still required: real Master proof-to-capability issuer, production key lifecycle
and recovery authority, independent anchor provider/check at startup, actual
contact-chain integration and bounded retention, collector-v2 sender/alarm,
trusted-provenance incident/outbox notification and real iPhone confirmation.
No live authentication or notification is marked complete by these tests.

Primary API references checked 2026-10-26:
https://developers.cloudflare.com/workers/runtime-apis/web-crypto/
https://developers.cloudflare.com/durable-objects/api/sqlite-storage-api/
