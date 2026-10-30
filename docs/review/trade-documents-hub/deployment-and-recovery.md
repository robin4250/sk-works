# Standalone hub: bounded installation and transition

This is a review plan, not permission or an executable production runbook.
Production HOLD and the individual-document-exemption OFF state remain in force.

## Installation requested separately from activation

Target: SK WORKS project `ztktgquxvcxcjxtluspu`, one transaction containing
`master-and-standalone-context.sql.review-only`, SHA256
`dffcc373801fb2d4b56d0c128e406b8fbe8c9b0d7929087a4fd29e38b655c706`.

The transaction extends the existing private master-key CHECK with
`site_order_documents`; replaces only `public.current_master_feature_flags()` and
`public.set_master_feature_enabled_with_proof(text,boolean,text)`; creates the
private live master gate, private management access/context functions and their
two public security-invoker wrappers. Explicit EXECUTE grants expose only the
scoped access/context RPCs to authenticated callers. Private authorization,
live SID, sole management membership and selected company checks remain mandatory.
Existing table RLS, owner and ACL are checked unchanged. It inserts no feature row,
enables nothing, changes no business row, original PDF, financial value or signature.
No invoice/payment automatic-attachment preference changes are included.

Existing owner-only profile/seal authorization is not broadened. This package
does not install site sharing, acceptance reply workers, notifications or internal
PDF registration. Their capabilities are separate and cannot be inferred from it.

Before asking for installation approval, capture fresh complete definitions and
pg_proc attributes of every guarded function and affected table constraint/RLS/ACL,
confirm the captured baseline still matches, preserve those originals privately,
and independently review the exact forward and recovery identities. A drift,
already-present new RPC, lock timeout or missing dependency stops the transaction.
The candidate sets lock timeout 3 seconds and statement timeout 30 seconds.

Apply order, if all three packages are separately approved: C master/context,
formal V1 prerequisite, then formal V2 month-end/FAX. The existing ordered fixture
ran 49 checks, including manager context after V2 and OFF denial. V2 first changes
the profile source expected by C and deliberately blocks the baseline guard.
Never replace that guard with a guessed hash.

## Verification after installation, still OFF

Independently compare installed function bodies and complete catalog attributes
against the reviewed expectation. Confirm the new master key is absent/OFF,
old flags retain their values, anonymous execution is denied, authenticated new
access/context calls fail closed while OFF, and existing registration-only
generation and existing company/financial reads retain their previous behavior.
Record installation separately from activation and device testing. Synthetic
JWT fixture success is not live GoTrue or iPhone proof.

## Recovery boundaries

A failure before COMMIT rolls back this transaction. A lost COMMIT acknowledgement
requires fresh read-only catalog reconciliation; never blindly retry installation.
If the committed identity differs from both the original and expected state,
stop and preserve evidence rather than overwrite a later change.

After COMMIT the default incident response is to keep the feature OFF and retain
the old registration entry. No automatic source rollback, DROP, flag deletion or
CHECK contraction is allowed. If the new key has ever been written, shrinking
the CHECK to the original five keys would conflict with a retained row. If site
modules reference the private master gate, dropping it would break those modules.

Any requested source restoration is therefore a separately reviewed, stopped-
writer operation: verify no in-flight/new calls and no later dependent source,
compare the exact installed function/catalog identity, and restore only the two
captured original public function bodies while preserving OIDs/attributes. Leave
the additive CHECK and new guarded functions in place, OFF. This restores the old
public source surface; it is not a full uninstall or a data undo. A source-only recovery generated from the original fixture capture was rehearsed
in PGlite: later-source drift is refused; both original function bodies, OIDs and
attributes return exactly; the OFF row, additive constraint/functions and table
security remain. The full suite passed 56 checks. Native PostgreSQL runs in CI.
The final production recovery must still be generated and pinned from the fresh
private capture before approving that operation; fixture rehearsal does not
authorize restoration against an unknown live state.

## Entry migration readiness

This candidate retains the existing company-detail generator and its existing
null-gate registration-only path verbatim. A hub error never falls back to it.
The new hub always uses its managed lease and strict new server context.

Remove the old buttons only in a later reviewed release after all of these are
recorded: installed backend identities, separate authorized master activation,
owner/admin/submanager positive and denied-role tests, creation/preview/native
print checks under company/SID changes, and the owner's iPhone operation proof.
That later release must remove the duplicate entry and update its routing test
together. Missing capability, OFF or CI success alone is not transition readiness.
