# Four original company rates: dedicated editor API (review only)

Child of PR1152 exact `36aae2be9ba6783cdf5d7a8446a55f5edc9d7e34`.
Original candidate files remain untouched. This separate review-only SQL is OUTSIDE
migrations and is not deployed. It restores the four rate-editing entry fields in
the combined settings flow without calling the old tax/allowance full saver.

The only current source remains `company_rate_settings`:
`overtime_hour_rate_yen`, `early_hour_rate_yen`, `night_hour_rate_yen`,
`holiday_day_rate_yen`. No copy, calculated default, payroll formula, tax-inclusive
conversion, separate price master or new stable IDs. Explicit edits write those
four columns plus the existing updated_by/updated_at metadata. All three legacy
allowance columns, companies tax/welfare, roles and source IDs stay untouched.
The existing legacy trigger may advance its version/history when the settings row
is updated; it must retain the same random UUIDs and names/amounts/display units.
The old-unit compatibility map remains unchanged and no tax UPDATE is issued.

## Independent contract version 1

Existing common read/state/expected_source and tax/allowance input shapes are NOT
changed. The two new public invoker wrappers are:

- `read_company_common_rate_settings(p_company_id uuid)` returns exactly
  `{contract_version:1,company_id,can_edit,version,rates}`. `rates` is the four named
  original columns above, with their current values; read never creates rows.
- `save_company_common_rate_settings(p_company_id uuid,p_expected_version bigint,
  p_expected_rates jsonb,p_rates jsonb,p_request_id uuid)` returns that read shape
  plus `{request_id,committed_version,id_map:[]}`. Both rate maps are original units
  of integer yen, no percent/division/tax conversion. New rates have exactly four
  JSON numeric integer values0–2147483647. Unedited values must be sent unchanged.
  A missing original settings row fails; no default or old full-save fallback.

The existing company-wide catalog version is shared. The original observed-four
snapshot is ALSO compared under row locks, because old rate savers do not advance
that new version. Old tax/legacy changes alone need not be overwritten or touched
by this independent four-column API. Concurrent new tax/allowance saves advance
the shared version and invalidate the rate draft. Company→settings→old identity→
member/session→new state order and post-wait reauthorization reuse the exact guarded
1152 lock helper. Owner/admin may edit; owner/admin/viewer may read; no manager/
ordinary/other-company/anonymous price access. Existing account helper must be TRUE
and original session_id must belong to an unexpired own auth.sessions row.

The shared receipt table adds operation `'rates'`, payroll_type null. Existing
`read_company_common_allowance_request(company,request)` returns an own-admin
receipt whose exact payload is
`{operation:'rates',expected_version,expected_rates,rates}` and result is the exact
original successful response. Actor/company/request/operation/payload are bound;
reuse for tax/allowance/different payload is rejected22023. The UI journals before
sending, does NOT resend uncertain requests and resolves only by exact receipt
read; found:false remains unresolved. Same-request transport replay is idempotent
server protection, not permission for UI retry. Late receipt is historical, not
current state; reread before another edit. History uses operation rates with
before_value/after_value each `{rates}`. Existing caller shapes are unchanged.

CAS conflict40001, invalid input/request reuse22023, permission/session42501.
Unclassified5xx/network/malformed success/missing RPC is not success. Preserve drafts
and unknown journals. A valid own session check is not a new short-lived single-use
reauthentication proof; PostgREST JWT expiry enforcement and real provider logins
are outside this SQL fixture. Existing Auth settings/roles/providers are unchanged.

## Isolation evidence and rollout limit

The fresh PGlite/PG17 fixture replays real old company savers, the staged original
random-ID migration and exact1152 candidate, with fake companies/actors/sessions.
Tests compare old company tax/welfare/roles/sessions/legacy columns/UUIDs/alias maps/
function OIDs/source/ACL/payroll/daily values; only the four tested rates and update
metadata change. It verifies zero tax UPDATE spy events, no first-save implicit
legacy adoption, same-value rate preservation, existing metadata actor/time,
observed-four conflict after an actual old saver, shared operation-bound receipts,
limits/roles/actor/session denial, failed audit transaction rollback and dropping/
reapplying only the new five functions without changing existing sources or data.

The dedicated PG17 race check must observe five actual row-lock waits: new/new CAS,
old/new original-four conflict, new tax/rate shared-version conflict, and committed
role downgrade/session expiry before a waiting rate save. Synthetic actor claims
are not real GoTrue/Data API proof. No PDF/render/device verification is claimed.

Existing versionless old full-save APIs are not removed or modified; an authorized
old client can still issue their original writes and tax-trigger side effects.
This API protects its own observed snapshot and does not claim every installed old
client has migrated. New settings routes must use only the new narrow endpoint.

No production mutation is authorized. Full protected backup, isolated production-
like restore, real administrator/company/Apple/Google preservation, UI/REST/session
checks and explicit production impact approval remain required. Source merge is
not database deployment. Do not run this review SQL against production.
