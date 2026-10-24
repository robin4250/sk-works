# Existing expense finalizer: invoice revision compatibility

This independent review-only candidate continues PR #1347. It is not a production
migration or an activation instruction. Main and live financial rows are untouched.

The original Native run at head `682d60ab2eed77306ec7dbe86abe0470de0ff761`,
job `120782142751`, matched all observed routine sources and then failed during
invoice approval: `record "new" has no field "revision"`. Both the observed
catalog and the fixture have a revision column on payment certificates, while
invoices have none. Adding a fictional invoice column would conceal this defect.

## Minimal change

Require original finalizer source MD5 `22ff4377666ec56ccc4b261cf380e9c0`, then
replace exactly two payment-only `new.revision` references with
`(row_data->>'revision')::integer`. The function already constructs `row_data`
and uses this representation for inserting document revisions. This avoids
PostgreSQL resolving a nonexistent invoice record field while preparing a shared
IF expression; it does not depend on Boolean short circuit to resolve row shape.

The payment envelope constructor still refuses a null revision. A mismatched
payment revision still differs from the frozen envelope and captured revision.
No default revision, relaxed check, sign conversion or amount rewrite is added.
The expected patched source MD5 is `26d214245ad95159dab04059710840bd`.
The review SQL asserts that every pg_proc attribute except prosrc is unchanged,
including owner, ACL, security mode, volatility and search path. A differing
source or anchor count refuses the patch. No table or trigger is added by SQL.

## Independent Native proof

The new harness is derived from PR #1347's corrected fixture and retains all 17
public-source Git pins and 21 observed routine body pins. It first runs the old
function unchanged, expects the precise missing-field exception and compares the
full captured financial/approval/consent state for rollback. It then applies the
SHA256-pinned review candidate only to that disposable database and runs the
original invoice +1000, one-consumption/retry, late-receipt rollback, finalization
snapshot/rollback, route refusal and old -1000 preservation assertions.

Additional payment cases finalize a new synthetic -1000 certificate using the
same finalizer, reject null/mismatched revisions and verify one consumption after
retry. The original saved payment and its ledger remain unchanged. All other
routine source pins remain original; only the finalizer pin changes explicitly
after the candidate is applied. Synthetic authorization is declared; this does
not replace real-GoTrue or production role testing.

Node syntax and whitespace checks are local. Native execution is pending; neither
the prior failing harness nor the new full-flow assertions are claimed successful
until the actual CI result exists. This branch stacks on PR #1347 and changes only
new review/test files. Root review and a separate bounded deployment process are
required before any production application.
