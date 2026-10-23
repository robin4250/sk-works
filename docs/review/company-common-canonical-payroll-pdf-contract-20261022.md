# Actual SQL payroll row → client mapper → payslip consumer contract

Synthetic disposable fixture only. No production read, financial modification, Dart execution, print action or share action was performed by this export. Backend SQL units remain unchanged. This supplements the existing six-key `company_common_canonical_publication_contract3.json`; that existing contract is not restructured.

## Producer and safe export

`tool/verify_company_common_canonical_publisher.mjs` accepts a second, separate output environment variable, `SKO_CANONICAL_PAYROLL_FLOW_OUTPUT=/absolute/new/path/payroll-flow.json`. The private fixture input environment and either public export environment are mutually exclusive: refusal happens before the database module is imported or its database constructed. Absolute and distinct paths are required before database creation. The new payroll output is created exclusively (`wx`) and cannot overwrite another artifact.

For PGlite, run the existing fixture with the locked absolute `@electric-sql/pglite/dist/index.js` module path. For native PG17, use the existing owned loopback `/sko_common_legacy_fixture` adapter and `pg/lib/index.js` argument followed by `postgres`; no hosted endpoint is accepted. Both exports can be requested in one fixture execution with different paths. Either output enables the same fixed synthetic identity/payroll UUID allocator. The existing publication fixture and all its assertions still run before the payroll file is written.

The captured point is immediately after the first successful revision-3 publication and its exact receipt, before later selection-edit, other-payroll-type or historical-boundary tests. The producer separately verifies selection remove→gross minus 1,200→selection restore→gross restored later in the same fixture; it does not mutate the captured initial payload to fabricate that result.

`test/fixtures/company_common_canonical_payroll_flow.json` contains an actual successful PGlite run. Names, rates, input settings, attendance IDs and generated UUID namespaces are synthetic fixed fixture values; UUIDs outside the fixed owner/company/worker and 8/9 fixture namespaces are refused. Relative current-month dates and database-generated timestamps/receipt hashes can differ on regeneration. Do not compare complete JSON byte identity across separate database runs. No field is copied from a live project or a private-rate fixture.

## Export fields

| Field | Origin / consumer |
| --- | --- |
| `saved_statement` | Direct `to_jsonb(s)` of the target `public.payroll_statements` row after successful publication. Includes untouched original gross/deductions/net, saved detail, workflow and revision. |
| `client_rpc_row` | Direct `to_jsonb(r)` of the target row from the actual `public.my_payroll_statement_rows_with_adjustments()` call under the owner/employee's fixture authenticated actor. This is the mapper input; it is not a manually reconstructed server response. |
| `source_settings` | Direct target `worker_payroll_settings` row, proving the original same-rate individual legacy slot remains 1,200 while calculation overlays prevent duplication. |
| `source_attendance` | Actual target-month attendance rows for this worker. One selected day, no unrelated worker rows. |
| `publication` | Direct canonical publication version-1 row and its actual immutable item snapshot. |
| `expected` | Explicit synthetic test oracle: base 10,000; shared legacy earning 1,200; gross 11,200; deductions 0; net 11,200. Never used to construct or repair actual server payload fields. |

The producer asserts saved/client equality for ID, period boundaries and three totals, and exact saved/client equality of unit resolution, configured earnings and deductions. It asserts two shared items: `Synthetic travel` rate 1,200 × selected distinct day quantity 1 = 1,200; `Synthetic work` rate 800 × quantity 0 = 0. The first is inherited once, while the original individual slot remains saved at 1,200. There are no adjustment rows in this fixture, so the employee RPC's adjustment-aware totals must equal the saved statement totals.

The fixture contains synthetic bank labels from the existing payroll fixture (`SELF BANK`, etc.); these are test values, not real bank data. Preserve `client_rpc_row.detail` exactly for the consumer: the RPC enriches it with workflow/revision/payment/bank metadata that raw storage rows do not necessarily expose identically.

## Flutter/PDF consumer connection

Use the product mapper, not a test-only manual `PayrollStatementRecord` constructor:

`payrollStatementFromRow(Map<String, dynamic>.from(flow['client_rpc_row']), null)`

The mapper is in `lib/features/payroll/payroll_statement_repository.dart`. Passing null review exercises the real fallback to saved row/detail state. Assert record gross/deductions/net are 11,200/0/11,200 and that common item identity, quantity and amount survive in `record.detail['unit_resolution']`.

Then pass that same record to `PayrollPdfService.buildPdf` in `lib/features/payroll/payroll_pdf_service.dart`, using the existing test font/expense stubs to avoid network dependencies. Assert actual PDF text/amount extraction includes `Synthetic travel` once with 1,200, the base earning once with 10,000, and gross/net 11,200. Zero `Synthetic work` must not appear as a positive 800 earning. Checking only `buildTextSnapshot` proves summary text, not PDF line rendering.

The product print helper uses `buildPdf(statement)` through `Printing.layoutPdf`. The preview page also caches rendered bytes and supplies them to preview/print/share. Consumer tests should verify those paths receive the same mapped record/rendered bytes and do not independently recompute shared allowances, reload a different month, or duplicate the same-rate individual item. A service PDF test alone does not prove native iPhone printing/sharing; keep those boundaries distinct.

## Evidence and remaining checks

PGlite fixture generation passes all existing canonical publisher assertions plus the saved-row/actual-RPC/item/total assertions above. A negative invocation with private-input and payroll-output set, and an intentionally unavailable database-module path, fails with the explicit private-export error before attempting that import/database creation. Node syntax and whitespace checks pass. The generated file is 12,850 bytes in the recorded run.

Native PG17 export regeneration, Flutter mapper/PDF consumer, print/share wiring and real iPhone review remain separate checks. Do not describe this JSON export as proof of completed UI/PDF output or production shared-allowance activation.
