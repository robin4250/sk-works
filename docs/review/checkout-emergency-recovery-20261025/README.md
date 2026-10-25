# Build15 checkout registration emergency recovery

The operator reported on 2026-10-25 that the report screen displayed
`退勤した本人の勤務原本を確認できません` and only report/attendance-management
pages were reachable (IMG_4509 / IMG_4510). No successful real signature or
attendance correction is inferred from either screenshot.

## Immediate production mitigation applied

The target company's checkout_report_registration_private.rollout row was
observed enabled=true, starts_on=2026-10-01. A transaction locked that exact row,
required exactly that enabled precondition, and changed only enabled to false.
An independent subsequent SELECT confirmed false and the same starts_on.
Shared-report and shared-hours flags were independently observed still true.
No report, worker, signature, payroll, attendance, identity, provider, or other
company row was changed or deleted. The app rechecks on foreground resume.
Do not automatically re-enable the blocking gate when this PR passes CI.

This is an operational pause, not an unused uninstall and not a claim that all
pending reports are complete. Existing deployment backup's active-state receipt
predates this emergency pause and must not be treated as current flag state.

## Root cause and scoped correction

A saved report worker has no sourceClockInId in the report-row loader. Optional
group-checkout can populate it, but shared signed facts skip that loader and
routes need not use group checkout. Restricted registration required that
optional field even when the server's source-bound shared context had verified
the same actor/company/worker/day/report. Valid saved reports could thus become
unopenable inside a globally blocking gate.

The page now accepts an absent local source only with the server context's exact
actor/company/worker/source/day/report/clock-out, allowed state, destination and
saved roster membership. An explicitly conflicting local source is still denied.
No guessed source is assigned and no saved/signed roster is changed on opening.
Regression cases cover the genuine saved-report shape and a wrong source.

Management receives a separate existing-report entry point for the selected
worker/date, retaining fresh management authorization and server signature rules.
The existing direct-delete operation remains explicit and confirmation-based.
Do not delete real reports to escape the gate, bypass signed-fact/financial guards,
or claim the user's observed delete failure fixed without its actual error and
applicable protected-record contract being verified.

Local Flutter/Dart were not run. Focused remote CI is required for this new
candidate; the already successful build15 checks do not validate this patch.
Build15/main 045169174188262f05b17c38495359e1059ea03b is retained until a newly
validated Release is deliberately integrated. No build15 IPA is relabeled.

## Additional device findings after recovery

IMG_4511–4519 show registered company allowances, a blank work description with
an inaccurate changed-roster error, an unmarked management date picker, and a
numeric keyboard retained after returning home. These screenshots do not prove
an actual successful signature or payroll projection.

Blank work description now gives a specific Japanese prompt before any report
write or signature navigation. Known signature precondition errors are presented
in Japanese; StateError's English wrapper is removed. Source/roster drift checks
remain active for filled reports, and no failure is converted into completion.

Management date selection now reads month-scoped actual attendance entries,
canonical work_date punches and approved leave, displays distinct marks and
identifies unavailable evidence. Uncertain dates are not inferred from names or
clock timestamps. Back/dispose/drag release input focus. New tests cover scoped
reads, marker classification/date selection and returning without a keyboard.

The current force_manage_attendance payload accepts free allowance_names, not
structured company_allowance_selections. The management page explicitly opens
the selected day's existing report/common-allowance/signature UI. This patch does
not pretend that free names are registered selections and does not add a new
payroll writer. Direct structured allowance editing within the management form
remains a separate backend/client requirement. No production business rows or
rollout flags were changed by these follow-ups. The emergency gate remains OFF.
