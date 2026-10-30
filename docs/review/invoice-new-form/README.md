# Invoice acceptance form selection — actual output follow-up

The 2026-10-30 owner report is **an acceptance is present, but it uses the old
format**. Do not describe this report as a preview-open failure or a missing
appendix. The owner's exact attachment state has not been read.

The current source has two distinct, intentional paths:

* A saved attachment is returned before current template/default/capability
  handling. Its original payload, schema, terms and seal must remain unchanged.
* A new, unlocked appendix receives schema 2 only when the authorized workspace
  advertises `form_fields_schema_version: 2`. Without that server capability the
  adopted original form uses frozen schema 1. A new standalone local form does
  not prove the attached document's server save capability exists.

Consequently an app update alone cannot safely promise the new attached form.
Do not set a fake capability, migrate saved originals on read, force an
explicitly disabled/null appendix, or route persisted input around validation.

The existing guarded server sources are reused, not reimplemented:

1. Confirm current production catalog/source/owner/ACL against the reviewed
   predecessor; keep unknown predecessors blocked. Preserve complete originals
   and function-only restoration material before proposing application.
2. Review the existing confirmed-terms prerequisite, typed form save guard in
   `docs/review/trade-document-form-input/server-save.sql.review-only`, and v2
   extension in `docs/review/trade-document-month-end/server-upgrade.sql.review-only`.
   PR 1633 also rehearses master-context → v1 → v2 order. Its successful fixture
   is not permission to install these modules or to enable the new master flag.
3. Present the exact production scope, impact, expected source/attribute checks,
   stop/restore conditions and owner approval together. Production HOLD remains.
4. After approved installation, confirm a new unlocked workspace returns schema
   2 and registered contacts. Save/read back a new appendix by the existing
   canonical save/CAS path; no historical attachment rows are rewritten.
5. Build the normal invoice output and inspect all invoice detail pages,
   acceptance front and complete legal terms. Confirm the selected invoice and
   current version on the owner's iPhone, using owner-operated steps.

`invoice_acceptance_schema_pdf_test.dart` covers resolver → real invoice builder
for missing capability, current capability and a saved legacy original. It
preserves source totals, null unspecified unit price, registered FAX and the
saved payload. It deliberately does not pretend to exercise a live Supabase
RPC, a native printer, a signed iPhone or a production database. Its PDF outputs
allow the three cases to be distinguished without reading customer data.
