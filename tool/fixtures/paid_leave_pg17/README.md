# Paid leave PostgreSQL 17 preflight fixture

This is a disposable, synthetic-data test. Never apply these files to Supabase.
The harness starts only against an empty local database named
`sko_paid_leave_fixture`, with the fixed fixture credential and PostgreSQL 17.
The URL guard rejects remote hosts, other databases, query parameters (including
host/socket overrides), other ports and arbitrary credentials before import or connect.

`old_functions.sql` contains code-only definitions read from the current server
on 2026-10-09. It contains no user rows, company/person UUID literals, URLs, emails,
credentials, bank data or connection settings. The metadata records function-code
MD5 and ACL only. Each loaded definition must match its captured code MD5 before
the rollout test starts. Schema/data prerequisites come from the existing
disposable payroll fixtures; this does not reproduce the full production schema,
RLS, scheduler infrastructure, or every business case.

The existing PGlite harness and assertions are unchanged. This separate real
PostgreSQL 17 job additionally checks:

- New DDL alone preserves every saved statement row and existing trigger OID,
  definition and enabled state; the capability immediately returns 1.
- Calling the current-month scheduler updates the automatic draft with leave
  wages, while manual draft, automatic finalized, manual finalized and previous
  month draft rows remain byte-for-byte equivalent as JSON.
- A normal paid-leave approval transition uses the existing trigger to remove
  and recreate the current automatic leave-only draft; protected rows stay equal.
- The old paid-leave warning is present before the migration and absent for the
  valid configured wage afterwards. Other warning conditions are not removed.
- Restoring saved code and ACL in a transaction removes the new capability/helper
  and preserves triggers and data. Default NULL ACL is restored to equivalent
  PUBLIC EXECUTE semantics; PostgreSQL may represent this as an explicit ACL.
- DDL restoration leaves the new draft amount in place, demonstrating that
  function rollback and data restoration are separate.
- Existing named-financial and paid-leave wage assertions also run on real PG17.

Normal payroll-setting changes are a separate existing behavior: the captured
`settings_refresh_payroll` visits all stored/attendance periods. This preflight
does not assert that changing a wage setting freezes all previous automatic
drafts. The unchanged previous-month assertion applies to the current-month
scheduler and current-period leave transition used here. Manual/finalized
protection remains required. No production setting is changed by this test.

Run on the workflow's disposable PostgreSQL service with a pinned `pg@8.16.3`
client. Real production snapshots or secrets must never be passed to CI. A PG17
CI result is not production migration approval, a protected-data backup,
iPhone validation, or TestFlight publication.

## Composition with the deployed company-seal contract

The harness loads both exact seal migrations before the paid-leave migration.
Existing synthetic payroll rows were saved before the seal triggers, so their
missing snapshot must remain missing during scheduler recalculation. After a
leave approval recreates a current statement, the new genuine-Reisho snapshot
must survive company name/style changes, attendance-detail synchronization,
subsequent scheduler runs, and paid-leave DDL recovery. All three document seal
triggers and the helper/metadata definition hashes and ACL are preserved.

Invoice, payment-certificate, agreement generators and the metadata reader use
minimal synthetic patch-anchor stubs here. This tests execution of the exact
seal migration patches and payroll composition; it does not prove full live
reader equivalence, company authorization/RLS, or every non-payroll generator.
The other document suites and read-only current production-definition review
remain separate prerequisites. The old paid-leave code fixture must not be used
to roll back post-seal functions or triggers. Current recovery needs a new
protected snapshot taken after the seal deployment, not the earlier backup.
