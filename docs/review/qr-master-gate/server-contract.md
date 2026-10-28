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
restore SQL. The retained old reader is private to clients, but dependencies on
its original OID must be reviewed before deployment. Do not apply this candidate
or turn on the rollout based on CI alone.

The common bridge test executes copied existing getter/proof/legacy setter
bodies, with synthetic session/master/proof issuer fixtures. It tests default
OFF at both public setter and QR gate, non-master rejection without consuming
proof, audit rows, legacy QR rejection, OFF preservation, old flag values,
client ACL preservation and expired-session rejection. It does NOT prove real
GoTrue/proof issuance, production catalog compatibility, concurrent operations,
all QR writer gate coverage, key ownership or owner-device behavior. Those
remain activation blockers.
