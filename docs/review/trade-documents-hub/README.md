# Standalone 注文・請書 — review candidate, production OFF

## Ownership and integration boundary

The standalone entry belongs to management (`owner`, `admin`, `manager`) behind
the existing second protected route. It reuses the formal touch editor and PDF
generator. The two registration-detail generator buttons are moved only in the
same release as a working hub; never deploy those removals independently.
Company editing, existing received documents and archives remain accessible.

`site_order_documents` is the **one master-controlled flag** shared with site
orders. Missing/unknown means OFF. Standalone capability is independent of the
not-yet-installed site archive/approval/notification/delivery modules. A complete
standalone context does not claim those site modules are ready.

The new flag may only be changed through the existing proof-bound master setter.
There is no new proof-free fallback, no local success switch and no flag row
inserted by this candidate. The existing invoice/payment automatic-attachment
preferences and the individual-document-exemption flag are unchanged.

## Server contract

`master-and-standalone-context.sql.review-only` is **not deployed**. It guards
eight captured deployed functions by source MD5, owner, security, volatility,
search path and ACL. Existing master read/proof setter are replaced in place;
their complete `pg_proc` attributes/OIDs are checked unchanged except source.
Existing owner-only profile and seal APIs are **not** broadened.

The new private master gate checks the live captured session through the actual
`private.require_reauthentication_session()` and holds the master setting row
with `FOR SHARE` for the operation. Missing setting is locked/rechecked and denied.
Site commands call this gate and retain their own company/source authorization.

The new standalone access/context APIs additionally require exactly one current
membership in owner/admin/manager and return actor/company/session receipts.
They read only the selected self-owned registration, company contact/representative,
registered seal and configured prose. They do not save contracts, templates,
financial rows, files or deliveries. A disabled registered company seal refuses
new context creation instead of inventing an impression.

The optional bank API is used only via the canonical stored partner ID. An absent
bank module is explicit; malformed or foreign bank acknowledgements are rejected,
including exact envelope keys, integer revision, snapshot revision and available/
null-account consistency. The existing Dart bank validator still validates its
full domain fields; no missing value becomes a fabricated bank account.

## Exact manager context response

`standalone_trade_document_registration_context(p_trade_company_id uuid,
p_acceptance boolean)` returns these required keys:

- `context_contract_version: 1`, `actor_id`, `session_id`, `company_id`,
  `trade_company_id`, `acceptance`.
- `issuer` with name/address/corporate_number/representative_name/phone/fax.
- `counterparty` with name/address/corporate_number/representative_name/phone.
- `template`, `company_seal_snapshot`, `company_seal_enabled: true`,
  `bank_backend_available`.
- Optional order-only `partner_company_id` and `counterparty_bank`.

The formal owner implements the strict receipt loader; new-hub errors never fall
back to the old owner/admin loader. The old null-gate generation route remains
unchanged until the simultaneous entry migration is ready.

## Master OFF and async operations

The hub lease refreshes the captured company/session/role, flag and selected
registration before and after protected operations and retires permanently on
failure. Foreground refresh polls every five seconds and the cached synchronous
lease expires after fifteen seconds. This is **not instantaneous remote revocation**
of a native print dialog or already-exported bytes. The formal page's print
callback also checks its lease, and server operations independently enforce the
live transactional gate. App backgrounding, logout and SDK session change retire
the underlying existing form session.

Original archived documents are not deleted by OFF. Site approval/outbox workers
must pause under OFF without rolling back a completed approval or discarding a
pending receipt. That worker behavior belongs to the site module, not this hub.

## Ordered deployment manifest — not authorization

1. Re-read changed dependencies before any separately authorized production
   application. Preserve the captured source/attributes and a tested recovery.
2. Apply this C master/context candidate against its exact captured baseline.
   Leave the new setting absent/OFF. It does not modify `partner_company_profile_value`.
3. The formal V1 prerequisite and then formal V2 month-end/contact candidate can
   follow. V2 changes the profile value helper's source to add FAX; applying V2
   first deliberately fails this C baseline guard and requires a newly reviewed
   forward composition, not bypassing the hash check.
4. Any other feature candidate changing the same master read/proof setter also
   needs a fresh composed baseline. Never blindly apply two replacements.
5. Site archive/artifact/notification packages have separate capability checks.
6. Production approval, feature ON, public delivery and iPhone verification remain
   separate unfinished stages. This document grants none of them.

## Actual verification and remaining scope

Local PGlite: **48 checks passed**, using eight captured deployed function bodies,
the actual live-session/proof-consumption bodies, calls under `authenticated`, and
synthetic JWT/policy setup. The bank acknowledgement adapter is synthetic because
that optional module is absent from the captured catalog. This is **not live
GoTrue, a production master operation, a signed PDF proof or iPhone verification**.

The predecessor’s 44 checks also passed on CI PostgreSQL 17.6 and PGlite at initial head
`9c4f41b0982bfaf5f065f11562e7c67d3715850e`. The hub client/SDK/UI suite passed
42 tests with a clean analyzer at `3767bcbddf82270bfcf46cb9622956a5df499bb1`.
Those head-specific results do not imply success of a later edited head.

`verify_trade_documents_deployment_order.mjs` additionally ran the inherited
formal fixture with C installed first, followed by the formal V1 prerequisite
and V2. **49 checks passed locally**, preserving the existing negative/financial/
signed assertions, C function identities and attributes, manager context after
the V2 FAX change and OFF denial. Its JWT/policy setup remains synthetic.

Native PostgreSQL and Flutter/SDK/UI tests run in the dedicated workflow; their
results must be checked on the final exact head. No local Flutter SDK is installed.
The formal manager registration loader is inherited from remote source
`b84102d9bfd5210ba3e72c1f65e6a6d4dc32ff30` (tree
`80d3ecad08b0dd42134cc034d453a1e398916f6e`). The hub supplies the
required managed gate for all three management roles and uses only the new
strict server registration context. That composition still needs final-head
Flutter/native verification and independent review before integration. Server
installation/feature ON/iPhone proof remain separate incomplete stages.
