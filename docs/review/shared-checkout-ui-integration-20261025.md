# Shared checkout UI integration

Exact shared-file baseline: main `71cf84f7bb31b160c4da0d3eb11763633032a7ee`.
This candidate changes only the reserved report page, checkout gate and personal
attendance page, plus focused UI tests and this workflow/documentation. Component
files are owned and published separately. Do not overlay old component snapshots.

## Authority and navigation

The report gate has priority. Scheduled checkout confirmation wraps the ordinary
Navigator inside the report gate's retained Offstage child. Each restricted flow
uses its own isolated Hero/Navigator; system back reaches the scheduled handler
only when there is no outstanding report block. A native tap/due signal performs
a fresh same-UID/session server read before acknowledgement; it never directly
opens an ordinary route or marks work complete.

Personal checkout opened from a schedule is pinned to the exact clock-in source,
worker, company, work date and site/route. Missing/mismatching/closed source cannot
silently choose the first open shift. Overnight work retains the clock-in work
date. Existing uncertain-photo/checkout recovery is preserved and cannot be
reassigned to another source.

Activation alone is not evidence that the mandatory report feature is ON. A
fresh async saved-source check returns to the existing optional group/report
flow when the server explicitly reports OFF or no applicable obligation. Unknown
state and failed reads remain protected. Group checkout still precedes first
reporter registration in the restricted flow. Scoped management recovery is
available only after a fresh server permission check, never ordinary navigation.

## Work report and personal facts

Shared report reuse loads the existing saved record and only asks the server to
attach the exact own completed source. Opening another reporter's saved work
does not call the old draft writer, clear signatures or overwrite roster facts.
The first shared reporter uses the atomic source-bound submit API. Other
members' own clockouts remain independent. Explicit work-only v2 capability is
required before relaxing legacy all-member clockout/meter-before-sign guards.

After work signing, common work facts remain read-only. Personal actual facts
use a separate editing copy and explicit source/revision-bound confirmation API,
not the original daily-report/RW save. Unconfirmed proposals are labelled; blank
numbers are rejected rather than converted to zero. Missing/stale hours start
blank. Ordinary users edit only their own authorized snapshot; manager
confirmation requires a server capability and an entered reason. Registered
allowance choices are retained as typed identities; manual cash is read-only.

Supervisor collection refreshes and previews the server's exact work payload and
personal evidence, including outstanding members. It captures the immutable
updated-at plus composite signature scope before drawing and submits that same
scope afterward. Incomplete actual facts cannot become zero/ready. A competing
change must cause a server CAS refusal and a new review. Existing approved-edit
sessions keep the original authorized correction path.

## GPS settings and device reminders

The personal page reuses the shared two-time selection helper, including its
saved revision and same-session guard. Permission requests occur only during an
explicit Save. Notice failure cannot hold an already-saved checkout away from
its required report. The native coordinator is bound to the authenticated actor,
uses server-generated UTC fire instants and cancels/replans after actor changes,
settings, postponement, actual checkout and authorized correction. Closing an
iPhone app cannot force it open; actual OS delivery/background behavior still
requires device verification.

## Verification and release boundary

Focused widget tests cover exact-source selection, wrong/missing source refusal,
unrelated capture preservation, explicit-OFF legacy group flow, report-over-
schedule priority, system back/deeplink isolation, authorized management, shared
read-only state, v2 work-first behavior and explicit personal fact confirmation.
Existing checkout/recovery/GPS/approval/common-allowance regressions run alongside.
Local diff validation only; Flutter/Dart execution is delegated to remote CI.
No production apply, activation, cron, real notification or iPhone installation
has been performed by this candidate.
