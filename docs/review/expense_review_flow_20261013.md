# Expense review confirmation and receipt camera

The manager review dialog keeps all five steps local: decision, actual burden
category/company, one of four explicit settlement methods, memo, final review.
Only Confirm creates a fixed command. Rejection skips allocation and settlement.
The final RPC locks the original company/settings/claim, validates the actual
selected company and original revision, and writes the claim, settlement choice
and immutable confirmation receipt in one transaction. No preliminary approval
is committed. Ordinary assigned reviewers keep their legacy approval authority.

`other` is an explicit burden category without a company; `paid` and `advance`
are distinct stored methods, never aliases for cash or payroll. Reimbursement
uses the original Japan application month. Invoice original-cost recovery still
uses the incurred month and external burden category. Payroll calculation and
statement generation are unchanged. The Mac payroll consumer must select only
current `payroll` choices for reimbursement; the old expense detail-only reader
continues to include the applicant's expense history and is not a payroll amount
calculation contract.

Manager edits are versioned immutable receipts, return the claim to pending and
preserve the original submission timestamp and photograph. Frozen monetary
consumptions prevent editing, rejection, amount changes or reassignment. Existing
receipt APIs and their successful retry results are preserved.

The application offers camera and photo-library selection and a local preview.
A selected JPEG/PNG is copied to application support storage before submitting;
the fixed pending submission stores that local path, SHA-256, size and MIME.
Upload preparation reserves the canonical company/actor/claim object path.
The private bucket denies generic policy leakage, replacement and deletion.
A submission links its verified object in the same database transaction as the
original fixed-ID claim. Upload or RPC failures retain the input and exact photo
for retries. The client verifies uploaded bytes before attaching. No photograph
is sent until the user submits. Existing Japanese iOS camera/photo privacy
contracts in prepare_ios.sh are retained.

PGlite covers four methods, other, explicit company authorization, failed-confirm
rollback, fixed receipt replay, invoice original amounts and frozen protection;
receipt tests cover reservations, failed upload without claim write, exact attach
retry, selected-reviewer access, generic-policy isolation and immutability. CI
repeats these on PostgreSQL 17 with concurrent final-confirmation calls. Storage
catalog tests use a synthetic Storage schema, not an end-to-end live Storage
upload. Flutter tests cover 320px / enlarged text, approval and rejection flows,
back/cancel behavior, local camera preview and retry preservation.

Production migrations and a Release device camera/upload test remain pending.
