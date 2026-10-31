# WIP: birthday CAS version 2 successor

This draft preserves PR1685 at 1ff6038ad8725f1a35d10c31d63530226f84dc53 and original1603 unchanged. It is source preparation, not a deployable or enabled feature. No production database, Auth, guide, document, main or device changes.

The review-only installer replaces five canonical personnel functions, adds one nullable birthday column without backfill, advertises version2, and requires explicit original DOB identity/CAS evidence. A narrow DOB-only branch preserves all non-DOB worker/profile data and family IDs. Combined edits additionally require an original canonical snapshot digest. No freshly copied family payload is used to bypass conflicts. Legacy explicit DOB writes fail; legacy omitted DOB is preserved.

save, decide and private apply share a transaction-scoped worker advisory gate before mutable row locks. decide peeks identity, acquires the gate, then locks and rechecks its request. Final approval rechecks CAS. Direct private apply EXECUTE is narrowed while postgres SECURITY DEFINER public save/decide remain canonical callers. Exact five-function hashes, owners, attributes and ACLs are guarded. All non-system static callers (case-insensitive source scan) and stored dependencies outside the two canonical callers fail the installer. Dynamically constructed SQL cannot be exhaustively proved by static scans. Privileged service_role direct DML remains outside this RPC serialization guarantee.

New synthetic PGlite fourteen logical cases pass: read version, narrow save, non-DOB/family-ID preservation, stale conflict, legacy explicit denial, direct authenticated apply denial, legacy omitted-DOB preservation, pending, and approval-time conflict with decision-row rollback. This is not Native concurrency, real authentication, Storage, SDK/UI or device evidence.

A dedicated CI suite now prepares PostgreSQL17.6 two-connection wait/phantom/revocation schedules; success is not yet confirmed. Outstanding before review completion: verified Native results; both Profile and Employee version2 transports now have source candidates; their analysis/SDK/widget evidence remains pending; full source review and latest CI. Both source writers now preserve original date/digest and choose narrow DOB-only versus combined intent. This new client source remains unverified; no version2 rollout is permitted. Production approval must be separate from the guide/document correction package.

Run only in a disposable synthetic fixture:
`node tool/security/personnel_birthday_cas_v2/verify.mjs tool/security/fixture_dependencies/node_modules/@electric-sql/pglite/dist/index.js`

No rollback by deleting columns, historical rows, proposals or approvals is authorized.

DOB response hardening now rejects malformed status/flags/pending identity instead of displaying saved. A dirty-DOB form retires its intent on attempt and retains draft input without same-form retry after an unknown result. This is not cross-restart durable outcome lookup/idempotency. Private apply rejects non-object legacy pending proposals before mutation; new rollback cases cover JSON null and array. The bank preservation row is a synthetic column projection, not real banking Auth/RLS/trigger/Storage evidence. Latest hardening CI/Native and independent review are pending.

Qualification source now pins language, support, argument names/count/defaults/modes/variadic/all-types, binary/SQL-body shape and cost/rows alongside the existing five-function metadata. Read-only production catalog confirms those original attributes, exactly two canonical static callers across all non-system namespaces and no recorded apply dependencies. New fault cases cover intermediate publication failure, unknown final ACL/role, initial grant option, uppercase external-schema caller and parsed SQL-body dependency. PGlite passes5 atomic faults plus14 logical cases; Native observer/no-partial-publication and latest CI remain pending. No production application occurs.
