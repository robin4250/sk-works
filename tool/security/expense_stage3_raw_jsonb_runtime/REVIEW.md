# Corrected raw-JSONB stage3 operator candidate

This is a new artifact/attempt namespace after the original stage3 transaction
failed its unchanged original-source MD5 guard. The old observation classified
`before_state_observed` with no COMMIT acknowledgment. The root identified numeric
scale loss (`1.50` → `1.5`) during JavaScript object reserialization; no original
hash or financial guard is relaxed. The corrected plan carries the database's raw
JSONB text as a string and verifies both its PostgreSQL-text MD5 and typed equality.
Maintenance SQL remains byte-identical `33e6a098...`.

The old package, marker, SQL and before/after/binding/capture evidence are read-only
inputs. All seven old executable source hashes are fixed. The owner requires the
old marker's before-state, acknowledgment false, retry false, complete artifact
hash matches, complete typed before/after equality, matching authorization reference,
old-plan before-state classification and byte-identical old SQL regeneration.
Regeneration uses a new private scratch directory and never submits the old SQL.

A fresh native read-only identity query additionally requires PID3584894 absent.
Any process with that PID causes refusal, including PID reuse. The result is a
mandatory seventh identity field `failed_backend_present:false`; no backend is
terminated or otherwise modified. Exact actual CLI DB session identity and absent
app UID/JWT GUC checks remain. The same newly obtained transport credentials are
used for identity, current capture, the single new submission and fresh read-only
classification. Corrected capture preserves `original_payment_jsonb_text` verbatim
through Python JSON parsing and artifact storage.

The new package is fixed to `root/stage3-raw-jsonb-runtime`, and the new marker is
`expense-stage3-raw-jsonb-install-attempt.json`. Old markers are never deleted or
rearmed. The new marker records old marker/install hashes and the corrected plan
hash. The old marker is rechecked under the existing filesystem operation lock.
The corrected plan hash is fixed independently to
`bd7e98697f9b2374e6fb1e97c0c9f06910cba3f9c4b2e22f717bd4596bcd92ea`.
All previous runtime/source/private approval/backup guards remain. CLI entry remains
refused; only a reviewed pinned bootstrap can call `run`.

Fifteen mocked orchestration boundaries passed, including old receipt/source/file
hash drift, old SQL reproduction, source immutability, failed-backend refusal,
raw-string scale retention, unknown-COMMIT no-resend, concurrent operator and durable
marker preservation. The corrected plan's synthetic PGlite27 checks and five CLI
protocol boundary checks passed via the read-only in-memory verifier wrapper.
These results are not proof of native TLS/CLI session behavior or a successful
production conversion. No production connection or mutation was performed here.

The prior failed artifact cannot be re-executed through this operator. A failed or
unknown new attempt permanently blocks this new namespace too; do not delete its
marker or use historical unused undo. A separately bound read-only recovery is
required after interruption. Real phone/PDF confirmation remains a separate task.
