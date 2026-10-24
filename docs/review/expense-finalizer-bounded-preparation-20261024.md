# Shared expense finalizer: bounded installation preparation

This separate preparation owns only this document and the read-only catalog query.
It does not execute SQL, deploy, modify main/build 12, or change application data.
PR1348 Native testing has a separate owner.

## Known exact defect and change

The current private observation records `expense_cost_finalize()` source MD5
`22ff4377666ec56ccc4b261cf380e9c0`, invoice without `revision`, and payment
certificate with `revision`. The proposed SQL has two exact `new.revision`
anchors and replaces only those with `(row_data->>'revision')::integer`. Its
expected source MD5 is `26d214245ad95159dab04059710840bd`. The existing
`row_data:=to_jsonb(new)` already serves other type-specific fields. The patch
does not add a fictitious invoice column, change the cost sign, or alter the
ledger's existing `coalesce(...,1)` behavior.

The observed snapshot proves source and two column-presence facts only. It does
**not** bind owner/ACL/config, complete trigger closure, or event-trigger behavior.
The review SQL's before/after attribute equality preserves whatever attributes
exist at execution; it does not independently prove they were authorized.
Therefore PR1348's raw review SQL is not yet a production installer.

## Minimal safe path

1. Require successful exact-head PR1348 Native proof. Preserve original-source
   failure/atomic rollback evidence and corrected invoice/payment/retry/late
   failure checks. Do not relabel PR1347's known old-source failure as success.
2. Execute the sibling `preflight.read-only.sql` through the approved read-only
   project connection, save its complete private response, and strictly parse it.
   It captures no application/Auth rows. It binds target definition and full
   pg_proc attributes (including owner/ACL/security/search-path), effective ACL,
   eight financial relations' columns/constraints/RLS/policies, all their
   noninternal triggers and source, any additional target attachments, and DDL
   event-trigger source. Review unexpected table attachments or event triggers;
   stop rather than guessing their effects.
3. Generate a bounded installer from that reviewed exact checkpoint. Pin its
   digest and the exact candidate SQL digest; use a short transaction with
   explicit `lock_timeout` and `statement_timeout`. A transaction-scoped advisory
   lock serializes this helper family only, not arbitrary administrator DDL.
   Avoid claiming advisory locking alone prevents concurrent source replacement.
4. Quiesce source deployment for this single function. Lock the actual attached
   application tables in SHARE mode in deterministic OID order before fresh
   in-transaction checkpoint comparison. This blocks ordinary writes that can
   invoke the function while its source is replaced. It does not replace the
   function-DDL deployment mutex; detect any unexpected checkpoint drift and
   abort without retrying automatically. Do not lock system catalogs directly.
5. While writes are blocked, obtain before/after server-computed row-count and
   deterministic row-digest checkpoints of the reviewed write closure. Return
   only counts/digests, never raw financial values. At minimum this includes the
   eight relations captured here; the trigger/event-trigger review must establish
   whether more relations belong to the closure. Preserve all ordinary SQL
   constraints, triggers and RLS. No impersonated actor/JWT or bypass function
   execution is needed for a source-only patch.
6. Replace exactly the target body with the two substitutions. Verify patched
   source MD5, unchanged target attributes, ACL/owner/security/config, relation
   catalog, trigger/source closure and before/after data digest. Any mismatch
   raises within the same transaction and rolls the installation back. There
   are no application-table INSERT/UPDATE/DELETE statements in the installer.
7. After acknowledged commit, re-run the catalog query read-only and compare
   against the expected checkpoint with only target source/definition changed.
   A later data digest may legitimately differ because normal writes resumed;
   the atomic in-transaction comparison is the no-install-data-mutation proof.
   Store before/after, source SQL, hashes and tool result durably before reporting
   installation complete. Unknown commit outcome requires observation, not rerun.

## Code restoration is not financial rollback

Prepare an exact original definition and attributes in the private record. A
code-restoration candidate must require the exact patched MD5, unchanged
owner/ACL/security/config and the same deployment serialization; then restore
only the original function definition. It restores the previous bug, so use
only as an explicit operational decision. It cannot undo legitimate approvals
or cost consumptions made after installation. Never delete their ledger rows,
rewrite confirmed documents, or call this an unused/financial undo merely
because the patch changes no table data during installation.

## Current blockers

