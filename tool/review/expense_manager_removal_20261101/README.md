# Expense manager removal: isolated review candidate

**Not deployable. Default OFF. No production installer or activation command.**

The candidate addresses manager deletion after registration, approval or rejection. It uses the stored original `expense_claims.created_by` Auth ID as the notification recipient; it never resolves the recipient from a current worker link, display name or phone number. Notice storage and removal history are in one transaction. Opening a notice is read-only.

## Implemented fixture contract

- Selected owner/admin/manager only, explicit company, authoritative Auth user and live SID, exact revision, immutable command and payload. Existing own-claim separation applies when there is more than one approver.
- New operations require the dedicated private switch ON. It is initially OFF with no client activation API. Existing results remain inspectable after OFF and by the same currently authorized actor under a new live SID. A new SID cannot start a mutation captured under an old SID.
- Unconsumed claims use the existing `withdrawn` transition and existing cost guards. Existing draft-refresh triggers may run; they are neither bypassed nor rewritten.
- Consumed claims retain their claim row, settlement data, original receipt path and financial consumption unchanged. The result says `finalized_original_retained` and `correction_required:true`. This is **not** cancellation of an invoice, payment certificate or payroll amount.
- The receipt records original claim/settlement snapshots and the exact notification ID. Same-command retries produce the same result, not another notice. SQL notification failure rolls back the removal as well.
- New guards reject subsequent legacy claim/settlement mutation and new consumption of a removed claim under another document or purpose. Existing consumption guards and financial function bodies remain unchanged.
- Same-OID reader edits are exact-source guarded: legacy manager workspaces omit removed rows; personal history retains an explicit `manager_deleted` marker rather than pretending the applicant withdrew it. No alias copy or ACL widening is used.

## Mandatory unresolved integration

`private.expense_document_claims(text,uuid,uuid,date)` at fixed source `48d345ddd52f5cca0166c2d6545a07ecb08fe8d4`, `supabase/migrations/20261010141814_expense_document_details.sql`, is intentionally unchanged. It supplies detail snapshots and may also supply live rendering for legacy documents without snapshots. The fixture deliberately observes that this unchanged reader still returns a consumed removed claim.

The Mac payroll owner must bind a **new-draft-only** removal policy without changing saved snapshots, historical originals or old live-original appearance. New reimbursement/compensation, unconfirmed payroll recalculation and a later financial correction remain unqualified. The new consumption guard is a safety barrier, not a completed calculation handoff. Until this contract and legacy-client rollout are reviewed, the feature must remain OFF and **deployable:false**.

The candidate has no UI or notification-router integration yet. It must not be shipped as a functioning delete button. The later UI must distinguish manager removal from applicant withdrawal, show the finalized-original warning before confirmation, and bind its pending journal to the current SID/company/actor. It must query a missing result as unknown rather than blindly resending under a new login.

## Verification boundaries

The Native fixture uses the existing expense foundation and actual review/cost guards. Its JWT, users and session rows are synthetic; this is not real GoTrue, deployed RLS, Storage, push delivery or device evidence. It does not read or modify production data. The SQL candidate rejects any database except its disposable fixture database. The launcher accepts no database URL and rejects inherited connection redirection variables.

Native validation is pending until an exact completed CI log is recorded. Local environment-target rejection tests can run independently without PostgreSQL. Do not interpret source completion or a stored notification as actual delivery or overall accounting deletion completion.
