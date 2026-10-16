# New additive company common allowances — review-only contract

Baseline `88af2275853faec3971929773dd0ec896824a955`, Issue #273. The candidate
is deliberately OUTSIDE migrations. Merging source does not deploy a database.
No production statements, automatic adoption, existing policy changes, payroll
calculation, individual reflection or daily-report quantities are included.

The existing random-UUID legacy identity lifecycle remains untouched, including
its triggers and history. New catalog rows are the sole current master for NEW
additive items. Existing `company_rate_settings` allowance names, amounts and units
are returned byte-for-value in `legacy_unassigned`: old registrations whose salary
type/unit interpretation has not been assigned. They are never copied into daily,
hourly or monthly lists, normalized, merged by name, guessed into quantities, or
retired by this API. Legacy migration into the new catalog and payroll reflection
need separate explicit contracts. This is not #840's reusable slot-derived ID.

## Contract version 1

All calls require explicit `p_company_id`; no first-company inference. Private
checked-definer functions use empty search_path and current DB membership plus
existing `private.account_access_allowed() IS TRUE`. Public wrappers are invoker.
No existing auth/RLS/helper/role/provider is replaced. New private tables have RLS
and no direct client/service-role grants. No PUBLIC/anon execute. API read access
is owner/admin/viewer; manager/member/outsiders fail. Editing and own-actor receipt
lookup require owner/admin. Viewer cannot save or access receipts. History is
price-bearing and follows the same owner/admin/viewer read scope.

- `read_company_common_allowances_admin(p_company_id)` returns
  `{contract_version:1,company_id,can_edit,version,items,legacy_unassigned}`.
  Version starts at zero, items empty; read never creates rows. Each active item:
  `{id,payroll_type,section,unit,name,amount_yen}`.
- `save_company_common_allowances(p_company_id,p_payroll_type,p_expected_version,
  p_request_id,p_items)` saves ALL active sections/units for exactly one salary
  type. Other salary types remain exact. Types: daily/hourly/monthly; section:
  earning/deduction; unit: hour/day/month. `p_items` is max100 elements and its
  PostgreSQL JSONB UTF-8 text representation max131072 bytes. Each element has
  exactly `{id,client_key,section,unit,name,amount_yen}`. New id is JSON null;
  existing id is the permanent UUID. Client keys are unique ASCII letters/digits/
  underscore/hyphen, length1–120. Name trims to1–80 characters. Amount is a JSON
  integer0–2147483647. No numeric string/fraction/negative coercion. Same-name
  separate IDs remain separate. Existing UI may impose a stricter same-name
  validation; the server never name-merges data.
- Save returns state plus `{request_id,committed_version,id_map:[{client_key,id}]}`
  for ALL submitted items. Server allocates UUID once, stable across renaming/
  price edits. Omitted active IDs of that salary type are retired, not deleted.
  Retired IDs cannot be revived or moved to another type/company. Add-again gets
  a fresh UUID. Section/unit may be explicitly edited without replacing the ID.
- Version is company-wide0–9007199254740990 on input. Company row then membership
  then catalog state are locked. Membership is rechecked AFTER company lock wait.
  Stale CAS raises40001. Identical actor/request/payload replay returns the EXACT
  original result without a second write; changed payload or actor reuse raises
  22023. This is duplicate-transport defense, NOT permission for the UI to resend
  an unknown operation. The UI must stop new writes and perform receipt READ.
- `read_company_common_allowance_request(p_company_id,p_request_id)` returns
  `{contract_version:1,company_id,request_id,found:false}` or adds `found:true,
  actor_id,payroll_type,expected_version,request_payload,committed_version,result`.
  `request_payload={payroll_type,expected_version,items:ORIGINAL_p_items}`. Exact
  company/actor/request/payload/result match is required for unknown resolution.
  `found:false` is UNRESOLVED: an in-flight transaction may not yet be visible.
  A different administrator can inspect bounded history but not another actor's
  own-receipt endpoint. An old receipt result is historical, not the latest state;
  refresh state before another edit, preserving other-type local drafts.
- `read_company_common_allowances_history(p_company_id,p_before_version default
  null,p_limit default50)` returns `{contract_version:1,company_id,entries,
  before_version}`. Entries descending version with actor/time/type/request and
  before_value/after_value active snapshots for that type. Limit1–100; cursor is
  the oldest returned version when older rows exist, otherwise null. Histories
  and retired IDs are never pruned by this stage.

42501 means explicit authorization rejection,40001 version conflict,22023 invalid
input/ID/request reuse. Missing RPC, malformed success response, network error and
unclassified5xx are NOT success and must never trigger legacy writes or blind
retry. Current application pre_request and session handling are not replaced; this
SQL fixture does not prove real JWT logout/provider behavior. Own auth roles are
synthetic fixtures only.

## Verification and restoration boundaries

The PGlite/PG17 harness replays the three real old savers and random-ID migration,
explicitly adopts only synthetic legacy slots, then tests new catalog changes.
It verifies no backfill, same-name preservation, stable rename/retirement/new ID,
all type/section/unit axes, foreign/retired/duplicate IDs and input limits, CAS,
receipt exactness after later edits, read/edit roles and changed membership,
private-table denial, failed audit atomic rollback, history pagination, old company/
role/settings/identity/history/payroll/daily/signature full-field equality. It drops
ONLY the new schema/APIs to restore the pre-candidate state, recreates them, and
restores its own isolated new catalog/receipts from a memory snapshot. This is a
synthetic restoration exercise, not a full production backup or disaster-recovery
claim. The separate native two-connection check must observe actual PG lock waits,
stale-write rejection and committed role downgrade before the waiting write.

No production rollout is authorized. Full protected DB/Auth/Storage/config backup,
isolated full restore, real administrator/company/provider preservation, existing
UI comparison, actual JWT/Data API checks and explicit impact approval remain
mandatory. No migration is automatically enabled and no runtime credential is
required. Do not run the review SQL against production.

References checked: current Supabase Database Functions and RLS docs via search_docs.
Changelog markdown fetch returned unsupported-content-type; no version-specific
new API is assumed. The implementation uses standard transactions, JSONB, row
locks and fixed function privileges.
