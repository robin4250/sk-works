# Individual required-document exemption candidate

Based on PR #1488 `dcbab453aaeefbfe48d9fa71972bdd0fbbfffb82`. No production writes, activation or release.

This adds exemptions to one employee and one existing company required-document ID. It does not exempt qualification ownership, license validity, or another company's requirements. Existing submitted statuses, paths, originals and histories are never changed.

## Behavior

- In employee document details, company owner/admin/manager can choose `この社員の提出を免除` or `免除を解除`. A nonempty reason is mandatory. The employee document shows `提出免除`, separately from submission/verification. Revoke restores the original missing/submitted predicate.
- The server validates a real existing account/session using the existing `require_reauthentication_session`, live company membership/role, active same-company worker and active same-company requirement under locks. First insert and later updates serialize by employee/requirement and compare an expected version. No user-provided actor or company role is trusted.
- The current table and append-only-to-clients event table are private, RLS enabled, no direct read/write grants. Scoped list returns only own active worker or own-company managed workers. Company administrators cannot activate the feature.
- Installation creates a private setting **OFF**. `list` returns current saved decisions and `can_manage=false` while OFF; new changes are denied. Existing saved decisions remain in effect when changes are disabled, preserving the administrator's prior decision rather than creating misleading missing-document alerts. A guarded root deployment must decide activation; no company/self activation API is included.
- Missing RPC only (`PGRST202` naming this endpoint) keeps old behavior and hides exemption action. Network, permission, malformed response errors do not manufacture exemption evidence.
- Attention keeps existing bank-account/photo rules and excludes only active scoped exemptions. Setup reads the same saved exemptions and displays `notApplicable` with an exemption version, never fake `saved`/submitted evidence. Both refresh on existing reload/navigation paths.
- Saved attachments remain available through existing Storage permissions. Nothing is moved or deleted.

## Verification and deployment limits

`tool/verify_worker_document_exemption.mjs` exercises actual candidate SQL with synthetic company/user/session fixtures against PGlite and PostgreSQL 17. It tests owner/manager, worker-only read, viewer/foreign/anonymous rejection, missing and expired session/account blocks, stale CAS, OFF state, revoke restoring attention and unchanged submitted/photo data. This is not actual GoTrue or iPhone validation.

The installer is **review-only**, outside migrations. Root must bind exact current catalog/body/ACL and business-table backup hashes, prepare tested unused restoration and retain the production snapshot before applying. Production attention body was read-only inspected; the bank/photo rules differ from the historical migration, and the patch therefore requires that reviewed shape. The source-shape guard is not a substitute for the production exact-catalog guard. Do not apply a fresh migration version or auto-enable from this candidate.

After any saved exemption/event exists, do not use an unused restore or delete audit data. Disable new changes and retain rows pending forward recovery instead. No hard immutability or absolute security claim is made for database administrators.
