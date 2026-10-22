# Monthly payment confirmation and order seal: next contract

Design and source investigation only. No financial writer, public RPC, grant, migration, approval, invitation, or production modification is included. This supplement does not make PR #1318 a delivered workflow.

## Confirmed boundary

Reviewed product main: `6ffaf7d4adec9a63805fc1acb094d9cbc97b5308`. PR #1318 head `0eba3eb63f8c12577ee67f1929593daa5ef24fed` remains a draft; its eight checks pass, including native PostgreSQL 17 123 checks and PGlite 85 checks. That proof covers the existing private invoice→acceptance adapter and its races, not monthly payment confirmation.

The monthly product screen loads `PaymentCertificateRepository.loadCertificates`, reads `public.payment_certificates` plus `payment_certificate_detail_rows`, and saves partner settings through `save_partner_payment_setting`. It has no monthly confirm/approve call. The preview screen offers PDF printing/sharing and attachment editing. `SitePaymentCertificatesRepository` calls the separate site-agreement workspace/saved-document APIs; it is not a monthly approval adapter.

Read-only production catalog inspection on 2026-10-22 found no monthly payment-certificate approve/confirm/finalize RPC in `public` or `private`. The existing site function signatures are `public.confirm_site_payment_terms(uuid,uuid)` (body MD5 `1554de857adeee2f128685b6ce1e98dd`) and `private.confirm_site_payment_terms(uuid,uuid)` (`3337f5ac1da930af1a80e3494fc2858f`). They confirm a site proposal, not a monthly certificate. Do not repurpose them or describe the monthly integration as an existing transaction hookup.

PR #1318's `trade_document_consent_private.parent_binding` and `confirm_local_document` deliberately raise SQLSTATE `0A000` for `payment_certificate`. This fail-closed branch remains unchanged. A new monthly confirmation transaction is required before that branch can be connected.

## What can be bound today

Monthly certificates are stored rows, not just a generated view. `public.payment_certificates` has UUID `id`, own `company_id`, local `partner_company_id`, period start/end, integer `revision`, `status`, `finalized_at`, calculation flags, amounts and JSONB `snapshot`. Status is constrained to `draft` or `finalized`; the company/partner/period tuple is unique. Draft rows can change through attendance/settings recalculation, so a stored ID or snapshot alone is not immutable approval evidence.

Registered-company zero previews are different: `PaymentCertificateRepository.emptyPreview` constructs `preview:<partner>:<year>-<month>`, revision 0 and `status=preview` in memory. They are not saved certificates and must never be accepted by the new confirmation command. Standalone order creation should remain a separate document identity; it must not manufacture a financial parent for such a preview.

`private.trade_document_attachments` already provides the saved `payment_certificate` subject UUID, source revision/fingerprint, attachment version and canonical payload. The current source reader `private.trade_document_source(text,uuid,text)` has production body MD5 `ebcc70935938482054943560390038b2`. Use its guarded, current binding rather than the older migration text when preparing the implementation. A source-reader hash is a prerequisite check, not complete dependency closure or an approval grant.

Resolve the real counterpart only through the unique same-company `trade_companies.partner_company_id` mapping, `linked_company_id`, role `subcontractor`/`both`, and accepted `link_status=linked`, with the actual formal connection checked by the existing connection helper. `partner_company_id` is a local business record, not a registered company ID. Reject absent/duplicate/wrong-role/wrong-company mappings; never infer a link from a name or phone number.

## Proposed new transaction contract — not installed

Reuse the existing `trade_document_consent_private.documents`, `revisions`, `local_links`, `consents`, `events`, `receipts` and `financial_receipts` design. Each company retains its own `(company_id, local_document_id)`. Order and acceptance keep distinct document IDs and issuer roles, even when their transaction ID and content are related. The issued and received pages may resolve one immutable issued body after authorization, but they never become the same editable financial page.

Candidate private names for a future implementation are:

- `trade_document_consent_private.preview_payment_confirmation(local_id uuid, cid uuid, rev integer)` for an exact, current source/attachment/seal preview;
- a new `private.confirm_monthly_payment_certificate(...)` financial operation, whose exact signature must be fixed with its approval model before implementation;
- the existing `trade_document_consent_private.confirm_local_document(...)` payment branch as the one transaction coordinator;
- `trade_document_consent_private.read_confirmation_receipt(cid uuid, rid uuid, expected jsonb)` for the original request after an unknown result.

