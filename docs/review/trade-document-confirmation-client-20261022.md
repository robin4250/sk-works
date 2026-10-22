# Directional trade-document confirmation client candidate

Based on main `6ffaf7d4adec9a63805fc1acb094d9cbc97b5308`. This is an unshipped
client candidate for the reviewed public API contract. No production SQL, grant,
invitation, financial amount correction, Flutter execution or iPhone validation
was performed by this implementation.

## Actual entry points and ownership

* `InvoicePdfPreviewPage._approve` calls the capability-gated combined flow after
  preserving the existing explicit-surname interaction. Known absent capability
  or a server-declared non-integrated scope keeps the existing approval method.
  Network, permission, malformed response or unresolved previous submission never
  falls back to the old approval. A successful combined invoice operation is
  re-read through the existing approval reader before reporting success.
* Invoice preview exposes **承認済み注文請書を開く**, using read-only resolve then
  exact approved rendering. It does not prepare another document on a read.
* Stored monthly certificate preview exposes **注文書の内容確認・角印** and
  **承認済み注文書を開く**. In-memory previews, agreement snapshots and invalid IDs
  cannot use these controls. Monthly content confirmation does not finalize a
  financial certificate; the two explicit choices explain this boundary.
* A linked company's existing directory dialog adds **受領した承認済み書類**.
  Its list is scoped by the local trade-company ID. The server resolves the real
  registered companies; no company name, phone or unordered company pair is used
  to establish identity. Each received document first gets its own local ID and
  then opens a read-only approved page with no seal-confirmation method.
* Existing standalone generation, preview and printing remain unchanged. This
  candidate does not invent an invoice/payment certificate for a standalone PDF.
  Standalone saved evidence/issuer consent remains a separate unsupported flow.

The existing three files above and the six new `trade_document_confirmation_*`
libraries are owned by this client lane. SQL/public API is a separate owner;
shared help, translations, workflows, publishing and production belong to root.

## Exact command and recovery

The preview descriptor has exactly 12 scalar fields: contract_version, kind,
company_id, actor_id, parent_id, source_revision, attachment_version,
local_document_id, document_id, document_revision, body_hash and preview_hash.
It contains neither registered PNG bytes nor session credentials. It is copied
deeply immutable, written to its own atomic actor/kind/parent-scoped journal
before the only live confirm request, and retained on unknown results.

The original request ID and descriptor are used by read-only receipt lookup.
Missing receipts, lost permissions and changed sessions do not authorize a new
request or delete the journal. Only that exact validated receipt, or a definite
first-live-request SQL rejection, can clear its matching record. A pending result
also blocks legacy fallback if the capability disappears after submission.

Own confirmation requires content confirmation and explicit use of the company's
registered stamp. A pre-approval image is only shown in the issuing company's
preview; OS printing/sharing is disabled there. The received page cannot request
or consent to an unapproved issuer asset. Actor and access-token leases are sticky
across account/session changes. No credential is written to a journal.

## Immutable rendering and separate pages

Approved rendering validates actor, company, local ID, evidence ID/revision,
side, archive flag, body hash metadata, exactly one issuer consent and issuer seal,
and the pinned renderer contract. The registered company name and uploaded asset
identity are checked by the existing strict seal parser. Unknown renderers or
cross-company assets are refused. The server's PostgreSQL JSONB body hash is not
recreated using Dart JSON serialization.

The registered PNG's PostgreSQL base64 transport can contain CR/LF line wrapping.
The PDF adapter removes only those transport line breaks from a copied snapshot
before the existing strict decoder; the decoded image SHA256, PNG integrity,
company and version checks remain unchanged. Stored evidence is never rewritten.

Preview, print and share use one generated PDF byte sequence. Only an explicit
native print/share handoff can retain approved bytes while the app is inactive;
session changes or hidden/paused state invalidate the viewing scope. A received
historical copy requires an explicit archive choice and is labelled as history.

The existing first-page invoice/payment PDF pipelines are not replaced by this
candidate. Approved evidence is available through its clearly labelled separate
entry. Automatic insertion of this immutable approval evidence into every bulk
financial export remains outside this first client candidate and must not be
claimed from the separate approved-document page.

## Verification

Run `flutter analyze` and `flutter test test/trade_document_confirmation_test.dart`
remotely using the repository's locked Flutter/dependencies. The tests cover exact
descriptor immutability/no image persistence, own/other local identity separation,
operation/result validation, unknown-result recreation and read-only reconciliation,
SQL rollback versus session changes, approved-renderer scope rejection before
asset loading, real SDK capability normal/absent/permission/transport/type cases,
and actual route fallback versus unresolved-pending retention.

The API lane's real synthetic response export must additionally be checked against
these parsers, and full UI/PDF visual, current/archive, concurrent session and
iPhone print/share tests remain necessary. Initial tests written or source saved
are not a passing CI result. The received list refuses over 200 entries and over
4 MiB JSON rather than silently truncating; pagination is not implemented.

## Shared help and translation integration

The new UI uses `SkoLanguageController.watch`, `tr` and `trParams`; root owns the
English map and contextual help. New entries are the labels above. The dynamic
translation key is `第{revision}版`. The historical banner is
`過去の承認済み書類です。現在の内容とは異なる場合があります。`.

Root should extract all fixed Japanese UI strings from the six new libraries for
the shared map. The two action descriptions must retain the distinction between
invoice final approval and monthly content review. Do not translate these into a
claim that payment is finalized or that a recipient approved another company's
seal.
