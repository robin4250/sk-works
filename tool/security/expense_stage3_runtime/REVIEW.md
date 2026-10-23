# Stage3 owner orchestration review candidate

`owner_stage3.py` is an import-safe/CLI-refusing operator component. Only an
independently pinned Mac bootstrap may call `run`. No endpoint/password is accepted
and no login, connection, SQL, Docker or external fetch occurs on import.

Required bootstrap arguments are fixed durable root/package and full execution-file
hashes, plus private binding/approval/backup paths and their independent exact-byte
SHA256 hashes. Private files remain outside Git. The binding authorization reference
must equal the approval bytes' SHA256. The approval binds source/target/claim/choice/
owner/catalog/financial/backup/restore/build7 proofs and does not include the binding
hash, avoiding a circular reference.

Before importing the previous transport, the owner verifies all fourteen old runtime
pins, stage1 approval `4a79...`, both stage2 runtime sources, stage2 acknowledged
successful marker, and actual stage2 undo bytes `07a220...`. The generated Python
transport binding is compared to the exact original bootstrap literal bytes before
import. Already-imported old operator modules are refused. Package sources are
checked before transport and again immediately before SQL generation/submission.

The unchanged native `_approved_binding` and `_operator_transport` obtain the existing
CLI credentials once. A fixed read-only identity query requires a CLI-shaped actual
session_user, effective postgres and absent app UID/JWT GUCs. PGUSER must equal the
actual session user or that exact name plus the fixed project suffix. The same
transport/credentials perform plan capture, the sole mutation submission and the
fresh separate-session read-only classification. Private binding is copied only to
add the observed exact session-user name; it is never used to fabricate app claims.

Offline generation reuses the reviewed Docker function's fixed local image, no pull,
no network, no logs, read-only root, dropped capabilities, private mounts and bounded
JSON stdin/stdout. Only the entrypoint filename changes to `stage3_plan.mjs`.
Generated install bytes must reproduce exactly before submission. A fixed stage3
marker is created exclusively and fsynced before the single transport invocation,
under the original filesystem operation lock. COMMIT acknowledgment is recorded
separately from observed state; any exception is unknown, never a retry. The only
success state is `converted_target_verified` from the separately pinned plan.
Before-state, drift, observation failure and process termination retain the permanent
marker. No old unused-undo reference is copied and no undo is generated or executed.

Ten database-free boundary tests passed: source pin, identity/exact PGUSER, SQL
regeneration CAS, unknown COMMIT with fresh success/before observations, post-ack read
failure, durable marker on process exit, concurrent operator refusal, private-file
hash/symlink protection and generated-binding pre-import byte rejection. Tests reuse
the original real lock/marker primitives. They mock plan classification and transport;
they do not prove production mutation, native TLS/CLI/COMMIT/disconnect behavior,
financial arithmetic or real iPhone operation.

No DB connection or application mutation was made during this implementation.
A later process-start read-only recovery entry point is not supplied. If execution
is interrupted, do not delete the marker or rerun install; separately review a
read-only recovery bound to the saved exact SQL/binding/before hashes. Financial
conversion invalidates the previous unused-undo scopes.

Run locally: `python -m unittest -v test_owner_stage3.py`.
The tests require the existing source-only runtime at their explicitly documented
local scratch path; they are not a portable unconditional CI job.

Offline CLI integration also passed against the frozen stage3 plan
`e0fc92909160cf63e567f47b71824ec80581dca157696cbea9ac1b94d417a6e4`:
using the existing synthetic PGlite verifier's in-memory before/after, capture and
install CLI SQL matched direct API bytes; success/before/unknown classifications
matched the owner contract (five protocol checks). This reuses the engine fixture,
not a new native execution proof. Required execution closure is seven files:
owner, stage3 plan, stage2 reference, immutable checkpoint/preparation modules,
negotiation source and maintenance source. Tests/review/manifest are non-executable.
