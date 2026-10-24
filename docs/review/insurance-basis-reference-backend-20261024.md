# Insurance calculation reference: bounded backend candidate

Source baseline: main `f891c161ed03bd48afe1cbf3a6e9325bec925333`. No AGENTS.md exists in its recursive tree. This sparse review branch contains only the owned backend paths; adopt these paths onto main rather than merging the sparse root commit.

The existing authenticated/effective-dated personal tax-condition save stores an optional reference object in the existing private `value`. There are no new tables, enrolment defaults, premium-rate changes, standard-remuneration conversions, financial row conversions or automatic retroactive changes. Existing audit/history, optimistic versions, employee lock, payroll refresh and finalized-document protections are retained.

## API

`read_worker_payroll_insurance_income_history(p_company_id uuid,p_worker_id uuid,p_from date,p_to date)` returns contract version 1, exact company/worker/from/to, a SHA-256 `history_fingerprint` and `items`. Each item has `statement_id`, `month`, `gross_pay`, `finalized`, `revision`, and nullable actual `payment_date`. Dates are canonical month starts; the inclusive range is 1–120 months.

The range uses **payroll calculation period**, explicitly returned as `period_basis: payroll_period`. It must not be advertised as a completed statutory payment-month assessment. Payment dates are separate actual metadata, never guessed from the period. Statutory remuneration can include considerations not represented by this gross-pay reference. The standard-remuneration fields and effective month remain explicitly entered/confirmed by the operator/adviser.

One finalized document takes priority over draft alternatives. Its immutable snapshot gross includes frozen additions. A finalized row without a valid snapshot, duplicate finalized months, duplicate draft months, negative/out-of-range gross or tax-blocked draft is excluded, never substituted with zero. A unique draft includes active addition adjustments, not deductions or net pay. Missing months stay absent.

## Stored reference

`insurance_basis_reference` has exactly `schema:1`, `from`, `to`, `average_monthly_income_yen`, `source`, `observed_months`, `history_fingerprint`. The source is manual / actual_available / actual_complete. Manual requires observed 0 and null fingerprint. Actual requires positive observed count, server fingerprint and rounded gross average. Complete requires every requested month. Explicit reference changes are revalidated after the existing company/worker locks. Unchanged historical references remain available when other tax conditions are edited; they are not silently recomputed. Identical retry retains the original idempotent path.

`read_worker_payroll_tax_conditions` advertises `insurance_basis_reference_contract_version:1` only after the candidate is installed. A legacy client without the optional object retains its prior behavior.

## Security and verification

The public new RPC is invoker-only; the private reader reuses the existing actor/account/payroll-settings view authorization before touching salary rows. Metadata validators are not authenticated-callable. No broader table or schema grants. Replacing the three existing routines changes exact source anchors under observed original MD5 guards and preserves owner/ACL/config/volatility/security attributes.

Original catalog definitions/metadata were observed read-only from the specified project and kept in `private-insurance-reference-backend-20261024/source-catalog.private.json` outside this branch. The three source definitions in the test fixture contain no salary/account rows. Review the live source/catalog again before any bounded deployment if prerequisites have changed.

The Native PostgreSQL 17 CI runner exercises the actual three source definitions, candidate SQL, API and save/reload. Authorization surroundings are synthetic; this is not a real GoTrue/session integration proof. Node syntax was checked locally; no local Postgres binary is available. Native CI is pending. Production unchanged.

Owned paths: candidate SQL, this review, insurance-basis-reference workflow, Native runner, and two insurance_reference SQL fixture files. Flutter/UI/model/test files belong to the separate insurance UI owner.
