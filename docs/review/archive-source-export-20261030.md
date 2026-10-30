# Private source export prerequisite — review only, OFF

The readback server can authenticate an owner and restore registered bytes, but
an administrator-seeded descriptor is not evidence that those bytes belong to
that owner. The Collector event itself has no company/owner column. This change
therefore does not assign a caller-supplied company to an arbitrary event.

`lock_source_export(uuid,bigint,text)` uses the existing pinned notice contract
from unmerged PR #1494, source commit
`c6676bc7c7b425f7660523d0697c49fa1afd2559`,
`tool/security/observation-notice-candidate/install.sql.review-only`.
That prerequisite is absent from current main and is not installed by this file.
The candidate cannot be installed as a standalone production fix.

The private function requires the persisted notice config, original outbox
company/recipient/config revision, terminal inbox revision and complete retained
review revision chain to agree. It calls the existing live-session and management
deployment binding helpers. It locks those records, source event, original signed
evidence and its verification-key row until the producer transaction ends, then
uses the existing PostgreSQL source-evidence verifier. It exports the exact
accepted envelope, event, notice/outbox and bounded review history in one
PostgreSQL JSONB text snapshot with a SHA-256 digest. No HMAC key, password,
management key or credential fingerprint is returned.

The status is `source_locked_unattested`. The locks only survive while the
enclosing transaction is open. COMMIT ends the protected snapshot interval;
returned JSON is not a perpetual authorization lease. No public RPC, execution
grant, listener, producer credential, unpin or purge is added.

The separate private `register_locked_source` completion re-exports and compares
the source in the same producer transaction, computes the exact existing byte
store object binding from the actual encrypted payload bytes, and inserts one
immutable descriptor per authority/company/event/revision. An exact retry returns
the same descriptor; a different object/owner/deployment for that source revision
is rejected. It does not update an old original. Its status remains
`registered_unattested`: the SQL cannot establish that arbitrary opaque bytes
decrypt to the source snapshot. Only a trusted producer's actual decrypt/compare
of retained bytes can supply that prerequisite. The function has no API/runtime
EXECUTE grants and must not be exposed as a generic upload/registration RPC.

## Current evidence

The PGlite test exercises the real exporter SQL over a deliberately labelled
synthetic boundary fixture. It checks exact snapshot/hash, original-byte presence,
key omission, API-role denial, stale/foreign/revoked bindings, changed evidence,
missing review history, exact immutable registration/retry and source retention.
The fixture live-session, deployment
and HMAC verifier are stand-ins. It does not prove real GoTrue, cryptography,
the complete #1494 composition, Native PostgreSQL concurrency or production.
No successful prior runtime/auth suite was rerun.

The new Native job reuses the exact original #1494 harness and installation SQL,
both vendored with SHA-256 pins and original source commit above. The driver
adds a hook without removing any original assertion. The hook uses the real
Collector HMAC verification, canonical notice review writer and existing
management deployment binding body; its owner/session surroundings remain
synthetic. It performs actual AES-GCM encryption, full byte-store restore and
decrypt/compare, same-transaction registration, locked concurrent revision
denial, rollback preserving opaque bytes, immutable exact retry and revoked/
tampered-source denials. Keys and filesystem are local fixtures, not independent
KMS/WORM. Node syntax and the PGlite suite pass locally. Native results must be
read from the exact published commit's CI; they are not yet claimed here.

## Remaining connection, before any deployment request

1. Complete the new exact-head Native composition, then connect the same producer
   to the genuine GoTrue/runtime adapter; test publisher/reviewer/purge races and
   lock ordering beyond the bounded new hook.
2. Implement a trusted producer transaction using this export. Obtain an opaque
   encrypted payload through separately authorized key custody, independently
   decrypt and compare the complete canonical snapshot before registration, and
   retain/read back those exact encrypted bytes. Neither a descriptor supplied by
   the caller nor a `committed` boolean is sufficient.
3. The private registration SQL supplies the mechanical binding/recheck, but the
   authenticated producer, pinned authority configuration and genuine encrypted
   payload provenance must be connected before granting any runtime capability.
   Do not expose a generic client/service-role INSERT or reassign an old object.
4. Capture fresh complete definitions/catalog/ACLs and pin the combined notice,
   source-export and registry dependency contract. Add guarded source-only
   recovery with writers stopped; no source/original/registry deletion or undo of
   a committed registration. A lost COMMIT response requires read-only lookup.
5. Supply genuinely independent custody/checkpoint/key recovery, WORM/retention
   policy and operational restore proof. Those require real provisioning, not
   additional same-host fixtures. Keep release/unpin/purge unavailable.

All production installation, runtime provisioning, activation and iPhone security
claims remain HOLD. This is a reviewable source-connection step, not completion
of the archive or permission to deploy it.
