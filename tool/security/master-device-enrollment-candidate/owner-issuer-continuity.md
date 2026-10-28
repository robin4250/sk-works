# External issuer continuity guard — review only, OFF

The existing owner-decision verifier accepts one independently configured issuer
public key. Replacing that pin without authenticated continuity would either
lose historical signature verification or silently introduce a different signer.
The new pure verifier prepares one bounded transition from an existing trusted
pin/history to a successor public key. It is disabled unless explicitly enabled.

It requires an externally authenticated current authority checkpoint (authority,
epoch, prior transition digest, current key identifier and SHA256 of its SPKI DER
public-key bytes), matching the independently configured pin. A local key
substitution is rejected even when the local epoch and prior digest are unchanged.
The checkpoint must also carry `retiredKeysSha256`, the SHA256 of UTF-8 JSON
`["sko-master-owner-issuer-retired-keys-v1", authorityId, tuples]`, where `tuples`
is the epoch-ordered array of `[epoch, keyId, SHA256(SPKI DER)]` for every retired
key, including an empty array at epoch one. The guard validates bounded canonical
order and own-data objects before deriving that digest. Replacing retired local
history cannot hide a retired key while leaving the external checkpoint unchanged.
The exact authority, next epoch, prior digest, old/new identifiers, new public
key and short validity interval are signed by both the old issuer and new key.
Both Ed25519 signatures must verify. It refuses stale checkpoints, skipped/reused
epochs, retired key/id reuse, another authority, expired/future proposals,
private-key input, accessor properties, extra fields and noncanonical signatures.
Inputs are snapshotted; no private signing key is received or generated.

The result contains the successor pin, retained old verification keys and the
canonical signed transition bytes/signatures/digest. Retired keys are for
historical cryptographic audit only. They must not be selected to admit new owner
decisions; the existing ingestion verifier still requires the current issuer pin.
The guard is bounded to 64 transitions, after which further policy review is
required. This implementation is not connected to owner-decision ingestion,
device registration, configuration publication, a database, or any public route.

## Trust and remaining work

Dual signatures establish key continuity relative to an already trusted pin;
they do not establish independent human identity. The separate checkpoint is an
explicit required input, **not** an implementation of authenticated external
checkpoint retrieval/freshness. Two stale local copies can still satisfy this
input contract. Same-app admin evidence, user metadata, an app-generated key or
a local database copy must not be used as that external authority.

A real authority adapter must authenticate and obtain the latest monotonic
checkpoint independently, atomically compare-and-swap the expected old pin/head,
retain the signed transition and prior keys, reject concurrent forks, publish a
fresh independently authenticated checkpoint, and reconcile unknown outcomes
without blindly retrying a rotation. None of that durable authority/custody,
rollback/fork protection, deployment or configuration publication exists here.
This pure verifier cannot mutate trust, bootstrap a new issuer, approve a device
or activate a pending key. It does not solve a lost/compromised old signing key:
without its valid signature the transition is rejected, and a separately reviewed
independent recovery process remains necessary. No fallback trusts same-app proof.

## Validation

Local Node 24 tests: twelve new continuity cases and three existing owner-decision
cases passed. Coverage includes two consecutive transitions across serialized
pin state, old-key history, replay/retired-key reuse, authenticated-checkpoint
mismatch, both signatures, time bounds, malformed inputs, caller metadata mutation and original owner
evidence rejection under the new current pin. Serialization in a fixture is not
durable custody or a real independent authority test. The dedicated workflow
runs these scoped tests without repeating the unchanged PostgreSQL/Auth suites.
This head's CI result is separate from local verification.

An independent review reproduced a gap in the earlier checkpoint contract:
after a valid first rotation, replacing only the local retired key/id allowed the
actual epoch-one key to return with valid current+retired signatures while the
external current-key/epoch/head checkpoint stayed unchanged. The intact history
rejected it. The exact regression failed before adding `retiredKeysSha256` and
passes afterward. This strengthens checkpoint input binding; it does not add the
missing authenticated checkpoint retrieval, freshness or durable authority CAS.

Main, production configuration, live DB/grants, original devices/keys and
individual-document-exemption OFF state are unchanged.
