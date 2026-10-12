# Additional expense amount connection: isolated preparation

This work continues the preserved expense-cost-connection checkout. The forward
migration was created using Supabase CLI 2.58.5 and has not been deployed. This
work remains a Draft until PostgreSQL concurrency and PDF/UI verification pass.
The ten current production prerequisite bodies were read without changing data;
the migration checks their hashes before changing any schema or function.

The staged SQL opts into cost recovery only through a new explicit allocation
command. Legacy approvals, settlement methods and old saved commands do not
authorize adding historical money. An expense contributes its original amount
once; it does not increase welfare or tax. Existing finalized and manually
edited documents remain protected. Payroll calculation is owned by the Mac
implementation and is not changed here.

The continued review reproduced a detail-page mismatch: a 999-yen selected
expense and a 688-yen unselected old expense both appeared in the document
details, although only 999 yen was charged. For new version-1 monetary
snapshots, the reader now matches charged IDs, revisions and original amounts
and checks their sum before returning details. Historical detail-only documents
retain their old reading contract. Account and document permission predicates
are preserved by a guarded patch of the existing reader.

Local PGlite 0.3.14 verifies the mismatch fix for drafts, finalized payment
details and inconsistent snapshot rejection, alongside original amount,
tax/welfare exclusion, fixed-command retries, destination changes, draft
preservation, legacy command compatibility and finalized-document protection.
The CI workflow repeats this synthetic isolated verification. Its foundation
models current invoice/payment functions but is not a complete production
schema, full RLS model or two-connection PostgreSQL race test.

The continued implementation passes monetary snapshots through the invoice and
payment readers, shows one original-expense line in the existing detail table,
and validates the charged second page against the first-page amount. Expense-only
payment documents do not fabricate work lines. The allocation dialog and help
describe the amount connection only when the server returns its capability.
Payroll reimbursement remains a separate Mac-owned connection.

The CI includes actual PostgreSQL 17 fixed-command allocation retries and
allocation/finalization locking, plus actual Flutter-generated invoice/payment
PDFs for work-plus-expense and expense-only cases. Text totals and rendered PNGs
are generated for inspection; local Flutter/PostgreSQL are unavailable.

Remaining: successful latest CI and visual inspection; production data/metadata
backup and preservation comparison; main integration and production deployment;
Release device verification. No production schema or data has been changed here.