These names are proposals, not existing APIs. Do not add a second financial confirmation ledger if the implementation can reuse an existing, independently reviewed monthly confirmation model discovered later. An immutable monthly confirmation/audit record is currently missing; its schema and authority must be established explicitly rather than copied from invoice assigned approvers or site terms. A possible separate private `monthly_payment_confirmations` record would need parent UUID/revision/content hash, actor/company, explicit financial decision, request ID, timestamp and immutable pre/post binding. Its existence alone would not finalize the financial parent or authorize printing another company's stamp.

Preview must bind the own stored parent UUID/revision, exact financial content hash (amounts, period, partner and snapshot), calculation readiness, attachment source revision/fingerprint/version/payload hash, directional order document ID/revision/epoch/body hash, formal company mapping and the issuer's registered seal version/hash. Do not hash a changing clock value as business content; store separate pre/post lifecycle bindings as the invoice candidate does. Recompute the same projection under locks before committing.

One existing confirmation UI operation must show the certificate, related order and explicit registered-seal use, then submit one request ID with both financial and seal choices. The new transaction must check current session/account authority, the issuer's owner/admin authority and the specifically defined financial confirmation authority independently. A recipient may not consent to the issuer's seal merely because it can view or confirm a received certificate. Internal own-company invoice approvers are not automatically another company's financial reviewers.

The transaction must execute the reviewed monthly financial decision and issuer consent atomically, preserve original multi-person approval rules if introduced, and record one immutable receipt with exact pre/post bindings. Replays of the same actor/request/payload return that receipt before stale-preview checks; a different payload under the request ID is rejected. Lost-result recovery only reads that exact receipt and never creates a fresh request automatically.

Do not implement finalization as a direct status update. Production certificate triggers include `private.expense_cost_finalize()` (`22ff4377666ec56ccc4b261cf380e9c0`), `private.expense_payment_v2_guard()` (`4d08bd0b372a3048b9eb52dd99a3c321`), `private.preserve_document_company_seal_snapshot()` (`d321fa751ac3374ce24782ab4abbe430`) and `private.capture_expense_document()` (`0f92690685d8ac74ce233543be999678`). A future writer must preserve their expense-consumption, direction and snapshot behavior, with full metadata/source prerequisites and negative tests. These observations do not authorize replacement of those functions.

## Required isolated verification before rollout

1. Stored monthly parent succeeds only with exact mapping, saved attachment, ready calculation, current original revision and both explicit choices. An in-memory preview, unsaved attachment, wrong type/local company or wrong issuer fails without writes.
2. A→B order, B→A order and related acceptance retain separate local/document IDs. Binding one local page never creates or modifies the other company's financial parent. Membership in both companies does not imply consent for both.
3. Unrelated member, manager/viewer without the defined authority, other-company actor, revoked/restricted session and an unauthorized recipient cannot confirm or retrieve the raw issuer seal. Approved received copies use document-specific permission, not issuer-parent access.
4. Financial mutation, attachment edit, seal rotation, connection disablement, wrong epoch or changed confirmation/approver configuration between preview and commit rejects the complete operation. A later failure rolls back both financial and seal records.
5. Simultaneous identical requests create one financial decision, consent/event and receipt. Distinct stale requests reject. Test actual lock waits against attendance/settings recalculation and finalization writers, preserving the established lock order; a theoretical lock claim is not sufficient.
6. A commit with missing acknowledgement is reconciled by the original request. Different request payloads, absent receipt, changed actor or permission removal never trigger a resend or clear the pending record incorrectly.
7. Existing finalized certificate amounts, expense ledgers, approval/audit history and saved seal/attachment snapshots remain unchanged. A new draft or changed body needs new explicit consent. Cancellation does not erase evidence; current and explicit archive reads remain distinct.
8. Product PDF/model/UI must consume the approved immutable body and exact registered seal asset/version under an enforced renderer contract. Both authorized local pages print the same issued evidence. Generated fallback seals, raw name-based reconstruction and unapproved opponent assets are rejected. Test preview/print/share using the same bytes on iPhone.

The limited next implementation is therefore the new reviewed monthly financial confirmation contract and its atomic coordinator adapter, followed by public/session authorization, durable client recovery and renderer binding. It is not a one-line removal of `0A000`, and the existing private invoice proof is not evidence that these monthly stages are complete.
