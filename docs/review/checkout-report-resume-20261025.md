# Saved checkout report continuation — candidate stage 1

This candidate adds read-only lookup from an employee/date's saved exact clock-in/clock-out pairs to the existing daily-report editor. The attendance sheet can resume missing/draft reports after the work date without creating another clock event. An existing report is reused; inconsistent pointers, duplicate pairs/reports, wrong company, actor changes, missing roster, protected payroll and signed reports without formal attendance fail closed. Normal report save/sign RPCs remain the only write path. No production records were changed.

The immediate checkout page now reads saved report signature evidence after returning. Without the reporter signature it retains its saved-clock continuation rather than reporting completion or inserting another clock. A pending responsible signature is explicitly shown as not yet reflected in payroll, and does not launch the legacy route quantity editor. Both-signature and formal-attendance requirements are unchanged.

## Not the final mandatory workflow

The persisted reporter-signature flag is evidence only: it is **not** authoritative proof that every business-required field has been saved. This stage does not globally block navigation, tabs, notifications, app restart or deep links. It does not implement daily reminders. Therefore this candidate alone does not satisfy the latest mandatory reporter-registration requirement.

The next coordinated stage needs a server-scoped pending/unlock contract that verifies actual required fields plus persisted reporter signature, an authenticated-root navigation boundary that cannot be dismissed by route pops or local state, and daily business reminders until responsible signing and actual payroll reflection. Reauthentication must remain accessible; actor/company changes must reset scope. Optional report fields must not accidentally become required. The responsible-person fields must not block normal app access after authoritative reporter registration.

## Validation

Added SDK HTTP reader fixtures for five closed days resolving two complete reports plus three missing reports, overnight work-date retention, signature/formal-source separation, protected payroll, conflicting pairs, company/actor authorization and read failures. Added widget fixtures for source-backed resume, cancellation and saved-clock retry without reinsertion. These are synthetic client fixtures, not proof of real RLS or real sign RPC integration.

Local Flutter execution remains prohibited by the existing automatic approval decision. A dedicated remote workflow runs Flutter 3.47.5 analysis and the related tests. No Flutter success is claimed before that workflow completes. Static `git diff --check` passes.
