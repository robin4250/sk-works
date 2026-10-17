# Personnel production protection checkpoint — 2026-10-17 JST

Source baseline: `7ab795f3b2da14dd09fd4a6fc72897ec15f84ed5`. This is preparation only, not authorization to deploy or restore. Production access in this checkpoint was SELECT of catalog metadata and the three migration-ledger versions only. No personnel rows, user IDs, company IDs, provider records, passwords or tokens were fetched.

## Exact candidate and observed production definitions

| Candidate migration | Intended change | Observed production baseline |
|---|---|---|
| 20261016104441_personnel_direct_read_permission_guard.sql | Replace only two SELECT policies; align people-feature/account checks with canonical read while retaining own-record access and existing viewer scope | profiles predicate MD5 1f1384d90020f684fa997e8fa582e8a2; family predicate `ebbb5d4863aefdbb313b26d24cf61a6d`; both PERMISSIVE SELECT TO PUBLIC, CHECK null |
| 20261016113335_personnel_legacy_read_permission_guard.sql | Replace only private.employee_personnel_rows() authorization condition/denial SQLSTATE, retaining payload/public wrapper | private body MD5 `3dd173b3ba0768718bbc6f326ea1fb18`; public wrapper `1c119e25281012769df17297a56b1fe7` |
| 20261016120458_personnel_write_permission_guard.sql | Replace only private.can_edit_worker_personnel(uuid), retaining save/apply/approval/notification bodies | helper body MD5 `ead531bcf8b745788cd01371ac405014`; save caller `c11956bf0845ab725312928c2422a7ab` |

All three candidate versions are absent from the production migration ledger. Thus code integration is not production remediation. The isolated manager-OFF bypass remains relevant to the observed deployed definitions; no real-user exploit call was made.

Both target tables are owned by postgres, RLS enabled and FORCE RLS false. There are exactly the two observed SELECT policies and no per-column ACL entries. Table ACLs are `{postgres=arwdDxtm/postgres,authenticated=rm/postgres,service_role=arwdDxtm/postgres}`. This records existing privileges; no new privilege is granted.

Canonical helper MD5 `e884314c5119e72345e7614802432b15`, owner postgres, SQL stable invoker, boolean, non-set-returning, empty search_path, explicit postgres/authenticated execute ACL matches the candidate guard. Legacy private and write helper are postgres-owned stable DEFINER functions, empty search_path, default ACL; public legacy wrapper and save caller retain explicit postgres/authenticated/service_role execute ACL. The non-sensitive metadata snapshot is committed beside this report. It is NOT a database backup.

## Scope that must remain unchanged

No candidate statement updates auth users/identities, company_members, member_feature_permissions, master registration, worker/company IDs, personnel/family rows, wages, payroll, UI, provider configuration or stored approval assignments. The read-policy migration uses a short ACCESS EXCLUSIVE lock with a five-second lock timeout; both function migrations serialize cooperating DDL owners using an advisory transaction lock. Arbitrary concurrent function DDL is not excluded by that lock: coordinate a single DDL owner during any later approved window.

Owner/admin and enabled-manager legitimate access must be compared before and after. Self-only direct table access and active-only viewer company-list scope differ intentionally from broad management access. A separately registered approver with people permission OFF retains its approval route; that is not an unrestricted personnel-list grant. Never repair a rejected test by assigning roles, replacing IDs or moving company membership.

## Evidence already complete — do not reimplement

- #1125 and #1141: source integrated. Direct and legacy candidates plus regression scripts at main 0a727634 had identical Git blobs to exact successful #1141 head 7e465343. Isolated PGlite 0.3.14 direct and legacy suites were rerun successfully during the preceding checkpoint; not rerun here.
- PG17 + signed synthetic PostgREST: #1141 runs 38896055201 / job 116956669854 and 38896055199 / job 116956669457 prove the canonical RPC/direct REST/legacy matrix, OFF/ON/revocation, owner/admin/self/viewer, foreign/anonymous/blocked denial, exact original-policy/function restoration and reapply.
- #1146: helper-only write hardening integrated; existing save/apply/approval functions are preserved. Its isolated test includes the assigned OFF-manager two-approver path.
- #1142: client integrated; exact head 9f4af523 focused run38925240401, Flutter38925240511 and iOS38925240598 succeeded. UI source and privacy test blobs matched the preceding main checkpoint.

