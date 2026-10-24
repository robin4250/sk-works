# Insurance calculation reference: bounded backend candidate

Source baseline: main `f891c161ed03bd48afe1cbf3a6e9325bec925333`. No AGENTS.md exists in its recursive tree. This sparse review branch contains only the owned backend paths; adopt these paths onto main rather than merging the sparse root commit.

The existing authenticated/effective-dated personal tax-condition save stores an optional reference object in the existing private `value`. There are no new tables, enrolment defaults, premium-rate changes, standard-remuneration conversions, financial row conversions or automatic retroactive changes. Existing audit/history, optimistic versions, employee lock, payroll refresh and finalized-document protections are retained.

## API

`read_worker_payroll_insurance_income_history(p_company_id uuid,p_worker_id uuid,p_from date,p_to date)` returns contract version 1, exact company/worker/from/to, a SHA-256 `history_fingerprint` and `items`. Each item has `statement_id`, `month`, `gross_pay`, `finalized`, `revision`, and nullable actual `payment_date`. Dates are canonical month starts; the inclusive range is 1–120 months.

The range uses **payroll calculation period**, explicitly returned as `period_basis: payroll_period`. It must not be advertised as a completed statutory payment-month assessment. Payment dates are separate actual metadata, never guessed from the period. Statutory remuneration can include considerations not represented by this gross-pay reference. The standard-remuneration fields and effective month remain explicitly entered/confirmed by the operator/adviser.

One finalized document takes priority over draft alternatives. Its immutable snapshot gross includes frozen additions. A finalized row without a valid snapshot, duplicate finalized months, duplicate draft months, negative/out-of-range gross or a draft blocked by either the top-level calculation flag or tax detail is excluded, never substituted with zero. A unique draft includes active addition adjustments, not deductions or net pay. Missing months stay absent.

## Stored reference

`insurance_basis_reference` has exactly `schema:1`, `from`, `to`, `average_monthly_income_yen`, `source`, `observed_months`, `history_fingerprint`. The source is manual / actual_available / actual_complete. Manual requires observed 0 and null fingerprint. Actual requires positive observed count, server fingerprint and rounded gross average. Complete requires every requested month. Explicit reference changes are revalidated after the existing company/worker locks. Unchanged historical references remain available when other tax conditions are edited; they are not silently recomputed. Identical retry retains the original idempotent path.

`read_worker_payroll_tax_conditions` advertises `insurance_basis_reference_contract_version:1` only after the candidate is installed, while removing the new reference from legacy response `items.value` (including manual-premium mode). The new UI then calls `read_worker_payroll_tax_conditions_with_insurance_reference` for the complete private result. Both reuse exactly the same existing scope/access helper. A full-read failure is an error, not permission to save a reference-free fallback.

When a legacy client omits the optional reference while updating an existing condition row, the stored reference is retained, including on identical retry. There is no implicit clear-by-omission operation. Save responses for omission callers also remove the reference from response values so the existing exact request/response comparison does not report false failure. New callers explicitly send the retained reference and receive the full result. No salary values, insurance mode or standard-remuneration amount are changed by this response compatibility handling.

## Security and verification

Both new public RPCs are invoker-only; the private reader reuses the existing actor/account/payroll-settings view authorization before touching salary rows. Metadata validators and the save-reply helper are not authenticated-callable. No broader table or schema grants. Replacing the three existing private routines and the legacy public read wrapper changes exact source anchors under observed original MD5, owner, ACL, config, volatility and security guards and preserves those attributes.

Original catalog definitions/metadata were observed read-only from the specified project and kept in `private-insurance-reference-backend-20261024/source-catalog.private.json` and `public-wrapper-catalog.private.json` outside this branch. The four source definitions in the test fixture contain no salary/account rows. Review the live source/catalog again before any bounded deployment if prerequisites have changed.

The Native PostgreSQL 17 CI runner exercises the actual four source definitions, candidate SQL, APIs and save/reload. It contrasts full and legacy manual-premium responses and omission retry while preserving stored references. Authorization surroundings are synthetic; this is not a real GoTrue/session integration proof. Node syntax was checked locally; no local Postgres binary is available. Native CI is pending. Production unchanged.

Owned paths: candidate SQL, this review, insurance-basis-reference workflow, Native runner, and two insurance_reference SQL fixture files. Flutter/UI/model/test files belong to the separate insurance UI owner.
