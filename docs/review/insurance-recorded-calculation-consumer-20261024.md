# Saved calculation -> insurance display regression

The user's report remains the primary investigation path: insurance was calculated and shown, then disappeared from statements around the individual earnings/deduction UI changes. Missing current tax-condition rows alone do not disprove an existing calculation result elsewhere.

## Confirmed consumer gaps

1. `PayrollFixedDeductions` requires the saved statement's condition version/start to match the currently returned profile before reading `tax_calculation.premiums`. Its previous saved-name fallback runs only when both profile and tax metadata are absent. A statement with a valid persisted calculation can therefore show blank insurance amounts when the profile is unavailable or newer, including when its named scalar values exist.
2. `PayrollPdfService` previously reads only the named scalar fields at `detail` level, although the producer persists the same individual premiums in `detail.tax_calculation.premiums`. A calculation-only representation can retain the correct saved deductions and net amount while the PDF drops insurance rows.

The candidate links the known persisted calculator contract into both consumers. It does not calculate premiums, look up current rates, copy an old profile into settings, change statement totals, perform an upsert, or rewrite saved financial rows. Explicit scalar values (including zero) take priority, and invalid explicit values are not replaced. Unknown/malformed/blocked/future calculations are not used for the fallback.

The individual UI labels a saved result whose current profile does not match as a saved calculation, displays it read only and does not request new data registration as the primary fix. Current verified automatic calculations keep their existing editable behavior. The PDF uses the same field-link helper for its preview/print/share renderer.

## Split-panel save path

The earlier `4117d1a0` layout split leaves `_loadWorker` and `_save` byte-identical to its parent. Both before and after it use distinct `custom_earnings` / `custom_deductions` keys. General salary saves do not send `insurance_mode` or `deduction_overrides`; these remain owned by the existing dedicated tax-condition RPC. Existing UI tests already exercise switching sections, adding a deduction, preserving raw input and both lists, and preserving insurance custom rows when one allowance is saved. These existing regressions should be run with the new consumer cases rather than duplicated.

## Verification

- Two widget cases reproduce saved premiums with absent/current-newer profiles, verify health/pension visibility, read-only status and unchanged saved data.
- Three helper tests cover calculation-only fields, explicit zero/invalid scalar priority and blocked/future/unknown/malformed contracts.
- The existing real-PDF reconciliation test includes a calculation-only variant with the named scalar fields removed. It must still match saved gross/deduction/net values and display all insurance names.
- Local `git diff --check` passes. Flutter is not executed locally; root runs the relevant analysis/widget/PDF CI.

These are reproducible source-contract gaps. Their presence in the user's exact affected row is not yet established. The separate presence-only observation found no positive candidates for the previously protected target, while company rate history exists; that observation does not establish the cause of every affected statement. Actual iPhone resolution remains unverified.
