# Site-purpose manager adapters — private review candidate

This is a separate candidate on canonical-renderer PR1632/head65eb8fce. It does
not modify that candidate's original owner/admin authorization, deploy SQL,
enable the master flag, or connect an unfinished app route.

## Implemented

The exact C actor-base helper from PR1633/headbbe04e55, body MD5
`63c57e18a04499e8d6bcfad4ead7837f`, supplies live SID, exactly one company
membership and owner/admin/manager role plus the shared purpose flag. Its
standalone capability is **not** treated as access to arbitrary site documents.
A private immutable registry additionally fixes the exact own site/document,
issuer/counterparty direction, registered trade ID/kind and server-generated
opaque connection fingerprint. The actor helper takes both company and document
IDs; it cannot lend a company's authority to another document.

The new prepare wrapper requires an existing own site. It atomically reserves
that document, validates the selected registered counterparty/direction/link and
prepares the immutable canonical body. A document from another route cannot be
adopted into this registry. No fabricated financial parent or site is created.
The registry's deferred document FK is satisfied by the same successful prepare
statement. Failed preparation rolls back its reservation.

Eight exact existing pg_proc bodies are mechanically generated into the new
private namespace: prepare/bind/local-check/preview/decide/approved-render and
canonical-job prepare/register. Only named authorization/delegate substitutions
and explicit site/direction/no-financial-parent guards are permitted. Original
canonical tables, seal snapshots, CAS, append-only receipts/history, immutable
original registration and stale-current-revision protection are reused. The
source contract pins exact function signatures, body hashes, argument names,
return types, volatility, owner, definer/invoker, search path and client ACL.
Generated-source hashes are retained privately. Existing original pg_proc
bodies/attributes and financial rows remain unchanged in the fixture.

New tables have RLS, no client/service grants and UPDATE/DELETE/TRUNCATE refusal.
Every internal operation repeats live actor/company/role/master, site ownership
and current registered link checks. There is no manager-to-admin impersonation,
company membership mutation, client-writable authorization GUC or public upload.

## Verification

Disposable PGlite: 39 checks passed, including both manager order and acceptance
prepare → registered own seal consent → job → actual Dart PDF → original receipt.
The original global helper still rejects manager. Foreign site/company/document,
wrong registered direction, changed fingerprint, no registry, financial-parent
borrowing, role loss, second membership, SID deletion, master OFF, disabled link,
site reassignment and client/service EXEC are refused. Original pg_proc and
financial rows are preserved. Modified C actor source stops installation before
new schema creation; rollback restores that fixture dependency.

The fixture uses C's exact helper body and the existing consent/API synthetic
session environment. It is not real JWT/native-device proof. Dedicated CI runs
new contract tests on PGlite and native PostgreSQL17 with the fixed pure Dart
runtime; the prior successful renderer tests are not manually repeated.

## Next atomic receive/approval contract — not implemented here

The recipient's site must be created by the actual approval transaction, then
its acceptance body/own seal approval and durable render intent are committed
with the order approval. Only an after-commit worker generates/registers the PDF
and records reply delivery. No placeholder site, fake PDF, or success callback
that sends an arbitrary second message is allowed. Role/session/master loss
holds that exact intent; unknown outcomes use the same receipt/job, not a new
request. The core runtime requires a dedicated verified request connection and
must not be nested into an existing approval transaction or commit its caller's
transaction. Approval records mean queued until the real reply is recorded.

The old structural `site_order_private.acceptance_outbox` requires an already
rendered artifact by FK. It cannot represent this after-commit sequence by
inserting a dummy artifact. A guarded new intent/receipt contract must replace
that assumption, preserving the old candidate and immutable originals.

There is no direction-specific registered company-rate revision in the current
body/job contract. No worker payroll rate or customer billing revenue rate is
copied into an outgoing supplier purchase order. Received order conditions are
preserved; missing prices remain null, without zero/total-division guessing.

Still pending: receive/approve/site/intent atomic coordinator, purpose-scoped
manager Node registration dispatch, actual internal runner/authenticated route,
reply recovery/history/notifications, production prerequisites/installer and
phone verification. The existing invoice/financial approval rights are not
expanded. Production HOLD, new feature OFF and document exemption OFF remain.
