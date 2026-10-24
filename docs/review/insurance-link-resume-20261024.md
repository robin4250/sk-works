# Insurance path resume (2026-10-24)

The user explicitly withdrew the earlier instruction that payroll implementation was confined to Mac Codex. Work-side insurance investigation is resumed. Main baseline: `22bf00631ff4c63f5cad50952456dbedcb40df62`.

## Existing path retained

Individual payroll settings -> `PayrollFixedDeductions` -> `PayrollTaxConditionsPage` -> authenticated `read_worker_payroll_tax_conditions` / versioned `save_worker_payroll_tax_conditions` -> `payroll_tax_private.calculate` -> statement `tax_calculation.premiums` / named financial detail -> `PayrollPdfService`.

The saved named-insurance fallback is already in main. No historical amounts are reconstructed or changed. No automatic condition is created from the UI's initial health/pension checks and zero base amounts.

## Concrete omission corrected

The server's existing rates/manual contracts and PDF already include child support (`child_support`, 子ども・子育て支援金), but the individual fixed-deduction UI omitted it. The UI now reads it from the same effective monthly statement or existing manual profile as the other insurance entries. An absent result remains blank; an explicit zero remains zero; blocked automatic calculations do not display stale premiums.

The current deduction override contract does not accept `child_support`. This field is therefore read only; its formula/help opens the existing individual conditions or company rates. No new override key is sent and the existing unsupported-key rejection is preserved. No tax formula, premium, company allowance, DB schema, finalized statement, income tax or resident tax is changed.

## Verification status and remaining work

Five widget cases cover positive/zero/missing generated amounts, the existing manual profile and blocked results. The existing saved-name test now includes the omitted item. `git diff --check` succeeds. Local Flutter execution is intentionally not performed; root must run Flutter analysis and related tests in CI.

This UI omission does not establish the cause of the user's missing health/pension amounts. Actual premium reflection remains incomplete until the same person/month's legitimate conditions, saved calculation and PDF are verified. Previous private observations reported no condition/history originals for the earlier target; the UI connection investigation continues without fabricating remuneration or amounts.
