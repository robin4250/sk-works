# Selected approver access review

Baseline: main b65c0efe7c013737f9294cf7783061ae3661f8e6.

The new migration allows company owners/admins to select their own managers and
viewers for daily-report correction approvals and personnel-change approvals.
A selection grants only the existing approval capability. It does not change
company member roles or people/payroll/invoice/attendance management flags.

Daily-report request and approval SELECT policies now require the requester or
an explicitly selected approver. Approver eligibility also requires a current
membership in the same company and an allowed account. Unselected viewers,
other-company owners and departed assignees receive no approval access.
Personnel requests remain accessible through the existing selected-approver RPCs;
no general personnel-profile SELECT policy or write grant is added.

The first owner/admin membership in a new company seeds one personnel approver.
Existing company selections are neither backfilled nor reduced. Existing company
creation already assigns its owner as the single daily-report approver.
Configuration continues to accept 1–3 people and reject zero, duplicates,
more than three, and other-company candidates.

The existing daily-report rule permits any one configured approver to approve.
Personnel-change requests require the request's saved required_approvals count.
This migration preserves those distinct rules and verifies completion with one
approver; it does not infer a new unanimity rule for daily reports.

Verification: `node tool/verify_approval_assignee_scope.mjs <pglite-module-path>`
runs real migration functions and RLS in an isolated synthetic PGlite database.
Personnel payload application and notification delivery are fixture stubs; this
is authorization/decision testing, not a production data or device flow test.
The fixture also checks account blocking, membership departure, and preservation
of an existing three-person configuration after another administrator joins.

No production migration or device operation was performed. Viewer role labels, candidate descriptions and help now include English translations.
The isolated verification command is included in Flutter CI.

Still pending: invitation of a viewer as an approver. The invitation UI currently
automatically enables sub-administrator when approver is selected. The database
constraint employee_registration_invites_requested_approver_role_check requires
requested_role=manager when requested_approval_assignee is true, and
approve_employee_onboarding repeats that restriction. This separate invitation
workflow must be changed and tested together with its server input validation;
it is not covered by selecting an already registered viewer.
