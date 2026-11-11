# Registered-document live-session deployment guard (review only)

This generator wraps the immutable **20261029 session successor**, never the old 20261019 session-less module. It does not authorize installation or activation, and is not a product migration. Production data, grants, Auth/RLS and feature settings are untouched by this PR. Source and unused restore SHA256 pins are checked by Python using ordinary exceptions, including under `python -O`.

## Compatibility and remaining connection

The session successor returns capability version 1, five keys, `new_upload_available=false`. Current main's strict v1 parser, own/managed change pages and separate review page already accept that shape. PR1478's v2 acceptance is unnecessary for existing-photo reorder/removal, expiry or notes, and must not be confused with enabling new photos. No UI fallback to direct overwrite is introduced.

Actual production catalog observation is retained privately: the change RPC and module are absent; its three existing helper definitions/owner/config/ACL match the immutable successor's pins. Document-bucket configuration is private. This observation is a dependency check, not real user or iPhone completion. Capture a fresh catalog before any later deployment; other production DDL/function changes invalidate the saved snapshot.

The rollout is a **global singleton**: OFF installation still leaves editing unavailable. OFF stops request/detail/review operations; the unchanged candidate preserves legacy unrelated/status-only/initial operations and does not impose a blanket freeze on every existing writer. A separately approved activation exposes the existing-person/company/current-authority and different-reviewer flow across eligible companies. A second currently authorized reviewer is needed; the requester never self-approves, and no reviewer permission is added by this proposal. It does not add uploads and does not waive a document. UI company selection is another gate: legacy document repositories currently select their first company membership; explicit company scope, or rejection of ambiguous multi-membership, must be connected before broad rollout. Do not call that unresolved profile complete.

## Generated proposal

`catalog.sql` reads existing function full-attribute hashes across public/private/auth/storage, twelve dependency relation catalogs (columns/defaults/owned sequences/constraints/indexes/triggers/policies), four schema ACLs, application-role authority and membership edges, all default ACLs and one fixed worker-document bucket configuration. It reads no document, signature, payroll, bank-account values, user/session rows or file bytes. Run `capture.sql` to export its single `capture` value, containing both the snapshot and the same-statement core SHA256 fingerprint. Store that value privately; never commit it. Sequence int8 fields are strings, preserving their exact maxima. Generated SQL compares the same database-side SHA256 rather than embedding or round-tripping a megabyte of catalog JSON. The canonical catalog query is SHA256-pinned by the generator.

```
python3 docs/review/worker-document-change-root-guard/prepare.py \
  --before PRIVATE-before.json \
  --catalog docs/review/worker-document-change-root-guard/catalog.sql \
  --candidate-dir docs/candidates/worker_document_change_session_20261029 \
  --output PRIVATE-new-directory
```

The output has three **review-only** scripts and SHA256 receipts:

- `install-off`: full before/after original catalog comparison, new-object absence, status/history SHARE lock, transaction-local full-row digests, immutable raw installer, exact new-function/table/trigger authority, OFF/zero-use and original-content preservation. Existing function bodies and ACLs are never replaced.
- One newly created public endpoint explicitly revokes inherited `service_role` EXECUTE, needed because schema-public default privileges otherwise survive the raw installer. Authenticated access stays; private dispatch and tables remain owner-only. Existing C/financial/Auth permissions are untouched. The new module's installation seal is refreshed after this narrower new ACL.
- `enable-separately-approved`: a separate global DML proposal, bound to the exact deployment receipt, original dependency catalog, full new-module manifest and zero-use OFF state. An OFF-install approval is **not** activation approval. This file must not be applied while profile/rollout review remains unresolved.
- `restore-unused`: exact deployment receipt/full new-module manifest, OFF/zero-use and immutable raw restore; original catalogs/status/history are rechecked. Any request/event/ticket or drift refuses restoration. No CASCADE, original row deletion, app reset or post-use rollback is provided.

New-module manifest includes full function attributes, relation columns/defaults/constraints/indexes/policies, types, sequences and the exact guard trigger. A private deployment fingerprint is stored only as a comment on the newly created installation table. For COMMIT transport uncertainty, read that fingerprint, stored seal/current manifest and OFF/usage state; never blindly reinstall or infer success from a lost response. Save the committed receipt before any next step. After use, pause and investigate forward; preserve requests, events, history and originals.

## Verification and limits

The dedicated PGlite/Native fixtures reuse pinned actual helper bodies but **synthetic surrounding Auth, accounts, memberships, sessions, Storage rows and policies**. They do not prove actual GoTrue/Storage, installed RLS composition, signed URL revocation, file immutability or device interaction. The unchanged session successor has a separate actual-GoTrue/PostgREST fixture; its existing successful evidence must remain distinct from these new guard tests.

Boundary cases include existing function/comment/ACL, inherited-role authority and Storage-policy/default-ACL/bucket drift, a same-name preexisting trigger, OFF install/unused restore, public-only default EXECUTE narrowing, new-module column drift, old SID failure and explicit live-SID recovery without rewriting creation SID, v1 proposal immutability, self-approval denial, different-authority final apply and after-use restore refusal. Existing photos stay on their saved paths; new upload remains rejected by the immutable server/client protocol. The schema-public defaults fixture is deliberate; no default grant is added to private/global scope in the accepted installation.

Pending: exact-head Native/independent review, fresh production baseline/composition, explicit installation and separate activation approval, profile selection, signed Release installation and actual editing/approval/device confirmation. CI alone is not production readiness or a completed edit feature.