- PR1348 exact head `9e7978f92807442de6fec72bd34b61fbcaacaa1f` has passed all four checks. Parent verified Native job `120783194542`: pass=true, checks=100. Reviewed SQL SHA256 is `4589d3cb2ab90db9fb07120b04e938aaa95c386babfdd810ed0e47ea0ee98802`. This prerequisite is satisfied; it does not replace the fresh production checkpoint.
- Parent has now captured the full production catalog and independently verified
  server fingerprint `7a11f4dd1025470d2f4cb340b343c083d041aba26300cb0e14f54f817ed2e698`
  against the saved observation. Generated install/postflight/source-restore SQL
  remains review-only and unexecuted. A source-DDL deployment mutex agreement and
  the new generated-binder Native proof remain prerequisites.
- No production application-data digest or production installer was executed.

The bounded change can remain independent from the reciprocal-seal rollout and
its missing default-OFF/proof prerequisites. Fixing the finalizer does not enable
reciprocal approval or mark the whole financial workflow production-complete.


## Offline binder and event-trigger review

`tool/security/expense_finalizer_compat/prepare.py` now generates a server
fingerprint query, a bounded installer, a read-only postflight and a conditional
source-only restoration candidate. It requires the exact reviewed SQL SHA,
original source MD5/two anchors, owner-only ACL, target attributes, exact eight
relation names and six known event-trigger names. The complete original catalog
is bound by a PostgreSQL-generated JSONB-text SHA256, never a Python JSON hash.
The fingerprint result includes its observation so the caller must compare that
object with the private input checkpoint before accepting the digest. Observer
formatting uses explicit `public, extensions` search path and restores the
caller's previous path.

The original function appears both at the top level and inside the two trigger
function snapshots. Installed-state comparison normalizes exactly those copies
of definition/source back to the original, then requires the complete original
catalog fingerprint. The installer locks all eight tables in captured OID order,
compares counts and SHA256 row-multiset digests before/after source replacement,
and raises within the transaction on any mismatch. No raw financial rows are
returned or stored by this observer. The tables remain locked until commit.
The advisory lock is deliberately documented as a cooperating-helper mutex;
separate arbitrary DDL must still be quiesced during installation.

The fresh checkpoint's six enabled event triggers were read-reviewed. Only
`pgrst_ddl_watch` handles CREATE FUNCTION here: it issues transactional
`NOTIFY pgrst, 'reload schema'`, with no application-table writes. The remaining
five hooks handle DROP events or CREATE/DROP EXTENSION, so this single CREATE OR
REPLACE FUNCTION does not activate their extension grants/wrappers. All six
catalog entries and definitions remain in the full fingerprint. An unknown or
changed event-trigger definition is rejected by that binding; the name whitelist
alone is not the authorization check.

Four offline tests passed, including exact candidate/server-digest requirements,
owner/ACL/source/event/relation drift rejection, source-normalization generation,
and read-only postflight boundaries. These are generator checks, not a claim that
the generated production binder has run in PostgreSQL. The target two-substitution
SQL itself passed the separately owned PR1348 Native100 proof. Placeholder-digest
outputs are local inspection artifacts and must never be applied.


## Generated-binder Native candidate

The added `native-bounded-install` workflow exercises a separate Node harness
against disposable PostgreSQL17. It runs the existing PR1348 financial proof,
then recreates the original finalizer from pinned repository sources and confirms
its original MD5. The harness declares six synthetic surrounding event hooks
with the observed names: one emits the expected transactional schema-reload
notification, five are explicit no-ops. These hooks test binder preservation and
notification behavior; they are not claimed as recovered production extension
hook bodies. Their entire observed definitions are included in the generated
fixture fingerprint.

The fixture obtains its own server fingerprint and feeds its exact observed
catalog through the same production generator. Prepared cases cover changed
catalog refusal before replacement, a forced exception after replacement and
checks but before commit (full rollback), successful generated install and
read-only postflight, duplicate install refusal, changed-catalog refusal for
postflight and restore, successful conditional source-only restore, duplicate
restore refusal, and byte-equivalent protected synthetic rows throughout. No
hosted database destination or production credentials are accepted. Node syntax
and Python generator tests pass; this new Native proof is pending remote CI.

Production-bound outputs use the parent's verified server fingerprint:

- install SHA256 `b2a5f36ee4e6052731dbc27da38c12ecae89e47a8c1f0c614e1dac5a8dbbacd7`
- read-only postflight SHA256 `45c9bf2679745f6b562a7c85e3235b1f7fbd9e6bca6a53754c4959b3de5d4b74`
- conditional source restore SHA256 `16c24652d3572d6c0eb3e7ff33b68d14ea40af9354886164638bd613bd297031`

These private generated outputs are not repository source or proof of deployment.
