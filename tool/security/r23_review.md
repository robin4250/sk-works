# R23 known-linked bulk synchronization filter (review only)

Five new files, based on R22. No original application/migration/payroll source
changed. Only catalog metadata (definition/owner/ACL/config) was read; zero
production writes, business-row reads or credential retrievals.

## Actual scope and narrow filter

`public.set_invoice_approvers(uuid[])`, body MD5
`9d59bbf09f2620f3fe9a58dfca6ae9a9`, is SECURITY DEFINER owned by postgres,
empty search_path, explicit authenticated/service_role grants. It chooses the
existing actor company, validates invoice-management permission and 1–3 distinct
same-company approvers, updates company configuration and resynchronizes every
draft invoice. Thus SELECT RLS cannot protect known linked invoices from it.

The candidate preserves that company configuration and validation. Exactly five
invoice operations exclude known line_invoice_submissions/historical links for
**every** actor, including Masters: invoice row locks, approvers_changed audit
INSERT SELECT, per-invoice approval DELETE, approval_finalized_at reset and
per-invoice approval INSERT SELECT. Exact anchor counts are 1+2+1+1; both lineage
sources are required in each filter. No new helper, grant, role, data update or
calculation change is introduced by installing this function definition.

This is not a company-setting Master-only gate. Ordinary company administrators
can still change normal invoice approvers, and ordinary draft invoices are still
resynchronized. The alternative of refusing the entire company call whenever any
linked invoice exists was considered but rejected here because it would block
ordinary invoice administration. There is no implicit export/visibility grant.

## Tests and original restoration

The fixture reuses unchanged R19–R22 sources and exact original setter body.
It reproduces the original linked invoice/approval/audit mutation. After applying
the candidate, both ordinary administrator and Master can change company settings
and ordinary invoices while known linked invoice values, approval rows and audit
rows remain exactly unchanged. Both current and historical lineage classifications
are exercised separately. Existing invalid-count/duplicate/wrong-company inputs
still refuse without side effects. Foreign-company rows remain unchanged.
OID/owner/ACL/config/SECURITY DEFINER and all five filters are checked, followed by
exact original definition restoration and changed-body refusal. Local PGlite
results are recorded in the PR; latest PG17/PostgREST CI must independently pass.

Actual HTTP tests invoke the same RPC successfully for an ordinary administrator
and Master, inspect synthetic SQL state, then restore disposable fixture rows.
Those cleanup statements are confined to the loopback fixture, never a production
restore command. No real payroll, invoice regeneration triggers or GoTrue issuance
are reproduced. The fixture modifies no computation source.

## Remaining blockers

Other helpers may later read changed company configuration and lazily regenerate
linked approvals; this candidate does not audit or guard those paths. Known
lineage classification is not complete provenance. Creation-before-lineage,
concurrent lineage changes, request/item writes, membership/invites, existing final
attendance/payroll copies, signed Storage URLs and external push remain separate
blockers. No all-data confinement or TestFlight safety approval follows from these
fixtures. Prior R19–R22 restrictions are review-only rollout prerequisites.

Before production: protected backup, successful relevant restore, current original
function definitions/ACL/dependencies, normal-company UI and Master comparisons,
explicit impact report and approval. Drift refuses rather than overwriting newer
payroll/source protections. There is no deployment or automatic migration hook.
