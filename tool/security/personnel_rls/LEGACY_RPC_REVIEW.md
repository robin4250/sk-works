# Legacy personnel RPC guard (stacked after #1125)

`PeopleCloudRepository.loadAll()` first checks `_requireManagePeople()`, then calls
`people_management_records` and `employee_personnel_rows`. Viewers use the separate
`employee_personnel_view` endpoint. The deployed private legacy read function only
checked owner/admin/manager roles and bypassed the two tables' RLS. Consequently,
the #1125 table-policy fix alone did not close the old RPC route.

This additive candidate changes only the private legacy RPC's permission condition
and denial SQLSTATE (42501). It adds the existing active-account and people-feature
checks. The public signature/wrapper, active-worker filter, complete JSON payload,
function owner, ACL, security mode and search path remain unchanged. Viewer and
self access keep their existing dedicated endpoints/table scope.

The disposable tests apply the actual #1125 migration first, reproduce the actual
legacy RPC leak despite corrected table RLS, then apply this actual second
migration. They exercise the exact public/private legacy functions and canonical
read RPC against PostgreSQL17 and signed-JWT PostgREST. They cover OFF/ON/revoked
permissions, owner/admin, viewer, self, other company, anonymous and blocked users.
They compare complete legitimate payloads and all synthetic identity/provider,
master, membership/role, business row, policy and ACL state before/after, restore
the exact old private definition, verify the old leak reopens, then reapply.

The migration checks exact reviewed source/owner/ACL/security metadata of both
legacy functions and aborts on drift. A transaction advisory lock serializes
cooperating migration owners; it cannot block arbitrary external function DDL.
Production review must exclude concurrent function-DDL operators and take a fresh
protected snapshot immediately before the approved change. System-catalog row
locks or grants are not introduced. No production data or permissions are changed
by these tests or by merging this PR.

Production application or emergency restoration requires a protected current
backup, administrator/provider/account recovery safeguards, a reviewed restoration
plan and the user's explicit approval. Those production gates are not complete.
Restoring the old private function reopens a confirmed vulnerability and is not a
safe routine rollback. Never print real IDs, tokens or registration details.
