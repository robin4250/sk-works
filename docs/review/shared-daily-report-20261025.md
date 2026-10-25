# Shared work report and supervisor collection candidate

Review-only. No deployment, rollout, real signatures, notifications or financial
updates have been performed. This owns only new files; DailyReportPage and the
global gate are owned by the integration task.

## Contract

The existing company/site/date and company/route/date uniqueness is retained.
`submit_shared_daily_report` serializes a destination/day, locks all affected
worker/month scopes and signs an explicitly saved, reviewed draft. It never
re-runs the destructive legacy draft writer during first signature capture. The second completed
participant reads/reuses the winner; it never replaces its roster or clears a
signature. Existing unsigned drafts require the exact displayed updated-at and composite
work/source-set CAS. Every server-known clock-in or validated manual attendance
identity in the same destination/day belongs to the initial common roster; the
client cannot omit a known coworker. A new member after the first receipt is an
explicit roster-correction hold, never an invisible append. The separate
membership candidate orders canonical worker/month locks before sorted group
locks, after the source-pinned date normalizer and before route-source locks.
It applies only to INSERT and never adds a row-before-canonical UPDATE lock.
Unprepared mixed-worker or mixed-month clock writes fail before acquiring an
additional canonical scope. The source-pinned authorized manager writer gets
one lock prefix that pre-acquires its full batch and affected-report scopes;
source sets are checked again after waiting for the last group lock. New
scope discovery requires reload rather than acquiring extra locks in reverse
order. Remote lock-order proof remains required before activation.

An eligible ordinary member belongs to the saved report roster, company and real
matching clock-in scope. A roster member can open supervisor collection readiness even while working;
actual final signature capture waits for all target personal checkouts and
confirmed closing facts. There is no early supervisor artifact to auto-finalize later. Reusing the report to satisfy
their own checkout does require their real exact clock-out. No other person's
shift is ended automatically. Same-site non-roster members are not eligible.

The supervisor API revalidates the member after all worker/month locks and the
report/roster/source locks. It compares both displayed updated-at and composite
signature scope; this includes the exact current hours annex when installed.
The immutable before-context must be retained throughout signature capture.
Changed facts require reload and renewed review, not an invisible refresh and
submission of the old signature to the new facts. Retry with an identical
already-saved signature is idempotent; different saved signatures are rejected.

## Management exception

`manage_shared_report_signature` requires current same-company membership and
server `can_manage_attendance`. It can collect reporter or supervisor signatures
without the manager's own clock/GPS/schedule/roster. It still requires actual
signature strokes and name, preserves actor versus actual signer in an append-
only private audit. Finalized edits use the existing approval workflow. The
approved-edit candidate observes the actual source-pinned approved-to-used
request transition and binds its reset to the same transaction, live session,
actor, report and company. It grants report-scoped approved-editor permission,
never global attendance management. Other clients cannot edit or sign through
an active session. Its final wrapper verifies current readiness and the exact
reviewed annex before calling the original signature writer. The hours module
must copy only unchanged, source-matching confirmations with explicit approved
editor provenance; changed peer or managed facts require fresh authorized
confirmation. Combined actual-v2 proof remains required before claiming this
continuation supported.
Management recovery must be reachable from a blocked gate only with the server
capability flag, and the management backend rechecks authority.

## Frozen work versus later hours

Under the initially-OFF shared rollout, server triggers prevent older draft or
hours clients from clearing the reporter signature or rewriting signed work
facts/roster. The first reporter's immutable work basis contains the work report
identity/description and roster identities only, not proposed or later
per-worker overtime, category, allowance, vehicle-closing or paid-hours values.
`work_signature_receipt(uuid)` is the owner-only schema2 adapter for the separate
hours protocol. Its evidence explicitly does not say the first reporter approved
later unknown coworker hours. Per-worker authenticated hours confirmation and
the final supervisor's annex signature are owned by the hours-v2 task.

`checkout_shared_hours_private.begin_work_report(uuid)` enrollment runs
before the FIRST signature only. Old reports are not reinterpreted as v2 just
because a rollout date is reached. `supervisor_snapshot(uuid)` supplies safe UI
inputs, readiness and fingerprint. `prepare_supervisor(uuid,text)` binds the
reviewed annex in a private transaction/actor/report context immediately before
the existing writer; direct old supervisor RPCs must not bypass required v2
capture. These interfaces must exist and the closing module must be explicitly enabled
before new work-only protocol enrollment. There is no silent v1 fallback.
Already-enrolled records remain protected after company rollout is OFF.

An ordinary already-signed roster member may append their own real source links
without altering signed work content. A recorded v1 paid-hours draft/ledger
hashes full source rows, so that separate basis cannot silently change; this
returns an explicit correction state. No quantity is invented or normalized.

Managed financial differences and ambiguous manual roster sources are persistent
management holds. Authorized read contexts preserve the server management
capability and safe reason-specific Japanese explanation. Signature writes roll
back; neither the UI nor repository automatically retries the same hold.

Per-stop `private.route_visit_reports` and their legacy RPCs are separate and
untouched. These guards and adapters apply only to canonical whole-day reports.

## UI hooks

Use SharedDailyReportRepository.loadForSource for a checkout anchor, loadReport
for a saved report list item. Explicit `enabled=false/state=disabled` permits the
existing path; missing API, error, unknown response never means disabled or
complete. The server `canManageAttendance` flag controls recovery visibility.
After reporterSaved, display the saved report read-only, suppress `_saveDraft`
and `_saveBeforeSignature`, and collect supervisor via `collectSupervisor` using
the immutable before-context. An exact approved edit uses
`approvedEditRequestId` and `collectApprovedSupervisor`; its report-scoped
permission is independent of `canManageAttendance`. Management uses
`manageSignature` and the actual
signer capture. Only the atomic shared path may omit the old all-peer-clockout
UI prerequisite; the ordinary reporter's own checkout remains mandatory. For
hours-required peers still working, first work-report signature and later hours
confirmation are separate; final supervisor/payroll is held until complete.

The detailed help belongs in the normal `?` help and must describe this division
without exposing raw schema, fingerprints or receipt IDs in product UI.

## Evidence and remaining work

New dedicated PG17 proof extends the unchanged existing save/sign/payroll and
registration source suite. It covers own-closed/peer-open first report, another
roster member opening readiness while still working, supervisor refusal before
all actual outs and confirmation, later real peer
checkout reusing the signed report, legacy overwrite rejection, other-member
refusal, same-company management exception and default-role denial. Auth, feature-permission surroundings and the closing-facts adapter are
explicitly synthetic; this is not real GoTrue or actual closing-facts API proof.
The composed hours/facts-v2 suite must prove authentic receipt creation and
trusted final materialization before activation.
Parser/client tests cover capability distinction, identity/day binding and
signature/annex readiness. Local Node syntax and diff checks only; remote
Native/Flutter, combined hours/facts-v2 proof, complete approved-edit session
continuation, final UI/help, production source pins,
activation and iPhone behavior remain unverified. The group/manager dedicated
proofs additionally cover blocked new arrivals, unprepared batch rollback,
same-worker cross-month rejection, and report-source expansion while a manager
waits for a group lock. The approved-editor proof uses the actual existing
request-consuming draft writer and verifies another session/actor cannot reuse
the exact continuation, including idempotent lost-response finalization.
