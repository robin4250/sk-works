# Checkout selection to payroll: actual source boundary

Read-only production catalog inspection on 2026-10-24. No application/Auth rows,
credentials or financial values were selected; no mutation was executed.

## Existing finalization connection

The app's `DailyReportRepository` calls
`public.save_daily_report_signature(uuid,text,text,jsonb)`. Its invoker wrapper
(source MD5 `acb037e984efe9800318ec86aa936a4f`) delegates to the private function
MD5 `40f29d53008e6bf5610ce25e5fa96ef3`. That function locks the report's payroll
scopes, verifies actor/company/report and draft status, and requires both the
representative and supervisor signatures before calling the existing finalizer.

`public.sign_daily_report(uuid,text,jsonb)` MD5
`377d9ccf8ba28a3e0b38fc162e31c056` uses the report's owning work date. For every
report worker it inserts or updates the same attendance row identified by report,
worker, company, site/route and work date. It refuses an independent attendance
row occupying the same day/destination. It saves the report text as:

```sql
array(select distinct trim(v)
      from unnest(string_to_array(coalesce(allowance_label,''), E'\n')) v
      where trim(v)<>'')
```

Thus explicit registered-name selection can reach `attendance_entries.allowance_names`
without a new field, guessed amount or second registration. A normal API retry
after finalization fails the private draft guard; the lower finalizer itself
updates its existing report attendance identities rather than appending amounts.
These are source properties, not a replacement for a Native retry test.

The actual AFTER INSERT/UPDATE/DELETE attendance trigger calls
`private.attendance_refresh_payroll()` MD5 `9b13194c0f26be2afa6e9f2be236dba7`.
It refreshes both old and new work-date scopes for edits, then the wrapper
`private.refresh_automatic_payroll(uuid,uuid,date)` MD5
`5931608c50c554eb7fbd75bc9144628e` invokes the internal monthly calculator MD5
`b86d2c64609024b1f3f0342daefac690`. The internal function locks the month and
returns without changing a manual or non-draft statement. Its fingerprint/amount
comparison prevents an unchanged recalculation from incrementing payroll again.

## Proven missing connection: selection versus configured common amounts

The internal calculator first calls `payroll_unit_private.augment_settings`
MD5 `42c841c244f492de24f8ad299b56590f`. If company-common activation is absent,
`resolve_company_common` MD5 `ba65d7c894fbc0fa2b7bab41cc7dcb5f` returns no common
rows. The calculator's remaining attendance-name loop only recognizes individual
`allowance_name_1..3`, at the individual saved amounts. A company name not matching
an individual slot therefore does not acquire its company rate merely because it
was selected during checkout.

For an activated publication, old company slots use
`company_common_canonical_review_private.resolve_legacy` MD5
`cdafde8689df45273c6b469c2f684158`. It recognizes selected names, counts distinct
work dates, applies the saved company amount and zeros a same-name/same-rate
individual slot in effective settings to avoid double addition. Ambiguous or
different-rate individual collisions are blocked, not silently overwritten.

For **nonlegacy** company items, the current common resolver does not consult
selected names at all. Day items use every worked date; month items use quantity
one; hour items read a separate monthly quantity record. Therefore expanding the
checkout name list alone cannot establish selected common items flowing through
their original units to payroll. In particular, hour quantities must not be
invented from a man-day or silently converted into a monthly manual input.

## Detail and display boundary

`private.sync_payroll_attendance_detail` MD5
`cee56765d93e26bbed602339ced4c0d4` runs from another attendance trigger. It reads
raw individual settings (without augmenting them) and emits named legacy rows.
Common calculated rows also enter normalized `custom_earnings`/`unit_resolution`
through `private.apply_payroll_custom_money` MD5 `35c54dd6bcc855eb0076439c451cf7c3`.
A future Native/PDF proof must check their combination for name duplication and
totals reconciliation. No duplication defect is claimed from source alone.

## Candidate status and next ownership

The six-path UI candidate `0b34cb6` is preserved. It is a registered legacy-name
choice connection, not a complete fulfillment of all company-common selection and
payroll reflection. Root must coordinate the all-registered-name API contract and
one producer owner for common resolution/refresh/detail synchronization before
claiming completion. Current UI source is not deployed or merged; no unrelated
employee data, new rates or activation state was introduced.

Private catalog evidence (outside git):
`private-checkout-common-connection-20261024/actual-functions-and-triggers.private.json`
SHA256 `a954598a2c09ac1180e95bc52ef1f1f48b602407dcc29189501cbdb3a3f55967`,
plus the exact legacy resolver and detail-sync observations in that directory.
