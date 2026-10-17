# R21 selected linked writes and invoice approval guard — review only

This stacked candidate follows R19/R20 without changing their files or applying any
production mutation. Five new files only; no payroll calculations, final attendance
or source records are modified. Source/ACL catalog inspection used definitions and
metadata only, never business data. Definitions are existing repository code, not
real payloads, admin IDs, email addresses or documents.

## Selected enforcement

Five additional restrictive FOR ALL policies cover invoices and dedicated analysis
groups/notes/albums/items. USING checks the old row, WITH CHECK checks the proposed
new row, both using existing R19 authoritative-lineage helpers. Existing ordinary
company/group permissions remain AND requirements. SELECT alone is insufficient:
the fixture first reproduces a non-Master INSERT into an analysis note and a real
existing definer approval of a linked invoice, then blocks these separately.

The three individually targeted SECURITY DEFINER functions are approve_invoice,
cancel_invoice_approval and set_invoice_stamp_display_date. Each receives an early
R19 invoice guard, validating current exact body MD5/owner before replacement and
preserving OID/owner/ACL/search_path/config. No function is moved and no public grant
is added. Known linked non-Master operations deny before body mutation. Normal
invoice approval/stamp/cancellation and legitimate Master operations retain original
approver/company/feature requirements.

## Source/permission evidence

Read-only live metadata confirms the four private lineage tables have RLS and ACL
limited to postgres. has_table_privilege for anon and authenticated returned false
for every SELECT/INSERT/UPDATE/DELETE permission. This rules out direct client
table tampering at that checkpoint, not SECURITY DEFINER or future migration paths.
The fixture rechecks client table permissions, but does not claim fixture metadata
is a fresh production read or a full graph audit of all lineage-writing functions.

Actual set_invoice_approvers is company-global: it audits/deletes/recreates approval
rows and clears finalized stamps for every draft invoice in the company. It can
therefore indirectly affect linked invoices. Blanket Master-only company config
would break ordinary operations; selectively skipping rows while changing the
shared source configuration also has future effects. This candidate DOES NOT
silently change that function. Separate configuration provenance/snapshot design
and compatibility review is required. This remains a release blocker.

## Isolated proof

The runner reuses exact-hash R19 source and existing R20 hooks. A new mode600
temporary module injects bounded hooks and retains original assertions/cleanup;
no tracked prior fixture is edited or copied into this change. The fixture grants
synthetic ordinary company writes to exercise the restrictive policy, not to claim
every production permissive policy is identical. All positive write/approval tests
run within rollback transactions. One HTTP ordinary-note update is explicitly
verified then restored to its synthetic prior value before byte comparisons.

SQL checks cover protected inserts, old protected group escape, proposed new group
and invoice-ID movement, foreign-company movement, full-table UPDATE/DELETE with
linked preservation, valid Master modifications, ordinary employee writes and
ordinary versus protected invoice approvals. Exact target definition/OID/owner/ACL/
config restoration and last-target drift rollback are mandatory. R19 snapshots
confirm original data and all policy metadata are retained after candidate removal.

The PG17 job additionally uses real PostgREST signed LOCAL synthetic JWT POST/PATCH
and approval RPC requests. This is not GoTrue, real device auth or full production
schema/trigger equivalence. Actual helper side effects inherited from R20 retain
its explicit minimal-model limits. No production tokens or endpoints are used.

## Still blocking full closure

* INSERT before private lineage exists can still take the prior path. This candidate
  is not proof of lineage-before-payload atomicity or complete historic classification.
* Unknown IDs, mismatched paths/actions and missing references are not inferred as
  ordinary. They remain unresolved; no guessed title/worker-date restriction occurs.
* Generic definer mutations, company-global set_invoice_approvers, invites/member
  additions and other chat management functions are not closed by these policies.
  In particular, inviting a general member into a dedicated analysis group conflicts
  with its Master-only purpose and needs a separate reviewed server boundary.
* Linked correction approval can publish LINE-derived raw values into ordinary final
  attendance and then payroll/payment documents. No safe exact entry mapping/deny
  candidate is supplied here; no final attendance/payroll function is altered.
* Storage INSERT/UPDATE/DELETE, direct notification writers, other push/enqueue paths,
  Realtime/caches/signed URLs and unclassified legacy copies remain outside scope.
* New authenticated restrictive policies do not establish a universal anon guarantee;
  existing anon privileges and exposed definers must be checked independently.

No TestFlight clearance or live deployment follows from a green fixture. Protected
complete target backup/restore, legitimate admin/provider compatibility, remaining
read/write/provenance closure, impact report and explicit final approval are required.
