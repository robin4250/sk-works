# Additional expense amount connection: isolated preparation

This work continues the preserved expense-cost-connection checkout. It is not a
production migration and must remain a Draft until PostgreSQL concurrency,
current production definition comparison and PDF/UI verification are complete.

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

Remaining: real PostgreSQL races; complete document/PDF and application help
integration; approved forward migration generated with the Supabase CLI;
production definition/data preservation comparison and deployment; Release
device verification. No production schema or data has been changed by this PR.
