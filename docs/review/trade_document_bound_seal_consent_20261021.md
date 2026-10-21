# Directional document consent: isolated contract, not integrated approval

Source investigation main2853; saved branch base main160542e6. This supplements the existing sealed-site closure; it does not relax its accepted-site requirements or connect site contracts to monthly documents. No product PDF/model/UI, existing SQL definition, financial parent, notification or production permission is changed. All new objects remain private/ungranted with RLS; there is no public opponent-asset API.

## Source facts and reuse

- `20261007221757_invoice_stamp_policy_and_approval_history.sql` approve/cancel is same-company assigned-confirmation state. It is not another company's seal consent. `20261011031108_invoice_draft_seal_finalization.sql` freezes original invoice seal metadata and invalidates approval on material content change.
- `20261014124714_monthly_trade_document_attachment.sql` saves parent source revision/fingerprint, attachment version and server-owned seal snapshot. Saved/locked attachments remain independent from current defaults. The source customer/partner ID is not a registered company ID by itself.
- `20261015080425_site_contract_sealed_revision.sql` already checks formal connection, official snapshot under company row locks, current proposal revision and exact hash; each company approves its own seal. Its accepted shared-site/rollout scope is not copied to standalone documents. This supplement reuses the official snapshot helper/lock/hash principles, not site-confirmation authority or notification sending.
- CompanySealSnapshot v1 includes registered legacy/aoyagi and company-restricted fixed PNG designs; v2 uploaded_png includes PNG version and asset SHA256. The fixture loads the actual official helper from `20261010160154_company_seal_png_designs.sql` and actual uploaded-PNG candidate, not a reconstructed other-company seal.

## Separate company pages; shared immutable evidence only

Each company has its own `(company_id, local_document_id)` link and retains its own editable draft, parent financial record and workspace. The agreement document ID is an independent evidence ID, never a synthetic invoice/payment-certificate ID. The candidate does not implement those local editors; `local_links` records identity only. Registering one company's link never creates/edits the other company's local document.

The agreement fixes transaction ID, document kind, issuer company and recipient company. A→B and B→A are separate documents/transactions. Order and acceptance are separate kinds/issuer roles even when linked to the same transaction. No lookup collapses an unordered company pair. Only the issuer can propose a new immutable content revision; the recipient cannot mutate it. Each side may edit its own local draft outside this evidence store; changed content must be proposed/reapproved rather than overwrite an agreed revision.

Each paper's issuer records explicit seal consent under its own owner/admin authority: order=甲, acceptance=乙. The other company's recipient page cannot approve on behalf of the stamp owner. Membership in both companies does not automatically approve both or infer permission. Pending issuer preview returns only its own official seal, never an opponent asset. Company-specific local links are required for decisions and rendering. Standalone initial view authority is explicitly owner/admin; it is not all-members/viewers access. Linked view requires an additional parent/document-specific adapter, false by default.

After that paper's issuer approval, both separate local pages can resolve the same immutable issued body/hash and print evidence. No additional recipient stamp request is required to read the received copy. The print response contains **one issuer seal**: order=ordering company (甲), acceptance=accepting company (乙). It does not add both stamps to both party fields or wait for two stamps on every paper. Order and its related acceptance keep their own issuer-consent records linked by transaction ID; approval of an order never creates an acceptance or its issuer consent. The evidence state `approved` means the explicit approved issuance of that paper, not automatic bilateral contractual acceptance. PDF/model/UI consumption is not connected.

## Version, lifecycle and archive

Content hash, document revision, decision epoch, company, actor and seal hash bind each consent. PNG mode additionally stores png_version_id/png_sha256. Registered generated v1 styles bind the official snapshot hash and a pinned renderer contract identifier; that is **not a bitmap hash**. The existing UI/PDF does not yet enforce the renderer contract identifier, and fixed-PNG/aoyagi real printing is not proven here. Never regenerate a substitute from a directory/name-only input.

Rotation after preview requires the issuer to confirm the current registered version; a stale preview cannot authorize another seal. Rotation after issuance leaves the saved approved snapshot unchanged. Connection disablement stops new preparation/approval, does not delete evidence or replace stamps, and does not itself grant/revoke archival document viewing. Issuer cancellation remains possible after disablement. Reject/return/cancel are distinct issuer lifecycle states; recipient-side financial review/return is not implemented by these internal stamp decisions. Changed content creates a new revision and reuses no consent. Current rendering rejects superseded revisions, while explicit archive reads can use an older approved version under document-specific permissions. Cancelled versions remain stored but this minimum renderer does not expose their stamps; full audit/archive UX is not implemented.

