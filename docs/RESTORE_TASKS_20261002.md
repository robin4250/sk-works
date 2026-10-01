# SKO restore tasks — 2026-10-02

Attendance additions requested during restore:

- [x] Monthly attendance calendar shows Japanese public holidays in red.
- [x] Monthly attendance calendar shows the holiday name in red.
- [x] Monthly attendance calendar can move to the previous month with the left chevron.
- [x] Monthly attendance calendar can move to the next month with the right chevron.
- [x] Month changes reload that month's attendance data instead of reusing stale data.
- [ ] Verify these two behaviors on the Release build installed on the target iPhone.

These checks are part of restore completion and must be rechecked during the final device route.


## Parallel-work operating rule

- While CI, builds, or remote checks are running, always inspect the remaining restore scope and continue with a non-conflicting task.
- Do not idle merely because one branch is waiting on CI.
- Before starting a task, check the latest branch diff so completed work is not repeated.
- When concurrent work has already changed the same file, refresh the latest file SHA and reconcile only the missing delta instead of overwriting it.
- Restore completion still requires the final Release build and real-device verification.
