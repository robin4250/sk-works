# Company-owned profile candidate (review only)

Baseline: main `b5b9ce705c61dca7f2d7d964add1bce47b0f0183`.
No production SQL, data writes, application navigation changes or active migrations.

## Primary implementation evidence

- `company_submitted_documents_page.dart` is the existing self-company data editor. `CompanySubmittedDocumentRepository.loadCompanyData/saveCompanyData` calls `company_data_state/save_company_data`; those use `companies` name/address/phone/email/corporate_number and additional fax/bank fields. No representative field exists in that API.
- `20261003003500_add_company_data_profile.sql` saves the existing fields into `companies`, including updated_at. Do not mirror these fields into another profile table or send an old whole form merely to save a representative.
- `20261015012352_company_profile_update_review.sql` records old/new five-field contact snapshots and sends optional revision notifications. Its workspace returns complete proposed and source_old snapshots; its accept function currently copies all five fields. Both require server-side masking before reciprocal visibility can be claimed.
- `trade_companies.representative_name/representative_phone` are the registering company's local contacts for another business. `sites.representative_name` and daily-report signatures are separate records. They are not authoritative self-company representative sources and must not be promoted automatically.

## Canonical data and candidate contract

Only representative_name is stored in the new private extension table. All existing canonical contact fields remain in companies. Blank representative is allowed as incomplete setup; readiness requires non-whitespace company/trading name, address, phone and representative. Corporate number is optional. Values are owner/admin assertions, not identity-verification proof.

`private.partner_company_profile_ready(uuid) -> boolean` is an internal bridge hook. Missing company/representative returns false. `private.partner_company_profile_label(uuid)` returns only name/representative_name, never address/phone/email/corporate number. These hooks have no authenticated/anon execution grant. A bridge SECURITY DEFINER caller must independently validate token, same actor/scope and invitation state before invoking the label hook. Invitation readiness is not a connection grant.

`private.partner_company_profile_visible(viewer_company,target_company)` first checks the actor's owner/admin membership, account access and an accepted direct connection in either direction. Pending/disabled/missing connection and forged viewer company fail closed. Returned JSON contains a target field only if the viewing company has registered its own same field. No hidden value, prior value, hash, or source object is returned. Example: B has name/phone/representative but no address/email/corporate number; B sees only A name/phone/representative. This helper has no client grant; it must be integrated into every allowed company-information read path before activation. Viewer/manager access beyond owner/admin is intentionally not introduced by this candidate.

`public.read_partner_company_profile(company_id)` returns own canonical profile, extension version, companies.updated_at and readiness. `public.save_partner_company_representative(company_id,expected,representative_name)` edits only the representative. Full expected snapshot CAS runs after companies FOR UPDATE, serializing with the existing company-data updater. Representative version and audit row advance atomically; failed audit rolls back the write. Contact changes make stale representative forms fail instead of overwriting contacts. Readiness never writes assumed values.

## UI candidate (not wired)

Add a representative field with its own save action to the existing self-company data editor, preserving the current contact save path. Show existing company/trading name, address and phone read-only in the readiness card; guide missing items to the existing editor. The representative action must not call save_company_data with a stale whole form. Retain user draft after CAS failure, disable save until a fresh read, and show server-returned state only after successful reread.

Bind read and confirmation to explicit company, actor, token and monotonic session epoch; close confirmations and clear PII on logout, actor/token changes, same-actor ABA and background. Unknown outcomes stop resend and require fresh read. Display feature-unavailable on missing RPC without inventing readiness or silently saving a different field. No changes to #1306 company-detail UI are included.

## Activation gaps, deliberately not hidden

This is an independently testable candidate, not complete production privacy enforcement. Before activation, review and route search results, link workspace, request acceptance copies, directory synchronization, direct companies/trade_companies SELECT grants/RLS, existing profile-review workspace (old/proposed/source_old), acceptance updates and revision notifications through equivalent field masking. Historical records stay stored; hiding values must happen in the returned payload before the UI. Existing local/manual trade-company data must be distinguished from externally copied canonical data. No bulk erasure or silent overwrite of local contacts/history is authorized.

Representative-only changes are audited privately but do not currently create the legacy five-field profile revision notification. A later integration needs explicit representative revision/approval semantics; do not manufacture a company contact change to trigger it.

Concurrent membership revocation, accepted-connection revoke/read ordering, legacy contact ABA outside updated_at conventions, native PostgreSQL locks, retry/idempotency and authenticated HTTP need deployment-level tests before production use. PGlite fixtures prove candidate SQL behavior, not production grants or serializable network approval.

## Verification

Run `node tool/verify_partner_company_profile.cjs` with pinned @electric-sql/pglite supplied by the repository's fixture environment (or PGLITE_PACKAGE pointing to that package). Local fixture: 34 checks pass for missing/complete readiness, reciprocal omission, pending/disabled/no connection, forged company, internal hook/table denial, owner/admin versus viewer/manager/outsider/blocked/anonymous, malformed value, stale contact/representative CAS and full audit-failure rollback. Fixture values are synthetic.

Official Supabase RLS guidance checked: https://supabase.com/docs/guides/database/postgres/row-level-security . The changelog markdown fetch was unavailable in the web transport; no API/library version changes were introduced.
