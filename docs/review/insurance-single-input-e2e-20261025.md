# Single input → existing payroll calculation → PDF proof

Base reviewed source: PR #1366 `20fe72ea7950a8adfb0193250719086167bd4557`.
This change introduces test/tool/workflow files only. The insurance UI, existing
calculator, rates, RPC implementations and PDF layouts are not modified.

## Existing evidence reused

`tool/payroll_scope_fixture_setup.mjs`, the existing tax-connection migrations,
PG17 guarded runtime, company-rate save RPC and `save_worker_payroll_tax_conditions`
are reused. Existing UI tests already verify missing/zero/error distinction,
CAS, read failure and manual overrides. Existing PDF test extraction coordinates
are reused, rather than inventing a replacement payroll renderer.

## New missing bridge

1. Prepare an empty disposable PostgreSQL 17 fixture using the existing setup.
   Save explicitly synthetic company rates (5% employee health and 9.15% pension)
   via the existing company-rate RPC. Produce a real condition-reader response
   with no registered employee condition and preserve the before statement.
2. Drive the actual `PayrollTaxConditionsPage` with that read response. Explicitly
   enter one average-income amount 700,000, select the existing fixed income-tax
   method, confirm enrollment/conditions and confirm the existing save dialog.
   Capture the exact UI-produced RPC arguments; no handwritten health/pension
   standard bases are substituted in the bridge.
3. Apply those exact captured arguments through the existing SQL save RPC. Check
   saved conditions and actual statement: health base 710,000, pension base
   650,000; employee premiums 35,500 and 59,475; fixed income tax 5,000, resident
   tax 12,000, gross 700,000, deductions 111,975, net 588,025. Idempotent retry
   retains version and statement revision. Old aggregate insurance is not added.
4. Feed that actual saved row to `PayrollPdfService`, preserve its input detail,
   then extract the real PDF. Reconcile earning rows, deduction rows, deduction
   total and net, including both insurance names and amounts. Preserve PDF/PNG
   and intermediate synthetic JSON together.

These rates/amounts/IDs are synthetic fixture data only. Authorization predicates
are the existing fixture's synthetic actor claims, not a fresh production JWT
claim. UI RPC transport is an injected read/save bridge; actual PostgREST/phone
session behavior is not proven. The fixture uses the legacy compatible condition
value shape, without the separately deployed income-reference metadata extension;
that extension's roundtrip/auth tests remain the earlier independent evidence.

No production endpoint/credential is accepted. No production amount is inserted.
No local Flutter execution; remote CI must finish before this proof is called
successful. PDF visual balance on the user's iPhone remains separate.

## Concrete device acceptance still needed

- Update to the Release containing PR #1366; existing build13 does not include
  this follow-up one-input/entry overhaul.
- Open the actual employee's deductions → `保険料を設定`, confirm actual enrollment,
  enter an actual initial average, and choose the intended effective start month.
  Confirm company rates are registered for the target insurance/payroll month.
- Confirm derived standard-remuneration values against the applicable notice;
  use the existing notice override if the actual determined amounts differ.
  The grade lookup does not make statutory acquisition/regular/revision decisions.
- Confirm nursing birth date and other actual conditions where relevant; preserve
  intended income-tax method. Resident tax uses its own existing saved setting.
- Confirm save, reload same employee/month, inspect the generated salary detail
  and PDF totals. No repeated monthly condition registration is required: the
  latest effective condition is used until changed; monthly rate applicability
  and source payroll data still need to exist.


## Real I/O boundary correction

The widget bridge reads its prepared JSON and writes its captured payload with
`WidgetTester.runAsync`, outside the widget test's FakeAsync zone. Widget
interaction, assertions and payload verification remain in the normal tester
zone; no timeout was extended. The separate PDF verification uses ordinary
`test`, not `testWidgets`; its font/JSON/PDF file operations and PyMuPDF process
therefore already execute in the real async zone, consistent with the existing
PDF proof tests reused here. No runtime or workflow changes.
