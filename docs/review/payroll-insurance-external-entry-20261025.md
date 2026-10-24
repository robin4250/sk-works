# Insurance entry outside pay cards

Base main `e5d53daba0dcf9abc66377895f37698bd5676a0d`. Snapshot `a09ec18` contains
only the exact existing individual page, fixed-deduction state and fallback test.
The parallel `registeredAllowanceNamesLoaded` call-site change is not edited by
this lane; root must preserve that separate one-line overlay on integration.

## Placement and behavior

- One `保険料を設定` button sits before the earning/deduction section selector,
  outside both cards. It does not disappear with earning/deduction or hour/day/
  month selection. The same common entry shows actual read status, saved
  reference period/average and the applicable condition's start month.
- The existing `PayrollFixedDeductions` state is still the sole reader and draft
  owner. A small controller publishes its current state after the frame and
  delegates to the existing guarded `_openConditions`. No second RPC reader,
  alternate settings save, tax calculation or per-tab monetary entry is added.
  Returning from the existing settings route reloads the same fixed state/month.
- The embedded component suppresses its old primary/direct entry and old
  reference summary when attached to the common entry. Standalone callers retain
  their old fallback entry. Formula/dialog links remain available. Help identifies
  the common location and clarifies insurance remains monthly, even when viewing
  daily/hourly salary components; switching view never adds insurance again.

A controller owner token prevents old/disposed worker states from publishing
readiness into the newly selected worker's entry. Publish is post-frame to avoid
notifying the ancestor during build. Dirty, uncertain and resident-editing guards
remain in `_openConditions` itself as well as button presentation; a stale UI
cannot navigate past a newly dirty state. Existing salary drafts are not reset.

## Verification

New tests: configured/unconfigured/read failure, status/reference/effective month
outside every unit, single button outside Card ancestry, no duplicate reads on
unit switches, actual same-month callback and reload, unsaved deduction retained
with navigation blocked, stale owner callback/readiness refusal.
Existing standalone entry and individual salary-tab tests are retained. Remote
workflow analyzes the three touched runtime files and runs those relevant tests.
`git diff --check` and YAML syntax are checked locally; Flutter/Dart are not run
locally due to the earlier approval-review restriction. Remote success and iPhone
position/operation confirmation remain necessary.

No PDF/evidence-model files from `9177c18`, company-common allowance files,
financial data, backend functions or authentication configuration are changed.
