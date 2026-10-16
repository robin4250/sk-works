# Personnel write authorization — review-only candidate

The live catalog's `private.can_edit_worker_personnel` allowed coworkers with
owner/admin/manager roles without checking `can_manage_people`. The actual public
`save_worker_personnel_profile` calls this helper before every save. When no
profile exists it applies the payload immediately, without approval; when a
profile exists, a disabled manager could still create a change request. This
remains reachable even after the two read-only fixes (#1125/#1141).

This candidate replaces only that Boolean helper. Active account access must be
explicitly TRUE. The existing self-worker branch remains; the existing same-company
owner/admin/manager branch additionally requires people permission explicitly TRUE.
It adds no membership, role, account, data or ACL changes. Exact source/owner/ACL/
security/search-path drift guards stop an unreviewed baseline from being replaced.
The current caller's source/owner/ACL is also checked. Advisory locking coordinates
cooperating migrations, not arbitrary external DDL; approved deployment requires
excluding other function-DDL writers and taking a fresh protected snapshot.

Call graph: a catalog search of all deployed public/private function bodies found
`save_worker_personnel_profile` as the helper's sole caller. The existing
`decide_worker_personnel_change` instead uses `is_worker_personnel_approver` and
calls `apply_worker_personnel_payload` directly. The save, payload, apply, decide,
and approver bodies are unchanged. A registered approval assignee with people
management OFF therefore keeps legitimate approval authority; they do not regain
permission to submit coworkers' changes.

The disposable suite imports actual captured save/helper/payload/apply/approval
and account-barrier/pre-request definitions, applies the actual two read fixes,
reproduces the original initial-profile write and existing-profile request, then
applies this actual migration. Owner/admin, self and enabled delegated manager
paths are compared; enabled-manager/self requests are approved through the actual
decide API. A two-approver case proves the separately registered disabled manager
can still approve as intended. Foreign targets, unrelated ordinary users, disabled
managers, unknown permission and restricted accounts are denied.

CI uses PostgreSQL17 and signed JWT requests through PostgREST configured with the
actual `private.check_account_access` pre-request. Most HTTP transactions roll back.
Two-actor approval tests commit only synthetic local rows and then restore the
exact original business-table snapshots; protected identity/provider/master/company
membership/role/approver tables are never reset. Tests assert all preserved data,
IDs, ACLs, RLS policies, source bodies and helper metadata. Restoring the original
helper is rehearsed and explicitly reproduces the known write vulnerability before
reapplying the candidate.

Limits: the fixture has synthetic minimal table dependencies. It does not model
every production trigger, delivery service, Supabase Auth identity schema or
real-device session. The captured pre-request function is exercised, but this is
not a real production restore/backup or an end-to-end approval notification delivery
test. Production payload triggers/side effects still require a separate protected
staging review. Restoring the old helper reopens a confirmed vulnerability and is
not a safe routine rollback.

Production remains unchanged. A protected current backup, administrator/provider
recovery safeguards, a reviewed restoration plan, exclusive authorized change
operators and explicit user approval are mandatory before any production permission
change or restoration. Merging this candidate is not deployment authorization.