## Mandatory single confirmation operation: not implemented

The final product must reuse the existing confirmation/approval screen: show the exact invoice/payment certificate, related order/acceptance and registered-seal use, then complete financial confirmation and seal consent atomically under **one request ID and one user operation**. There must be no separate extra stamp request/button. Both authorities and explicit choices, the company-specific parent revision, attachment revision, directional document identity and seal version/hash must be rechecked in the same transaction. Any mismatch must roll back both records. Old internal invoice approval is never interpreted as counterpart permission.

`confirm_local_document` deliberately raises adapter-not-connected. `parent_binding` also fails closed and `linked_view_allowed` defaults false. The ungranted `decide` primitive is for isolated boundary tests only, not an alternate product workflow. The actual formal FK→registered counterparty resolver, local-parent mapping on both companies' pages, shared request delivery/workspaces, proper financial recipient-review authority and same-TX recording are still missing. The fixture's explicitly synthetic read-only parent/view adapters prove binding mechanics against the real attachment saver; they do not implement those production permissions or change existing financial confirmation status.

## Verification and remaining blockers

Dedicated PGlite/PostgreSQL17 CI loads the real existing attachment SQL and official seal helper/upload contract. It checks issuer-only explicit consent, own-only preview, identical issued/received evidence without extra approval, separate local IDs/directions/kinds, body changes/new approval, receipt replay, stale epoch, rotation, rejection/return/cancel, unrelated actor/ACL denial, no parent financial writes and default fail-closed unified integration. Results are separate from source preparation. Native two-connection races, real JWT/session revocation, durable lost-COMMIT reconciliation, stamp permission integration beyond this restrictive role contract, renderer pin enforcement, existing private source/canonical mapping guard closure, counterpart delivery, UI/PDF/device and production rollout remain unverified. The required single-operation same-TX financial approval plus stamp consent is UNIMPLEMENTED; core CI cannot satisfy that completion condition. No migration or deployment is authorized by this candidate.

## Private invoice confirmation adapter (isolated candidate, not rollout)

`trade_document_invoice_confirmation_20261021.sql.review-only` replaces the
unconnected command for **own-company invoice → acceptance only**. It calls the
existing `approve_invoice` or explicit-surname approval function, preserving its
assigned approver rows, audit, approval timestamp and invoice freeze trigger.
Their exact source bodies are guarded against drift. It requires owner/admin,
invoice view/manage permission, the assigned pending final approver, explicit
financial and seal consent, accepted formal connection and exact customer FK.
Earlier assigned confirmations must already exist; it never approves others.

The two changes and immutable financial receipt execute in one transaction.
Preview binds parent row, saved attachment/version, configured approvers, approval
rows, surname draft, own registered seal and immutable document revision.
Approval lifecycle changes are saved as separate pre/post binding evidence;
original document content/binding is never overwritten. Current reads accept only
that exact post-approval receipt; later content changes require fresh approval,
while an explicitly requested archive retains the issued snapshot. Companies keep
separate local IDs/pages. A received owner/admin may read that issued copy without
another stamp approval; this is a narrow independent document ACL, not general
access to the issuer's invoice or raw stamp.

The disposable fixture loads original financial functions and freeze migration,
not a fabricated financial writer. Synthetic prerequisites are minimal tables,
a clock trigger and companies/users/amounts. Cases cover normal/surname paths,
parent CAS, stale surname draft, finalized protection, permissions, replay and
later receipt-failure rollback. CI execution status must be read from this head;
source save alone is not a passing result. Real concurrent lock races and the full
production dependency closure remain unproved. Ordered company → financial
parent/attachment → consent locks align current rendering with confirmation.

**Still incomplete:** monthly payment certificates have no matching existing
confirmation RPC, so that path fails closed. Public RPC grants, existing approval
screen integration and actual renderer binding are absent. The renderer marker in
`own_seal` is a review contract, not proof of current PDF execution. Existing
standalone core is not a substitute for financial confirmation. No production
DDL/DML, existing financial data change, other-company request, deployment,
Release/iPhone confirmation was performed. Do not mark simultaneous confirmation
or the user's complete workflow as delivered from this private candidate.
