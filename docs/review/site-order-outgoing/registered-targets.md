# Registered target reader (source candidate only)

One new owner-only function in the existing outgoing private namespace returns
only registered directory `id` and formal `name`, in UUID cursor pages of at
most 50. It reuses the exact standalone access helper with current live session,
company and owner/admin/manager admission and the master switch. The requested
site must belong to that company. Only linked subcontractor/both registrations
with exactly one accepted formal company connection are eligible. Ambiguous
connections and registered/formal name drift reject rather than silently
returning a misleading empty list. Unlinked/customer/foreign registrations do
not become targets. Distinct registered IDs are not collapsed by company name.

There are no new tables, public wrappers, invoker grants, financial RPCs,
directory synchronization calls, original mutations, Auth or RLS edits. The
fixed Edge purpose uses its existing verified JWT and dedicated PostgreSQL
connection. `session_user=postgres` is required and the SQL function is called
directly by that owner connection; authenticated/anon/service-role invocation
is denied. This avoids assuming that an owner-only helper can be called through
an authenticated public invoker. Canonical C's required authenticated grant is
preserved exactly; no existing helper rights are removed.

The captured client repository validates actor, company, session, site, exact
result/entry fields, monotone cursors and duplicate IDs on every page. It never
returns partial results as a successful directory on unknown, malformed or
overlong traversal. The explicit 200-page safety bound fails rather than
truncating the list. A larger directory needs a paginated/search selector.
The normal RAM-input route calls this loader only after input confirmation,
then supplies the verified results to its dropdown. A failed/unknown read keeps
the user on the retained input and never shows a successful empty directory.
Explicit target injection is confined to the existing synthetic UI tests.

Native PostgreSQL and PGlite fixtures combine the existing C/access source and
new purpose. HTTP evidence uses actual pinned SDK ES256 verification, the fixed
handler and real SQL transactions, including foreign/worker/OFF denial and
closed connections. Native-generated HTTP receipts feed the actual Dart SDK
repository decoder in a dependent CI job. Surrounding Auth and directory data
are synthetic; this is not real GoTrue, full production baseline composition
or hosted deployment evidence. Existing original functions and reader-observed
directory/financial rows are compared before/after. Synthetic fixture setup
adds optional legacy names only to align its old nullable-name table with the
actual captured NOT NULL name contract; candidate SQL does not write them.

This module must be included in the complete guarded baseline/catalog proposal,
not independently applied as a production-ready installer. Production HOLD and
order OFF remain. The main entry, guarded preparation/preview/consent, actual
PDF/storage/send and terminal receipt reconciliation remain unconnected.
