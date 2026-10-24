# Company-selected checkout allowances: bounded contract

This is an independent review candidate. It changes no production data, activation,
registration UI, salary rate, insurance calculation or existing signed report.

## Proven existing connection and gap

The actual signed-report writer stores distinct selected text in attendance and
the existing attendance trigger recalculates the owning month. Manual and frozen
payroll are protected. However, the common resolver currently counts all days for
new day items, uses monthly manual quantities for hour items, and does not consult
checkout selection. Without activation, company items do not enter effective
worker settings at all. A UI-only name choice is therefore insufficient.

Observed source pins are recorded in the sibling checkout investigation. Relevant
additional catalog observations are:

- `attendance_entries.regular_hours` exists, NOT NULL, default `0`.
- The current signed-report writer does not INSERT or UPDATE this column.
- Normal and route report-worker payloads contain overtime/early/night components,
  but no normal-work duration or break duration.
- Catalog column discovery found no paid-work/break-duration source in the
  application attendance schemas. Clock verification timestamps alone do not
  establish paid work time or rest deductions.

Accordingly, an hour selection without an authoritative recorded actual-hours
source must explicitly block calculation. Neither day*8 nor raw clock elapsed
time is a justified substitute. The missing source is not silently zeroed and no
new monthly quantity input is introduced.

## Target UI/backend boundary

The company registration screen remains unchanged. Individual settings use one
addable allowance list, retaining old slot values internally without converting
them into duplicate unit items. Checkout exposes only current company day/hour
allowances; month items remain in monthly payroll and are not selectable there.

The names-only reader is owned by `common_names_b12`. Its current-registration
response supplies stable origin/id, legacy generation or common registration
version, name and unit, never an employee-supplied amount.

Proposed worker payload field:

```json
{"company_allowance_selections":{"contract_version":1,"items":[{"origin":"company_legacy","id":"UUID","generation":1,"registration_version":1,"name_snapshot":"registered name","unit":"day"}]}}
```

`company_legacy` and `company_common` are the only origins. Month is rejected.
An omitted field preserves an existing draft's metadata; explicit `items:[]`
represents a user clearing the selection. Old signed/raw labels are not adopted
into identities merely by matching their text. Amount/quantity fields are not
accepted from this payload. Capability discovery must succeed before a client
sends this field; old writers must not silently discard it and report success.

## Server capture and financial compatibility

The draft writer must validate the same report/company/worker scope using the
existing authorization and draft/approved-edit rules. At the existing normal
report finalization, the server rechecks registration version, identity generation,
unit and name, then captures the company's registered rate/section into a receipt.
Stale/retired/cross-company/ambiguous identities reject atomically. Price is not
trusted from a client, nor looked up from a changed current name during later
payroll rendering.

Day receipts count once per employee/work date and company item, across visits,
retries and sites. Hour receipts require an explicit authoritative work-hours
basis; absent evidence blocks the affected payroll calculation. Existing monthly
calculation is unchanged. Payroll detail must retain the selected registered name
and quantity/rate/amount used by the same calculation. Existing individual/frozen
values must not be rewritten to make the new source appear connected.

Selective compatibility is essential: removing a legacy amount from effective
settings for the whole month would incorrectly erase older ordinary attendance.
Old and new sources must be partitioned by confirmed receipt/date, while mixed or
ambiguous same-day sources block instead of being double-counted. The existing
detail-sync path must use that same partition, not a separate name total.

## Additional bounded writer prerequisites

Both public draft writers retain a three-allowance guard:

- `save_daily_report_draft(uuid,uuid,date,text,jsonb)`:
  `06bc60d5393d1b7e75a69767a72a0e6f`
- `save_daily_report_destination_draft(uuid,uuid,uuid,date,text,jsonb)`:
  `b22883565c0913ffb4d7695ca89e8da7`

The new versioned payload needs its own bounded validation, rather than widening
the old untyped API without a company-defined identity check.

Route visit wrappers delegate to
`private.route_visit_report_command(...)` (`c2558d7c24f09f4998200b2410ec681e`),
whose stored worker JSON already preserves additional explicit client keys and
echoes them. `private.save_route_visit_report_signature(...)`
(`b543f41579f541edc51fb13e94bdebf9`) marks the visit completed but does not itself
write attendance/payroll. Visit metadata must therefore survive the final route
checkout aggregation before claiming end-to-end payroll reflection.

## Validation status

The low-level receipt aggregate passed 14 isolated PostgreSQL cases in PR 1352
(head `bb876c6c65e0729357ca32b508ac4de4898e278c`). This is component proof only.

A separate source-bound integration candidate now prepares both normal draft
writers, two-signature capture, private immutable price receipts, attendance
pointers, selective legacy/new payroll resolution and matching detail display.
The public report metadata contains identities and labels only; captured prices
remain in the owner-only private receipt store. Omitted metadata preserves a
saved draft; an explicit empty selection clears it. Version and company/worker
checks run again at confirmation, and stale prices are rejected atomically.

The integration runner uses pinned observed function bodies with explicitly
synthetic authorization, tax and surrounding tables. It checks old individual
rates versus newly selected company rates, multi-site/day deduplication, separate
workers, retries, renamed/versioned snapshots, manual/finalized preservation,
private price access and direct metadata-write rejection. Python generation and
Node syntax passed locally. Its Native execution has not yet run; source-bound
integration success and real Auth/RLS completeness are not claimed.

Hour items remain explicitly blocked without an authoritative actual-work-hours
source. Route visits do not acquire new financial semantics. No production
activation, installation, data conversion or existing signed-record rewrite has
been performed. The review unit must not be deployed solely on the component
proof or syntax checks.
