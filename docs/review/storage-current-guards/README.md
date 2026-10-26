# Storage boundary audit and exact-catalog preparation

Base: `74d4c2f578e26ca1f7f21628f19a1da6b2fdeee9`. Review only. No database connection, migration, activation, account change, real file read or notification is performed by the preparation scripts.

## Current observation and reused evidence

The root owner captured only catalog metadata on 2026-10-26. All 16 buckets are private. No RLS-disabled public/storage table with client SELECT and no anonymous-executable public SECURITY DEFINER routine were found. These are bounded observations, **not a complete authorization test**.

Every current Storage SELECT/ALL policy (35 of 35) matches the established `storage_session_catalog.json` exactly for name, role list, permissive/restrictive mode, command and predicate. All six captured helper definitions also match exactly. All 59 locally inspected Storage/personnel/R19–30 source files match the main Git blobs in `source-pins.json`. Accordingly, do not rerun successful unchanged suites merely to renew a date.

| Existing proof | Exact evidence | Proven boundary and limit |
| --- | --- | --- |
| #1131 | run 38891139821, SUCCESS | Selected worker-document role/feature denial and exact policy restoration; not every Storage helper |
| #1136 | run 38895753226 / job 116955692830, SUCCESS | 16 SQL + 41 real disposable GoTrue/Storage HTTP checks of the live-session guard; no real Google/Apple or hosted CDN equivalence |
| #1228 | run 39016078478 / job 117348346167, SUCCESS | Same signed URL returns exact synthetic bytes after real logout before expiry, then rejects after expiry; this retained bearer capability is a limitation |
| #1216 | run 39009019393 / job 117327318684, SUCCESS | Atomic personnel policies and two private helpers, actual PG17/PostgREST synthetic signed-JWT role matrix, rollback/reapply; not a full production restore |
| #1226 | run 39015648825 / job 117347112169, SUCCESS | 16 personnel notification resolver cases with actual selected read/write guards; no real notification delivery |

## Confirmed outstanding paths

1. `worker_document_photo_managed_read` is still the permissive role-only manager branch. Its selected actual policy can retain worker-photo reads with `can_manage_people` OFF. #1131 deliberately narrows this authorization contract; owner/admin/self access is preserved by the existing proof. Do not claim an app menu permission alone closes this backend path.
2. The `worker_document_live_session_guard` policy, rollout table and helper are absent in the fresh root capture. The existing account guard checks account-deletion restriction, not `auth.sessions`. #1134's old-JWT-after-logout observation is still relevant to this unchanged boundary. Exact hosted exploitation is not performed in this audit.
3. All other buckets, signed-URL delivery, RPCs, service-role jobs and unknown LINE provenance require their own bounded evidence. The 35-policy equality does not prove every dependency/helper recursively matches or every permissive branch is safe.
4. R19–30 LINE/privacy candidates remain review artifacts. Their cumulative isolated success is not evidence that they were applied to production. Personnel direct/legacy/write production state requires fresh target catalog comparison before considering deployment.

## Prepared deltas and ownership

`prepare_storage_guards.py` reuses the exact SHA-256-pinned #1131 and #1136 SQL, with the original bodies unchanged. It adds one transaction, a five-second lock wait, a 45-second statement limit, complete current Storage object policy comparison, six full helper definitions plus owner/ACL/security/config/volatility, Storage table/schema owner/ACL/RLS and column-shape checks. It refuses source or catalog drift; no bypass flag exists.

- `storage-feature.guarded.sql.review-only`: immediate selected manager-read contract change. This is **not** an OFF install and must not be bundled as if it were. Its emergency restoration intentionally reopens the known original bypass; never run it as automatic recovery.
- `storage-live.guarded.sql.review-only`: existing live-session policy/helper/default-OFF rollout plus one owner-only installation receipt. The receipt stores the initial rollout row version. An ON→OFF transition in another transaction cannot masquerade as never used; removal then refuses. No client can read/write the receipt.
- `verify_guarded.mjs`: reuses the exact established synthetic fixture bootstrap only. Its new PG17 checks concern the new preparation guards, late rollback, unknown external dependency refusal, unused restoration/reinstallation, and ON→OFF removal refusal. It does not reimplement or relabel the earlier 41 real Auth/Storage checks.

The two layers are intentionally separate. The supplied live preparation was generated against the original fresh 98-policy catalog. If feature narrowing is applied first, **recapture the post-feature catalog and regenerate the live envelope**; do not bypass its expected-before comparison. Removal is in reverse order, with exact fresh post-catalog, stopped readers/writers, independently saved original metadata and the tested operator plan. DROP has no CASCADE. Catalog guards are not a substitute for a complete private Storage-object/DB/Auth backup or for provider/administrator recovery checks.

## Status

New wrapper PostgreSQL17 CI succeeded: head `f8d809d3c25c7386ae5ddf40abfb461e9bf91cc5`, run `40282520949`, job `121438749060`, 28 checks. Earlier failure receipts remain in history: SQL late-failure fixture dollar replacement and restore source-delimiter extraction were corrected without modifying the original product bodies or permission expectations. Main integration, protected full recovery rehearsal, production changes, activation, actual provider/administrator/iPhone checks are not complete. Existing build 20 IPA is unchanged. Root alone owns production integration and deployment.
