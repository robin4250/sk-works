# Explicit financial facts and fresh signatures UI

Requires the separately reviewed default-OFF PR 1419 transition. No production change or rollout is performed here.

An attendance manager opens an existing document report and explicitly chooses financial review. The page reloads the current server context and requires `financial_resigning_supported` before offering any history-protected signature reset. Absent capability on an old/unprepared database fails closed without changing signatures.

After the existing audited reset, all individual source scopes are loaded afresh. The existing worker facts controls and models collect actual category, applicable registered allowances and required hours. Every roster member must be explicitly reviewed. Editing any reviewed value invalidates that review. One reason and one atomic prepare RPC stage the complete batch; the individual confirmation writer is not called by this step. Vehicles and saved manual amounts are retained.

The server response and a subsequent reload must contain the same valid persistent transition marker. Existing real reporter and supervisor capture then perform the normal financial finalization. No signatures are synthesized or reused. The main draft writer is excluded for a staged report, including after reopening: it omits financial category and would overwrite the staged row. Invalid staged state remains blocked instead of falling through to that writer. Staged facts are read-only while fresh signatures are pending.

Current real Oct25 still needs actual manager input and new signatures. This UI does not invent reports for other dates, change salary type or silently remove saved allowances. The current non-applicable choice must be explicitly reviewed by the user.

Local Flutter/Dart is not executed. Dedicated CI analyzes the three touched files and runs focused repository/model/report-page flows, including old deployment, explicit category, signature reset, atomic stage and reopened/invalid marker behavior. Existing broad successes are not rerun by this workflow.
