# Approval result recovery — review only, default OFF

The previous page-only uncertain-operation map disappeared on close/restart. A
negative package-detail read cannot establish that an earlier HTTP request has
not yet committed. The new identifier-only local journal is written before any
approval request, scoped to the captured actor/company/package; a failed journal
write sends no approval. Opening another page/session retains quarantine. It
stores no bearer, price, body, seal, recipient name or signature.

`approve_operation` and the explicit `reconcile_approval` barrier serialize on a
key derived from the saved preview's package, current authorized company/actor
and immutable preview ID. One preview has one immutable operation; the exact
request ID is checked in every path. An accepted record cannot become cancelled.
If a request has not been accepted, the barrier records a permanent cancellation
before releasing the lock, so that same delayed request can never approve later.
A prior operation still committing must finish before reconciliation proceeds.
Existing direct private consent code is not made public; the fixed Edge approval
command uses the new wrapper. Native two-connection checks observe both the
approval-before-readback and cancellation-before-late-approval lock waits.

This barrier is an explicit user action (`保存状態を確認`), not an automatic
retry. The current live actor/exact company membership remains required, even
with the master OFF. A fresh SID can read its same actor's historical result or
cancel that exact unaccepted request, but cannot reuse old-session seal consent.
Only an exact accepted/cancelled server response removes the journal entry;
network errors, a malformed response and negative package reads retain it.
Reconciliation COMMIT response loss is also unknown and the same identifiers
remain available for another explicit lookup.

The received immutable nonfinancial site projection is now returned only in the
management-authorized detail and displayed with the order. It is not passed to
the general footer as a document body, financial note, PDF URL or price.

## Remaining work

- Reply processing after a changed SID still refuses the old immutable
  session-bound job. A separately reviewed explicit re-confirmation and
  append-only recovery authority is needed; this patch does not relax it.
- Unknown reply-processing state itself needs durable recovery beyond the
  approval journal, including status/receipt reconciliation.
- Outgoing creation/registered supplier selection and site/company entrances
  remain unfinished.
- New-package refusal and its notification remain unfinished. Do not release
  the old legacy response guard for `false` as a shortcut.
- Combined Edge staging/deployment, production guards/approval, feature ON and
  actual iPhone checks remain separate. This SQL is not a production migration.
