# Worker document change candidate — review only

Base: aad4843e6fd26893a555b6ffc7c6d943d5207030. This candidate is not a product migration and must not be applied to an application database. Existing UI saves/reviewer inbox are not connected. Product source, SQL migrations, Storage policies, Auth/RLS and financial functions are unchanged.

## Contract

`public.worker_document_change(p_action text,p_data jsonb)` supports capability, prepare, submit, list, detail, cancel, approve and reject. Capability is version 1, change_requests_available true, new_upload_available false, max_photos 20, self_approval_allowed false. Fixed caller request_id is retained; prepare accepts status_id, expected_updated_at and exactly attachment_paths/expires_at/notes. Notes must be null or trimmed nonempty text. Proposed saved paths may only reorder/remove existing paths; approval checks object existence. Receipt includes six IDs, immutable whitelisted previous snapshot, proposed, state/timestamps/reason and can_review, matching the independent candidate client. No new upload or silent legacy direct-write fallback.

Preparing/submitting does not change the official row. Approval rechecks current account, membership/requester identity, active requirement, different authorized reviewer, exact old snapshot and attachments. Only a private transaction/actor/request/snapshot-bound single-use ticket allows the guard to apply proposed content. GUC values and definer-owner identity confer no bypass. Reject/cancel preserve official content; retries return stable terminal receipts, contradictory terminal actions fail. Cancel is draft-only. Status/original_verified-only manager confirmation remains possible but cannot mix content/identity/updater changes.

## Local verification

```
node tool/verify_worker_document_change_candidate.mjs /absolute/path/to/@electric-sql/pglite/dist/index.js
```

PGlite 0.3.14: **10 boundary groups PASS**, using saved original checklist/history, hardened status RLS, self-registration and multi-photo normalizer/audit/retention SQL. Synthetic users, memberships, account gate and Storage objects only. Tests cover proven initial placeholder save; own/manager direct-edit denial; history/ticket forgery; fake GUC; fixed command replay/conflict; new-upload rejection; official preservation; self/foreign denial; missing object; exact single approval; cancel/reject retries and opposite action; manager verification mixed-change/updater guards; stale CAS; transactional rollback; requester membership revocation; inactive requirement; malformed input; unproven old placeholder; account gate and retained attachment protection.

## Mandatory unresolved gates

- No native PostgreSQL 17, real JWT/session, live schema, full current RLS stack, Storage server/object bytes, advisors, concurrency interleavings or production deployment tested. Fixture role/account tables are explicit synthetic foundations, not proof of server authorization.
- CLI absent: no migration generated, migration/advisor commands not run. Supabase skill reviewed; trigger/functions official documentation was consulted in prior audit. This file remains review-only.
- Empty pre-audit placeholders without positive INSERT history fail closed. Existing history completeness is not assumed; a separate reviewed compatibility/backfill plan is required. No client may forge/delete this proof in the fixture. Initial INSERT still relies on existing product RLS/storage gates, which this candidate does not broaden.
- Guard rejects every direct official DELETE, including FK cascades and privileged maintenance paths. Impact on company/worker/requirement deletion and admin workflows requires explicit review before any migration. No retention data or existing row is deleted by this candidate.
- Reviewer rule is deliberately restricted to current owner/admin or existing approval assignee, with no self approval; role policy requires product approval. Rejection conservatively requires unchanged official snapshot too.
- Existing managed/own content editing, legacy first-save compatibility, qualification-photo approval, feature gate, durable client command storage, reviewer UI, and new-upload workflow remain integration work. This candidate does not claim all document/qualification edit paths are covered.
- Account helper only checks its existing contract; this candidate does not establish full server session revocation guarantees. Completed operation cannot be cancelled by a client lifecycle change.

## Source SHA-256

- `docs/candidates/worker_document_change_20261019.sql.review-only`: `67fa8b1b2ca8027aa39a08211942c8ee00f353bc92ac27ca5432134e565f9dc5`
- `tool/verify_worker_document_change_candidate.mjs`: `cbdf45a6d4b53bdada7a1bd1b711e9b0b5e5ed4719ae1150b62e1d784a5ebe47`
- `supabase/migrations/20260918133000_add_worker_document_checklist.sql`: `f0b2551b61d0b0a2be9e937bd85d76072cff0a5e66829ff3882550c2a6c90e93`
- `supabase/migrations/20260918144500_add_worker_document_status_history.sql`: `f63c59630441ae119429ea59f9d73eaac7ab9e1451c8678816abd05df11df71e`
- `supabase/migrations/20260919023500_harden_worker_document_rls.sql`: `69b5c08c41a97075c8ea86b5aaf00842e3324d752f24538ac6102b6765a217fe`
- `supabase/migrations/20261003121632_allow_self_document_registration.sql`: `a09f9a9ffe7927ee599a77e87f05689e0433ee78605a0b090b9326985edd64c1`
- `supabase/migrations/20261010222524_worker_document_multiple_photos.sql`: `6f628675124a342491838337de6762812d6b1319557584e86f39f7d3e21430b8`

## Subsequent local UI integration

The saved own/managed edit entry points, durable command store, and named review list were subsequently connected in ae59d9df/e9e81e1e. Combined document/notification tests passed 158 cases across 18 files, with 16 analyzed targets clean. This supersedes the earlier UI-not-connected statement for the local candidate only. New uploads, management qualification edit protection, native PG17/full production RLS/concurrency, compatibility/cascade gates and production/device deployment remain outstanding. No production migration is generated or applied.