Synthetic identity/provider/master sentinels and restoration assertions are not complete Supabase Auth, production snapshots or real provider/device tests. Old-definition restoration deliberately reopens the known leak; it is not a safe automatic rollback.

## Saved / restored / missing

| Target | Status | Limit |
|---|---|---|
| Exact pre-change source SHA and candidate SQL | Saved in Git | Does not capture uncommitted Mac files |
| Non-sensitive production definition MD5/owner/ACL/RLS/ledger | Saved beside this report | Metadata only, not original full DDL or rows |
| Original fixture policies and private function definitions | Saved in existing synthetic fixtures | Not a fresh production restoration capsule |
| Fixture original-definition restoration, legitimate access and reapply | Verified in isolated tests | Deliberately verifies that rollback reopens vulnerability |
| Existing friends-release-fix uncommitted three-file work | Previously protected by root; not touched here | Must recheck root's saved copy before actual deployment |
| Full protected production structure/RLS/grants/functions/Auth configuration | NOT obtained by this lane | Acquire outside Git/logs using protected backup workflow |
| Actual administrator IDs, roles, company memberships, master/provider settings | NOT read or changed here | Protected snapshot and restoration comparison still required |
| Personnel/family/business rows and Storage bytes/configuration | NOT backed up here | No full-production recovery claim |
| Isolated restoration from a real protected production backup | NOT verified | Synthetic rehearsal is insufficient |
| Real current administrator and Apple/Google login/role/UI comparison | NOT verified | User confirmed account login recovery separately; not a blanket deployment test |
| Explicit impact approval for these production changes | NOT obtained | No production permission change allowed |

## Executable next independent preparation

1. Keep the catalog SELECT checkpoint fresh immediately before a proposed change; compare all exact guards, owner/ACL/security/RLS/policy inventory and migration ledger. Drift means stop and review, never bypass guards. Do not use a generic db-push that applies unrelated migrations.
2. A designated backup operator must save original full policy/function definitions and dependent ACL/owner/security metadata, required schema and business data, and actual administrator/provider/master/company-role recovery state to an access-restricted destination outside Git and chat logs. Record only a non-secret manifest and verified backup checksum here.
3. Restore that protected backup into a network-isolated disposable environment without outbound email/SMS/OAuth/notification effects. Compare actual protected identity/company/role/provider invariants internally; do not publish their raw values or per-person hashes. Verify both current restoration and candidate application.
4. Use synthetic authenticated users in the restored isolated environment for UI/canonical RPC/legacy RPC/direct REST comparisons: disabled manager cannot read coworker address/family or start unauthorized saves; self/admin/enabled-manager and registered approver legitimate paths remain usable. Include active/inactive and multi-company scope.
5. Prepare a concrete narrow deployment/abort checklist and dependency-order plan for the three reviewed migrations, blocking unrelated DDL owners. Obtain impact approval only after protected restoration, admin/provider/UI checks pass. Until then production stays unchanged.
6. After any later approved application, verify exact expected definitions and all protected identity/company/role/business invariants before claiming completion. Do not invoke an old-vulnerable rollback automatically; contain and review first.

Remaining product limits: foreground UI cancellation is polling-based (15 seconds plus up-to-10-second read timeout), not instantaneous. Non-first-company inactive profiles remain basic-only with incomplete-save refusal. A successful basic transfer followed by denied PII append can be partial and is not automatically retried/deleted. Real GoTrue/production JWT, device PDF/printing, real delivery and production restoration are unverified. TestFlight safety approval remains HOLD.
