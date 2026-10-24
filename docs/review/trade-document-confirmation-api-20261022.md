# Trade document confirmation API candidate — 2026-10-22

Review-only, not deployed. This extends the PR1318 private coordinators with a new public contract, not an existing production API. Invoice confirmation invokes the existing `confirm_local_document` and its real final `approve_invoice` adapter. It requires issuer stamp authority and the existing assigned invoice approver; ordinary invoice approval permissions are not replaced. Monthly payment certificates receive a new content-review/issuer-seal receipt; this does not finalize the financial parent or change its amounts, details or status.

## Dependencies and installation order

Use the existing PR1318 consent/attachment/real invoice adapter fixtures, then the current source epoch (base → tax snapshot → directory party → own representative → invoice representative), then `trade_document_monthly_review_20261022.sql.review-only`, then `trade_document_confirmation_api_20261022.sql.review-only`. The API aborts on source body/owner/SECURITY DEFINER/search_path/ACL drift; production reader expected MD5 is `ebcc70935938482054943560390038b2`. Old saved proofs are retained.

The only monthly coordinator adjustment is its full private preview size bound from 64KiB to 2MiB, because an accepted registered PNG can exceed 64KiB. Its new body MD5 is `4a43c7ec090882d384de11b451318cd8`. Public commands remain scalar-only, exact-key, maximum 8192 bytes; image bytes never enter persisted pending commands.

## RPC contract v1

All RPCs require a current authenticated account and matching `auth.sessions` row. Server derives financial parent company from its saved UUID. Registered linked counterpart and formal connection, company owner/admin stamp permission, actor, source revision, attachment version, immutable body hash and preview hash are checked. The caller never supplies inferred company names or phone numbers as authority.

| RPC | Arguments | Result |
|---|---|---|
| `trade_document_confirmation_contract_version` | none | integer 1 |
| `trade_document_confirmation_workspace` | `p_kind text, p_parent_id uuid, p_source_revision text` | issued workspace; prepares/reuses canonical evidence document and local link |
| `resolve_trade_document_confirmation` | `p_kind text, p_parent_id uuid` | read-only saved issued IDs and render availability |
| `preview_trade_document_confirmation` | `p_company_id uuid, p_local_document_id uuid, p_document_revision integer, p_kind text` | descriptor plus full display preview |
| `confirm_trade_document_with_seal` | `p_expected_command jsonb, p_request_id uuid, p_document_confirmed boolean, p_seal_confirmed boolean` | atomic existing invoice approval/new monthly review plus issuer seal consent and immutable API receipt |
| `read_trade_document_confirmation_receipt` | `p_company_id uuid, p_request_id uuid, p_expected_command jsonb` | `{contract_version:1,found:false}` or `found:true,result` original response |
| `list_received_trade_document_confirmations` | `p_trade_company_id uuid` | own-company scoped approved received evidence list |
| `received_trade_document_confirmation_workspace` | `p_trade_company_id uuid, p_document_id uuid, p_document_revision integer` | stable separate receiving local ID, no confirmation permission |
| `render_confirmed_trade_document` | `p_company_id uuid, p_local_document_id uuid, p_document_revision integer, p_kind text, p_archive boolean` | immutable consent-bearing render evidence |

`p_kind` is financial parent kind `invoice` or `payment_certificate`; corresponding evidence kind is `acceptance` or `order`.

Workspace common response keys: `contract_version,kind,company_id,actor_id,parent_id,source_revision,side,document_id,document_revision,local_document_id,attachment_version,integration_required,can_integrated_confirm,unavailable_reason,can_render`. Unavailable document/local/revision/attachment fields are null. Preparation is idempotent for identical parent/source/body/attachment; material changes create a revision on the same evidence document. Company-local IDs, evidence IDs and financial parent IDs are distinct. Missing/stale attachment is not manufactured or silently saved. Capability presence alone does not authorize confirmation. A current invoice-viewing company member with an existing pending assigned approval receives `integration_required:false`, null evidence IDs and `unavailable_reason:ordinary_assigned_approval` only when they lack owner/admin stamp authority or other assigned approvals remain incomplete. This preserves the existing ordinary approval transaction without preparing evidence or falling back from a permission error. Nonassigned members and missing invoice-view permission remain denied.

