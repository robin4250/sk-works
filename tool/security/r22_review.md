# R22 correction decision boundary (review only)

Stacked on R21/#1191. Five new files; no application, payroll calculation,
existing SQL, migration, production setting, administrator or company mutation.
Supabase skill and current function-security guidance consulted. Production
interaction is one catalog-only SELECT (definition/owner/ACL/config); business
rows, personal values, credentials and logs were not fetched.

## Observed source checkpoint

The live public `decide_attendance_correction_request(uuid,text,text)` has body
MD5 `87b46c1df058ad8b455bcd843cf7f851`, owner postgres, SECURITY DEFINER,
search_path public/private/pg_temp and explicit postgres/authenticated/service_role
EXECUTE grants. No same-name private wrapper was found at this checkpoint.
Its definition is preserved in r22_catalog.json (schema source, no data).
Latest repository payroll scope-ordering SQL contains a *different* body. This
candidate intentionally refuses that body rather than overwriting its protections.
The payroll owner must separately review any composition; no source replacement
or automatic production application is provided.

## Narrow fix

The original definer bypasses SELECT RLS, so an ordinary company assignee can
approve a known LINE-linked request, inserting its proposed values into ordinary
attendance_entries and canceling matching leave. The candidate adds exactly one
R19 request-visibility check immediately after the existing top-level BEGIN.
It refuses linked approve **and reject** for non-Masters, before request reads,
locks, writes or notification generation. Existing assignee, self-approval,
company, decision and status rules remain unchanged for permitted actors.
CREATE OR REPLACE preserves OID, owner, ACL, configuration and SECURITY DEFINER;
these are asserted after replacement. Exact body, owner, configuration and helper
presence drift fail closed. No grant or role change is included.

## Scope limits / release blockers

This is not complete lineage confinement. A legitimate Master remains permitted
by R19, and its approval still publishes the values into ordinary attendance.
Tests explicitly demonstrate this remaining path; it must not be described as
fixed. Preventing that publication requires a separate product decision and
payroll-owner review, not a silent change to the original business calculations.
Creation-before-lineage races, unknown provenance, direct correction/item writes,
company-global set_invoice_approvers, invitation/member mutations, upstream source
creation, final attendance/payroll visibility and external push remain unresolved.
R19/R20/R21 themselves remain review-only dependencies, not deployed protections.

## Validation and rollback

The fixture reuses unchanged R19/R20/R21 chain and exact original correction body.
Synthetic tables cover ordinary past-attendance approval/rejection, unchanged
numeric and allowance inputs, leave cancellation, legitimate Master decisions,
non-Master/disabled-Master denial, wrong-company assignee denial, full snapshot
preservation on denial and transaction rollback, original metadata preservation,
exact definition restoration and changed-body refusal. It does not reproduce
real payroll/invoice triggers or GoTrue/device authentication. PG17/PostgREST CI
adds actual signed-JWT HTTP denial; until CI succeeds it is unconfirmed.

There is no deployment hook. Protected backup, full relevant isolated restore,
source/ACL/dependency revalidation, existing administrator/UI comparison, impact
report and explicit production approval are mandatory before a future rollout.
Rollback in fixtures restores the exact definition and verifies OID/ACL/config;
it is not authorization to restore an old production database over later data.
