# QR master internal contract candidate

Review only. No public getter/setter or client master toggle is replaced. No
production deployment, grant or enabled QR flow is included.

`master_feature_fragment()` returns the version-1 QR flag fragment after the
existing live-session check. Missing settings are OFF. A future reviewed common
getter can merge this fragment while preserving its other keys.

`set_master_feature_with_proof()` requires a live session, current master and the
existing action/target-bound proof consumer before updating the same
`private.master_feature_settings` row used by the QR gate. OFF keeps all device
and other feature data. It records actor/time on that existing row; this is not
a durable audit-history implementation. Both helpers remain private with no
client execute grant. This cannot bypass the current common key CHECK or proof
issuer whitelist: those still reject QR until separately extended and reviewed.

Before exposing the common API: verify actual function definitions and key CHECK,
extend the proof issuer/verifier whitelist consistently, connect all QR register /
issue / scan transactions to the gate, integrate existing audit history, test
concurrent OFF with in-flight operations, real GoTrue roles and owner devices,
and provide reviewed restore/rollback. Do not change the public contract or
advertise the QR toggle as usable before these are complete.

The SQL test uses synthetic auth/proof fixture functions. It verifies the real
candidate SQL's live-state call, exact proof target, default OFF, master refusal,
null / invalid / replay refusal, actor/time attribution, shared flag/gate behavior,
OFF preservation and private ACL. It is not a test of real proof cryptography,
GoTrue/JWT, production CHECK compatibility or client/device authorization.

## Common public bridge (review only, default OFF)

`qr-common-public-contract.sql.review-only` connects the existing common flag
reader and proof setter to the internal QR contract, while leaving the legacy
no-proof setter unable to change QR. It extends the existing CHECK expression
and the proof issuer's known allowlist; all other keys, proof validation and
issuer ACLs are preserved. QR changes append an existing master audit-history
row in the same transaction. A separate private rollout starts OFF and also
protects the QR gate; a true settings row alone cannot enable QR. The new reader
requires the existing live-session check, preserves old keys, and returns the
versioned shared QR flag. No device/attendance data is deleted by OFF.

The file refuses missing or mismatched independently reviewed hashes for all
modified function sources and the existing CHECK. The guard inputs in the
isolated test are derived from its fixtures and are NOT production catalog
approval. A production package still needs independently recorded current
catalog hashes, compatible schema/ACL/dependency review, a backup and explicit
restore SQL. The retained old reader is a client-private copy. The public reader is replaced
in place to preserve its OID, ACL and existing view dependencies; the test
checks an already-bound dependent view receives the QR contract. Other real
dependencies still require production review. Do not apply this candidate
or turn on the rollout based on CI alone.

The common bridge test executes copied existing getter/proof/legacy setter
bodies, with synthetic session/master/proof issuer fixtures. It tests default
OFF at both public setter and QR gate, non-master rejection without consuming
proof, audit rows, legacy QR rejection, OFF preservation, old flag values,
client ACL preservation and expired-session rejection. It does NOT prove real
GoTrue/proof issuance, production catalog compatibility, concurrent operations,
all QR writer gate coverage, key ownership or owner-device behavior. Those
remain activation blockers.

## Unused bridge restore candidate

The apply candidate now retains private original function definitions, owners,
ACLs and CHECK text, together with before/installed hashes. If the apply would
change a reviewed function's owner or ACL, it rolls back. The snapshot is RLS
protected and has no client privileges.

`qr-common-public-contract-unused-restore.sql.review-only` is only for a
never-enabled, unused bridge under an operator-controlled maintenance window.
It takes bounded locks and refuses any QR settings row, QR audit evidence,
enabled rollout, catalog/owner/ACL drift, missing or modified backup, or unknown
dependency. Independently reviewed original (`sko.review.qr_*`) and installed
(`sko.restore.qr_*`) hashes must be supplied; deriving them live is not approval.
It restores existing function OIDs/ACLs and the old CHECK in one transaction,
never CASCADEs and never deletes business/audit rows. The earlier private QR gate
and internal helpers remain; this restores the common bridge only.

After any use, do not remove QR settings/history to make this restore pass.
Keep data, turn the rollout OFF through a separately reviewed procedure and
prepare a forward recovery. Full after-use rollback, real catalog evidence,
concurrent maintenance, GoTrue and owner-device operation remain unverified.

The shared test runner checks unused restore plus refusal for an enabled rollout,
saved QR flag, audit evidence, function drift, altered original backup and an
unexpected dependency. CI runs real PostgreSQL with synthetic auth/proof;
local PGlite is not a substitute for native CI. Its hash inputs are fixture data,
not production approval evidence.


## Isolated real GoTrue common boundary

`qr-common-real-gotrue.mjs` starts a disposable loopback-only Supabase CLI stack
and verifies a real JWT with Auth /user before applying its claims transaction-
locally to the existing common public API candidate. It preserves real auth.uid,
auth.jwt, auth.users and auth.sessions. It exercises owner/default-OFF, owner
ON/OFF with audit, worker rejection, editable metadata not granting master,
tampered-token rejection before DB, restricted/expired/deleted sessions, anonymous
ACL and cleared transaction claims. It does not print credentials or private
responses and always stops its own stack.

Master ownership, access restrictions and operation proofs remain synthetic
fixtures. The session predicate is a harness mirror, not the entire deployed
reauthentication implementation or deletion-barrier protocol. This is not a
deployed JWT-to-database bridge, a real proof-issuance test, a test of all QR
writers, production catalog approval, recovery after use or owner-device proof.
CI success cannot enable QR. Local PGlite only checked expanded setup syntax
with synthetic auth tables; the real GoTrue job is separate.
