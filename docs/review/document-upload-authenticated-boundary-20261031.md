# Registered document new-photo composition (unregistered candidate)

Parent: PR1468 `253e48fa72159fa1eaa15235aae4beff268ee7d1`. This change reuses its `inspectPendingUpload` and does not modify that inspector, inspection SQL, existing worker-document change module, Storage policies, Auth helpers, public RPCs, grants, flags or UI. It is not deployable and cannot enable new photos.

## Implemented boundary

`createAuthenticatedDocumentUploadInspection` takes only bearer plus fixed request/upload IDs from its eventual caller. It gets actor and live SID from an injected trusted verifier. A trusted DB read must authorize the exact pending contract/actor/SID/company/worker/requirement/official-target/object/request/upload identities. Paths stay within the reserved worker-document request namespace. A version-bound reader must return the exact object ID/version and bounded bytes. The existing parser/inspection hash is reused, while selected SHA256/size must match the actual bytes before commit. A frozen copy prevents asynchronous adapter mutation of authorization scope. Parser changes, stale object identity, foreign sessions, and a failed atomic commit cannot produce a success receipt. No terminal receipt is generated before the DB adapter reports a committed result.

8 local Node tests use **synthetic sessions, DB, Storage and parser mocks**. They are boundary regression evidence, not real GoTrue/Storage/parser/transaction proof. CI results are separate. New object registration is not yet implemented by this wrapper.

## Required next implementation, still blocked

1. Reserve request/upload/status/actor/creation-SID and exact previous snapshot server-side, with upsert forbidden and only a new object name. Keep official row/history/old objects immutable during upload and review.
2. Implement the live verifier and private DB adapters using the current valid-session/people authority contracts. The commit must lock/recheck rollout OFF, live SID, current membership, active worker/requirement, draft state, old snapshot, object identity/version, declared and inspected hashes/size/MIME. A client-supplied actor/session/inspection verdict is never accepted. Creation SID is immutable; explicit new-session recovery needs its own current-authority check.
3. Prove an actual immutable, bounded Storage reader and pending-object UPDATE/DELETE protection against the full installed policy set. An unchanged version string alone is not proof of unchanged bytes. Avoid service keys in clients and direct formal-row write fallbacks.
4. Install a resource-isolated full-file parser (existing Sharp/PDF validator factory), including actual parser tests; this wrapper's tests mock it.
5. Bind draft finalization and separate-authorized review to the same immutable manifest, version and displayed bytes, preserve originals, apply once by the existing CAS/ticket, and reset original verification for newly changed photos. Do not reuse v1's old-path restriction by simply removing it.
6. Implement request-bound authenticated pending-image reads with current permissions and no-store lifecycle handling, then connect versioned client protocol, durable unknown-result reconciliation and review UI. Reuse PR1478 only when all v2 server/client contracts compose; accepting v2 alone does not enable uploads.
7. Actual PostgreSQL/GoTrue/Storage tests must cover immutable-version attacks, OFF/revocation races, dropped ACK, process restart, self/foreign approval, stale snapshots, before/after originals, finalization/approval atomicity and guarded rollback. No production installer is offered here.

## Rollout and recovery

Production HOLD and existing exemption/order OFF states remain. This candidate adds no deployed database object, grant, endpoint or feature switch and cannot change production documents. A future production application needs a fresh full catalog/Storage baseline, exact before/after receipts, independent review and explicit approval. Before any use, an unused-only guarded rollback may remove only its own objects. Once requests/receipts/history exist, preserve them and use forward recovery; never delete originals or reset data. Client upload errors must preserve the exact ID for receipt reconciliation rather than blindly re-uploading under another ID.
