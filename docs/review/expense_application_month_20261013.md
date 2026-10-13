# Expense settlement uses application month

New cash/payroll settlement approvals use the Japan civil month of the original
`private.expense_claims.submitted_at` timestamp. The date is NOT NULL, defaults
to `clock_timestamp()` on submission, and applicant edits preserve it. The dialog
shows this month and asks only for cash or payroll; the server rejects new
commands with any other month.

The existing five-argument RPC and immutable command encoding are retained.
Replay of an existing receipt precedes the new month validation, preserving
pending successful historical commands exactly. No existing claim, choice,
receipt, finalized document, calculation or history is backfilled. The original
expense date remains the invoice/cost-recovery month. Payroll calculation and
statement generation remain owned by the Mac implementation.

The guarded forward migration checks the deployed approval body hash and
inserts one validation into that existing function, preserving its privilege,
search path, lock order, review authorization and cost allocation guards.
Tests cover cash/payroll, Tokyo UTC month/year boundaries, applicant date edits,
wrong-month rollback, fixed receipt retries and unchanged legacy rows/ACLs.
Production deployment and Release device verification remain pending.
