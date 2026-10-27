# Company lock: writer-inventory starting point

Review-only, source analysis. No deployment, grants or live database access. Source checkout `3b08b17b9666e764a628e77e67b8f0005b668ca5`; this is not proof of the current production catalog. Latest main and actual pg_catalog, functions, triggers, policies and grants must be checked before any implementation.

## Confirmed existing app entry points

The following client paths directly issue table writes and do not invoke this prototype's advisory lock:

- `lib/features/attendance/attendance_cloud_repository.dart`: insert and delete on `attendance_entries`.
- `lib/features/invoices/invoice_cloud_repository.dart`: insert on `invoices`.
- `lib/features/sites/site_cloud_repository.dart`: update on `sites`.

These are concrete paths to investigate, not proof that a particular user's current role is granted each write. Advisory locks added only to a new approval RPC would not make those old clients participate. The negative control in `verify.mjs` demonstrates the bypass in the synthetic database. Do not deploy or switch off the existing lock.

## Source search scope

For the 28 tables named in the existing correction-preview revalidation lock list, a text-only search of `supabase/migrations/*.sql` looked for INSERT INTO, UPDATE, DELETE FROM or MERGE INTO followed by a qualified or unqualified table name. Examples of matching migration files:

- Attendance writes: `20260929210000_add_attendance_correction_requests.sql`, `20261008042058_fix_managed_attendance_overnight_chronology.sql`, `20261009180420_payroll_normal_api_scope_order.sql`.
- Report worker writes: `20261008162618_attach_vehicle_meter_to_report.sql`, `20261008042058_fix_managed_attendance_overnight_chronology.sql`, `20261001232457_add_daily_report_vehicle_usage_rpc.sql`.
- Invoice writes: `20261006104325_preserve_invoice_auto_refresh.sql`, `20261007221757_invoice_stamp_policy_and_approval_history.sql`, `20261012142138_expense_document_original_costs.sql`.
- Expense writes: `20261012170840_expense_atomic_review_flow.sql`, `20261010140111_expense_review_allocation.sql`, `20261010044054_expense_personal_submission.sql`.
- Route evidence writes: `20261012053842_route_customer_billing_connection.sql`, `20261008204012_route_journey_capture_staged.sql`, `20261010222139_route_manual_visit_capture.sql`, `20261010132957_route_journey_visit_lifecycle.sql`, `20261011121738_route_visit_report_documents.sql`.

This is a triage list only. Text matching includes obsolete/replaced migrations and may match comments; it misses dynamic SQL, trigger side effects, schema-qualified/quoted variants, direct REST, service jobs, cascades, functions outside migrations, and other source dependencies. A zero match is never evidence that a table cannot be written. Do not use this list as a complete allowlist or authorization decision.

## Requirements before considering replacement

For each actual deployed source, enumerate current writers and indirect effects from catalog and application entry points; identify server-trusted company scope, including absent or changed company IDs and parent lookup. Ensure every path acquires the same lock before row locks/writes, with deterministic ordering for multi-company changes. BEFORE ROW triggers alone can acquire locks too late; cascade, TRUNCATE, administrators, direct API and security-definer paths need explicit coverage. Preserve existing RLS and caller permissions.

Use disposable PostgreSQL and real GoTrue/PostgREST with actual current function bodies to test same-company insert/update/delete, company reassignment, other-company progress, multi-company ordering, rollback, timeout, deadlock, access revocation, fingerprint recheck and old clients. Prove lock order across the other existing invoice/LINE and attendance workflows. Unknown company scope and unverified writers must fail closed, without introducing new production restrictions by inference. Review performance and a reversible rollout separately. Keep the synthetic non-participant bypass as a negative control.
