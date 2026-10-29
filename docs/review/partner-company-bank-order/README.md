# Supplier company bank and order PDF candidate (review only)

The existing supplier list/model has no supplier bank fields. Metadata-only
production inspection found no bank columns on partner_companies,
partner_payment_settings or trade_companies. Worker personal-bank storage is a
different domain and is never reused. No account values or business rows were
read and no production schema, policy, data or setting was changed.

The management contract follows the actual partner_payment_settings policies and
current_company_admin_id: owner/admin/manager in the selected company. It does
not infer payroll-worker authorization. Original order reads retain those three
roles and saved-order writes still delegate to the original owner/admin guard.

`bank.sql.review-only` creates a private, default-OFF, append-only bank-version
master with exact company/partner, live SID, account-access and active-partner
checks, 7 ASCII account digits, required five fields, CAS, and actor/SID/request
idempotency. Ordinary clients cannot read or mutate the table directly. UPDATE,
DELETE and TRUNCATE are refused; privileged DDL/owner rollback is out of scope.

`order-snapshot.sql.review-only` guards the exact current original function
body hashes, ACLs, owner, search_path and security attributes before delegating.
The captured original source body is fixture/recovery code only; it contains no
business rows. It includes already deployed directory/profile/tax extensions
missing from the oldest repository migration, which must not be overwritten.
The renamed save delegate is owner-only to prevent a direct authenticated bypass;
the canonical save RPC retains its original authenticated ACL and guards.

Only a new unsaved, unlocked monthly order obtains the current supplier-bank
snapshot. Client-supplied bank fields are replaced by the authoritative snapshot
on first save. Existing saved snapshots (including absence), finalized/missing
historical appendices, source_changed checks, originals, signatures and source
revisions stay under their original rules. Later master updates never rewrite a
saved PDF/appendix. Rendering reads only the supplied frozen payload and makes no
live bank lookup. No new acceptance/legal wording is introduced.

The separate `PartnerCompanyBankPage` receives privacySession, expectedCompany,
partnerCompanyId and partnerName. Root owns the small People partner-sheet button
hook; no raw bank data is loaded into the People list. The page owns private
navigation, clears controllers and stays masked after scope/background loss,
uses exact captured bearer/gateway/privacy admission, and never blindly retries
an unknown save. Backend absence or OFF is shown as preparation required.

Local isolated exact-SQL checks exercise synthetic Auth/catalog fixtures; native
PostgreSQL, Flutter/SDK/widget and actual PDF evidence must be read from their
CI outcomes. No synthetic fixture is real GoTrue or production authorization.
Deployment, activation, real bank registration and device delivery are separate
unfinished stages; these SQL files are not migration/activation instructions.

The bank scope reuses the exact reviewed require_reauthentication_session helper
(hash b5c8e2f..., owner/config/ACL pinned): actual anonymous/banned users, deleted
or expired SID, and the deletion barrier stay enforced. It locks the selected
membership and active partner FOR SHARE, rather than relying on unlocked EXISTS.
Native disposable races exercise revoker-first denial/no append and writer-first
ordering; they are synthetic Auth fixtures, not a real GoTrue enrollment test.
