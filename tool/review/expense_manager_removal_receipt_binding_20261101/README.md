# Canonical receipt binding: isolated successor only

Not deployable. Not in Phone Release. SQL77dc and bridge46773 remain frozen.

This supplement requires an empty isolated removal ledger, canonical receipt migration and the exact frozen function bodies. It retains `before_row=to_jsonb(claim)` and a separate immutable receipt snapshot. `attached_metadata_only` means attached metadata was captured, not proof of object existence/bytes; `reserved_not_attached` is not a submitted photo; `unrecorded` is unknown historical photo provenance, not proof that no photo ever existed. Mismatched company/applicant/creator rejects atomically.

The canonical submit locks receipt then claim. Removal takes a claim-specific transaction advisory lock, receipt SHARE, then claim UPDATE. A new receipt INSERT-only trigger takes the same advisory lock and refuses existing tombstones, protecting earlier legacy prepare validation without rewriting the existing prepare/submit RPCs. Two actual connections test reservation-first and removal-first interleavings. No attached UPDATE trigger acquires that advisory lock after a claim lock. No claim JSON, receipt metadata, objects, financial originals or existing Auth/financial helper bodies are changed by the supplement.

Fixture uses actual receipt migration and wrappers, synthetic Storage catalog and identity. Corrupted metadata is deliberately seeded only in isolated negative tests. All prior synthetic GoTrue/account-access limitations remain. The public result/notice DTO is unchanged; removed workspace uses the same receipt_object_path field as canonical wrappers and separately states preservation status. No new UI behavior or real Storage operation is asserted.

Workflow is disabled pending independent source review. No Native result yet. Financial shared-reader, legacy rollout, deployment admission, real Auth, Storage bytes, push and device remain unqualified.
