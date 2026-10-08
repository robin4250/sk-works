# Scoped staged group report source attachment

Baseline: main `a2a0ad26cebfbcc39ec99fe49f8b78d4ceb6c202`.
Supabase CLI generated migration `20261008161708_group_report_source_attachment.sql`.
Runtime dependency: #765 staged group checkout migration. No existing functions,
generic report RPCs, RLS policies, gate rows, permissions or registered data change.

Public contract (security invoker wrapper; private scoped definer implementation):

```text
attach_group_report_sources(
  p_daily_report_id uuid,
  p_anchor_source_clock_in_id uuid,
  p_source_clock_in_ids uuid[]
) -> {daily_report_id: uuid, source_clock_in_ids: uuid[]}
```

The result contains the exact selected unique IDs, sorted canonically. Call only
after a successful daily report save, and only with sources whose checkout is
already completed. Pending attendance may stay in the draft roster without
attachment. Manual roster members with no evidence are not passed or modified.

The existing group anchor helper requires an authenticated unblocked active own
worker, current company membership, site-only canonical work date and gate ON.
The report must exist in the exact company/site/work date, be saved by the caller
(`created_by` or `updated_by`), and include the anchor worker. Every explicit source
must be an actual active same-group clock-in, belong to a saved roster worker,
and have one consistent source-linked clock-out. Existing links to another report
are rejected. No inferred or old NULL work-date repair is performed.

Only the selected clock-ins and their actual clock-outs' `daily_report_id` are
updated from NULL. GPS/photo/origin, worker/company/site/route/vehicle, source,
timestamp and canonical date are preserved by both the implementation and existing
triggers. It never reassigns an existing report link. Signed status or a non-NULL
`signed_at` rejects changes; fully linked same-content retry is allowed and issues
zero UPDATEs, including after signing. Report and attendance locks serialize the
validation/write against signing and other attachments. No notifications are sent.

The isolated PGlite test uses authenticated roles, own-attendance RLS, company
report/roster SELECT RLS and denied direct UPDATE privileges, then executes the
actual #765 candidate/checkout RPCs. It covers NULL-photo proxy and personal early
leave attachment, atomic rejection, foreign company/site/month/source, absent
saved roster/author, pending checkout, duplicate/NULL selections, signed changes,
exact signed retry with an UPDATE-rejecting trigger, blocked/missing auth and gate
OFF. Snapshot comparison verifies every original evidence field except the intended
report ID is unchanged. Anonymous function ACLs are denied.

```sh
node tool/verify_group_report_source_attachment.mjs <pglite-path> <group-checkout>
```

CI checks out #765 at immutable SHA
`fa44c2badcecddb501c5637d7ca6656b13b84b36` as its dependency fixture.
This is a synthetic isolated fixture, not full production schema/data, concurrent
PostgreSQL session or device validation. Rollout readiness must additionally require
this public/private attach signature; parent handles the capability RPC separately.
No production migration or gate activation was performed; staged gates remain OFF.
