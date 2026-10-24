# Payroll Release checkpoint — 2026-10-24

The reviewed payroll UI and guarded backend rollouts are integrated. The app source retains the build 11/12 history; no old build was relabelled.

- Insurance: reference start/end months, manual average income, actual-income candidates, existing health/pension standard remuneration and effective month use the existing conditions save/recalculation path. Reference averages never silently replace the premium bases. Enrolled rate-based insurance requires positive standard remuneration. Related UI: 66 tests, all 9 checks passed.
- Individual allowances: legacy named daily slots and additional rows use one addable editor, preserving original IDs and amounts. Checkout offers company-registered day/hour choices with worker/report/version eligibility. Related checkout/individual tests: 94 passed.
- Backend rollouts: insurance_basis_reference_bounded_20261024; company_registered_names_context_bounded_20261024; company_checkout_receipts_bounded_20261024. Independent postflight/source/data comparisons passed. No actual worker conditions, financial amounts or publication activation were entered or converted. The first name-reader attempt rolled back on a catalog display-context mismatch; the corrected observation context retained every guard.
- Scope of evidence: insurance storage 41, names rollout 47, receipt rollout/races 132, local real GoTrue boundaries 72. These suites overlap and must not be added together. This is not iPhone evidence.

## Release gate

The comment-only iOS workflow checkpoint requests the exact-main iOS evidence required by the existing private TestFlight wrapper after support-only SQL/tool merges. It changes no workflow behavior. Complete exact-main Flutter/iOS/secret/provenance checks before the owner's Release build. Build 12 is installed; confirm the next unused App Store Connect build number before building. No new IPA has been created, uploaded or installed by this work.

## Device confirmation still required

Enter the owner's confirmed health/pension standard remuneration and effective month, save and reload, then verify the payslip deductions/net and PDF. On a valid normal checkout, select a registered day allowance, sign the report, and verify attendance and the unfinalized payroll/PDF. Do not fabricate attendance or personal insurance amounts.

## Remaining boundaries

Normal paid-work hours, breaks and rounding have no authoritative day-level source; affected hour allowance calculations stay blocked. Month-unit items do not appear at checkout; their publication/application boundary remains separate. Logout does not immediately invalidate an already-issued JWT in the observed existing predicate; real production RLS and immediate revocation are not claimed. Phone/Apple provider readiness and the administrator's real login methods remain separate work. Expense minus 1,000 and same-minute checkout prevention were user-confirmed earlier and are not repeated as data repair.
