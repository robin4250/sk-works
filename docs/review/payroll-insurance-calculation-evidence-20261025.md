# Saved insurance calculation evidence in payslip and PDF

Base main: `e5d53daba0dcf9abc66377895f37698bd5676a0d`.
Exact source blobs: PDF `36868487bb952f8b4dd3af65ef1a7e21c05a263e`,
statement page `6b6a0ef65822e2c0d90ebd43688df813dd56c89c`.
This change is display only. No DB migration, settings save, insurance-rate or
financial amount changes; no production data is fabricated or repaired.

## Display

The payslip has an initially collapsed `保険料の計算根拠` card. The PDF uses the
same shared model in each insurance row and an additional basis band in the
existing whitespace between net totals and remarks/bank details. Main table
coordinates, adopted page and money totals are retained; paid-leave allocation
retains its existing separate note and the band moves below it. No extra page
or whole-page shrinking is introduced.

Health, pension, nursing, employment and child support each show their own saved
base, employee rate and premium. Employment says `当月対象賃金`; the others use
saved standard remuneration, or a zero calculation target where applicable.
Rates are formatted from saved scaled integers, never hard-coded to 4.925%.
Company rate definitions may predate the statement month: the model checks their
registered payroll month is not future and the saved insurance/payment month
offsets agree with this statement's actual insurance month/payment date.
Duplicated/missing/malformed/inapplicable rate evidence does not become a guessed
formula. Explicit zero, unregistered and failed/blocked records stay distinct.

Manual-premium mode shows saved manual input only when its saved amount matches.
An explicit per-item override shows automatic calculation and manual result
separately. Unexplained scalar/calculation disagreement is marked as disagreement;
the formula is never relabeled as yielding a different actual deduction. Saved
rounding results are read, not recalculated (health/nursing/support share rounding
semantics). The input detail is unchanged, including finalized snapshots.

## Average-income provenance: existing contract is insufficient

The existing saved `insurance_basis_reference` contains selected from/to window,
average, manual/actual_available/actual_complete source, observed count and a
history fingerprint. It does **not** prove any of the following:

- that manual input was an employee's initial salary rather than a later edit;
- the exact adopted month list when only part of the selected window exists;
- that the reference average produced the current bases, because notice-based
  base edits may deliberately differ while the reference metadata is retained.

Therefore the display says `参考入力：手入力の平均月収 ...` or a saved complete
reference period/count, and explicitly states the adoption relationship is not
recorded. It never presents an unrecorded previous-month salary as the actual
source, uses current settings to explain an old statement, invents missing months,
or changes the calculation policy. The exact requested labels `初回・手入力` and
`R8.x月 給与実績` must wait for an actual adopted-source contract; they are not
inferred from condition version 1, hire date, a single reference count or a
current payroll query.

### Minimal proposed future contract (not installed here)

Save an explicit origin with the condition and freeze it into tax_calculation:
initial application manual / single-payroll-month / multi-month average /
notice override; actual adopted month list and their statement IDs/revisions,
validated average, the derived health/pension bases, explicit overridden bases,
effective month and source/renderer version. Backend validates links against the
same company/worker/history fingerprint at save. A notice override records that
source rather than silently retaining an average-derived claim. Existing records
without this origin remain `採用元未記録`; no financial-data backfill is justified.
This needs a bounded backend/value-contract change and UI origin capture in a
separate owner lane. The current helper deliberately consumes no speculative
new JSON contract.

## Verification / limits

Remote workflow reuses the existing font/PyMuPDF pipeline and existing tax PDF
regressions. New tests cover separate bases/rates, non-hardcoded rates, manual
corrections, invalid/duplicate/future/month-shifted records, explicit zero/manual
premiums, unsupported/missing provenance, immutable input, same shared values in
screen/PDF, one-page money-column totals and coexistence with paid leave.

No local Flutter/Dart or database runtime was executed, honoring prior review
restriction. `git diff --check` / workflow syntax are checked locally. Remote CI
and visual inspection of its PNG remain required before merge. The previously
successful PR1371 actual UI→PG17→payslip→PDF proof remains intact; this change does
not repeat or invalidate that calculation proof.
