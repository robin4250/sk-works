# Invoice child party defaults — review only

No production execution or migration history entry is performed by these files.
The existing representative profile storage is reused, never reinstalled.

The exact source body MD5 before is `a24d433cb49462869a06d51081562a43`; after is
`ebcc70935938482054943560390038b2`. Apply and restore compare all `pg_proc`
attributes other than `prosrc` within the same transaction. Restore accepts only
the exact after hash, removes only this addition, and verifies the exact before
hash. Neither direction updates application tables or saved appendix snapshots.

Root must remain the sole function DDL writer. A source hash guard followed by
CREATE OR REPLACE is not a compare-and-swap guarantee against another DDL writer.

Run the identical `invoice_party_representatives_verify.read-only.sql` immediately
before and after and retain the results privately. It outputs routine hashes and
catalog attributes, and whole-table row counts and ordered SHA256 row digests for
11 relevant relations. It outputs no actual row values or company/worker IDs.
The observations are separate repeatable-read snapshots; ordinary concurrent app
writes may change table hashes and must be investigated, never overwritten.

For isolated reproduction, run `node tool/verify_invoice_party_source.mjs` with
an absolute path to the disposable PGlite adapter as its next argument. It builds
the exact baseline from the existing public monthly-attachment migration and
the public tax/directory/own-representative candidates. It also executes the one-JSON read-only observer and checks all table hashes unchanged
across apply, with only the expected source hash changing. No private body file,
company IDs, credentials, production rows or downloaded private receipt is needed.
The synthetic actor IDs in the fixture do not identify actual accounts.

The locally run 42 checks cover scoped customer mapping, duplicate/wrong-role/
foreign-company/missing/invalid mappings, saved-child preservation, parent-only
locks, invoice/finance/source-fingerprint preservation, function metadata, access
guard rejection, restore/reapply and unchanged payment behavior. These are
postgres-role PGlite tests with authorization stubs, not real JWT, RLS, native
Postgres concurrency, UI, actual PDF or production verification.

In the public monthly-attachment implementation, source reads lock the parent
FOR SHARE; save calls the source and then locks an existing child FOR UPDATE.
That is not a parent FOR UPDATE serialization boundary. Concurrent first save
and read-only generation can observe different child availability; this candidate
does not modify those save semantics. A parent-only locked invoice with no saved
child may receive registered defaults for a newly generated child; its original
invoice rows, amounts, approval state and seal snapshot are not rewritten.

The dedicated PR-only workflow reuses the existing pinned pg/PGlite dependencies
and loopback-only empty-database PG17 adapter. Native PG17 is pending CI; no
local native database, real JWT or production proof is claimed.