Read-only resolve returns `contract_version,side,kind,company_id,actor_id,parent_id,document_id,document_revision,local_document_id,current_document_revision,phase,integration_required,can_integrated_confirm,can_render,can_render_current,can_render_archive,source_changed,unavailable_reason`. It prioritizes the latest API-confirmed revision even when a newer draft exists. Use resolve for approved printing; workspace may propose a new draft and is not a read resolver.

Preview returns the 12 descriptor fields at top level plus `expected_command` and `display_preview`. Exact descriptor keys and types:

- integer: `contract_version` (1), `attachment_version`, `document_revision` (positive).
- canonical UUID strings: `company_id`, `actor_id`, `parent_id`, `local_document_id`, `document_id`.
- strings: `kind`, `source_revision` (1–128 chars), `body_hash` and `preview_hash` (64 lowercase hex).

`display_preview` includes the immutable `body`, its `body_hash`, and the existing private preview with the registered issuer seal snapshot. Persist only `expected_command` and the original random request UUID; never persist display/PNG or recompute PostgreSQL jsonb hashes from client JSON. Unknown response/renderer contract must fail closed.

Confirmation response exact keys: `contract_version,kind,company_id,actor_id,local_document_id,document_id,document_revision,request_id,operation,seal_consent_recorded,result`. Operation is `invoice_final_approval_with_seal` or `monthly_content_review_with_seal`; result preserves the existing coordinator result (`financial_approved:true` for invoice, `financial_finalized:false` for monthly). Both explicit booleans must be true. Original same actor/scope/request/descriptor replays the exact saved result even after source changes; a changed actor/payload or a new request cannot impersonate the receipt. Read receipt after uncertain delivery before retrying. Technical result flags are not user-facing terminology.

Received list outer keys: `contract_version,company_id,actor_id,trade_company_id,peer_company_id,items`. Item exact keys: `document_id,document_revision,kind,issuer_company_id,issuer_name,month,body_hash,is_current`. Only API-confirmed evidence is listed, latest approved per document; no peer draft or financial parent rows. Maximum 200; 201st produces SQLSTATE 54000, never silent truncation. Pagination/narrowing is a future contract requirement.

Received workspace returns common scope with `side:received,phase:approved,can_integrated_confirm:false,unavailable_reason:received_copy,can_render:true,can_render_current,can_render_archive:true,source_changed`. Receiving local ID is stable and differs from issuer local ID. It cannot preview/confirm issuer seal use and does not require or grant peer financial-parent access.

Render outer exact keys: `contract_version,kind,company_id,actor_id,local_document_id,document_id,document_revision,side,archive,evidence`. Evidence is existing `render_approved` body/binding/seals/consents/hash output. Primitive seal consent without the integrated API receipt cannot render through this API. PDF adapter must validate scope/body/seal issuer and renderer contract `company-seal-pdf@2853e2d8d530f3fc65ce74ef307a1c63b21b0496` before invoking the existing PDF generator. Current source change blocks current render; archive explicitly preserves approved immutable snapshot.

## Reproducible proof

Run from repository root with the locked existing fixture dependencies:

```sh
SKO_MONTHLY_PAYMENT_REVIEW_HOOK=contract-v1 SKO_TRADE_DOCUMENT_API_REVIEW_HOOK=contract-v1 node tool/verify_trade_document_bound_seal_consent.mjs tool/security/fixture_dependencies/node_modules/@electric-sql/pglite/dist/index.js
```

For root-owned native CI use the existing strict loopback fixture URL and pg dependency, with both hook environment values unchanged. No workflow is changed here.

Actual synthetic SQL response examples are saved in `tool/fixtures/trade_document_confirmation_api_synthetic.json` (no real user data). Regenerate by setting `SKO_TRADE_DOCUMENT_API_EXPORT` to a local output path.

Local PGlite: 230 checks passed including unchanged monthly parent, actual member ordinary non-final approval followed by owner integrated final approval/audit/seal freeze, exact receipt replay, altered command refusal, missing explicit choice rollback, distinct received local ID, primitive direct consent denial under authenticated role, viewer/other company/restricted account refusal, deleted session refusal, current-source change versus immutable archive, and a valid registered PNG above 64KiB with compact command. Previous source epoch and invoice adapter regression proofs pass in the same run.

This is SQL role + synthetic session/claims proof, not real GoTrue/PostgREST JWT verification. Native concurrent public requests, actual issued JWT/session revocation over HTTP, API deployment, final UI/PDF/native proof and device distribution remain required. Existing private concurrent fixture coverage is not relabelled public-API race coverage. No production financial data, auth role, real account or external recipient was modified.
