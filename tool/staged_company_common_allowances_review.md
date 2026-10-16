# Existing company settings: additive editor contract (review only)

Baseline main `79249015d02363126b4c978a070271159bf285ca`, Issue #273.
SQL is OUTSIDE migrations; no production apply or payroll/daily calculation change.
This supersedes the saved readonly-legacy experiment `670932dd`, which must not be
merged as the final contract. Existing company settings remain canonical.

## One logical catalog; existing links stay intact

The original three `company_rate_settings.allowance_[1..3]` name/amount/display-unit
columns remain the ONLY current values for those three items. Their existing
random UUID lifecycle (`20261009201229_company_allowance_identity_lifecycle.sql`)
is a required staged dependency; its functions/triggers/ACL are NOT replaced. The one original attendance unit-read
RPC receives an explicitly guarded price-free compatibility call; its OID, owner,
ACL, SECURITY DEFINER flag, arguments and search_path stay unchanged.
Read has no side effects. First explicit confirmed allowance save compares the
full original source, calls its existing adopt() once, and edits legacy + extras
atomically. Existing adopted IDs are retained. Rename/price/display-unit edits keep
UUID; blank retires; later refill allocates a new generation/UUID. Slot-derived IDs,
name matching, quantity inference and three-pay-type copies are forbidden.

Legacy references occupy the first three rows in ALL pay-type day/earning groups:
`applicability=all, section=earning, unit=day`. This is a UI grouping; `source_unit`
retains the original free display unit (e.g. 回/組). It is never forced to 日 or used
to move the item into hour/month groups. Explicit display-unit edits are permitted with original validation only when
they do not change an already-observed name→unit mapping. Ambiguous same-name unit
changes wait for a future dated-history contract and are safely rejected. Unedited NULL/blank/spaced names and display units stay
exact, including when only extras are saved. Existing invoice/payment/site links
continue to read the same old columns. New extras are the extension only, stored
once in the new private catalog. No existing payroll calculation is reimplemented.
Individual payroll reference integration is a separate task; no automatic payment
or duplicate legacy calculation is introduced by this stage.

## Exact contract version 1

`read_company_common_allowances_admin(p_company_id)` returns:

```
{contract_version:1,company_id,can_edit,version,
 expected_source:{legacy_adopted,legacy_version,legacy_slots:[
   {slot,name,unit,amount_yen} // exactly 3 raw original slots
 ],tax_rate,welfare_rate},
 tax_rate,welfare_rate,
 legacy_refs:[{slot,id,generation,applicability:'all',section:'earning',unit:'day',
               name,source_unit,amount_yen}],
 items:[{id,payroll_type,section,unit,name,amount_yen}]}
```

IDs/generations in unadopted/blank legacy refs are null. New item lists initially
empty. No new column backfill. Missing original settings fails55000 rather than
inventing defaults. Tax/welfare numbers use percentages:10 means10%, not0.1.

`save_company_common_allowances(p_company_id,p_payroll_type,p_expected_version,
p_expected_source,p_request_id,p_items,p_legacy_slots,p_confirm_adoption)`:

- Pay types daily/hourly/monthly; extras save ALL sections/units for exactly that
  pay type. Others remain unchanged. Section earning/deduction, unit hour/day/month.
- Each extra exactly `{id,client_key,section,unit,name,amount_yen}`. New id null,
  otherwise active existing same-company/type UUID. Unique ASCII client_key
  `[A-Za-z0-9_-]{1,120}`, name trimmed1–80, JSON integer amount0–2147483647.
  Max100 extras/type, PostgreSQL JSONB text UTF-8<=131072bytes. Same-name IDs remain
  distinct. Omitted active IDs retire; retired/foreign IDs cannot be revived.
- Legacy input exactly3 ordered rows `{slot,id,generation,name,source_unit,amount_yen}`.
  Slot/ID/generation must match observed refs. Names may be null/blank to retire;
  max80 characters, amounts nonnegative integer bounds. Display unit explicitly
  changed must be nonempty trimmed1–12; unchanged old raw text is retained.
  No legacy IDs are accepted as extras and no new IDs replace old legacy IDs.
- Company-wide new catalog version is CAS integer0–9007199254740990 on input.
  Full `expected_source` is ALSO compared: old combined writers may advance their
  legacy version twice, or old tax writers may update company values without
  touching the new version. Never assume legacy version+1. First adoption needs
  `p_confirm_adoption=true`; source match, old adoption/edits, extras/history/receipt
  share one transaction. Old columns update ONLY when explicitly changed.
- Result is read-state plus `{request_id,committed_version,id_map:[{client_key,id}]}`
  for all extras, including existing UUIDs. `legacy_refs` contains resulting old IDs.

`save_company_common_tax_settings(p_company_id,p_expected_version,p_expected_source,
p_tax_rate,p_welfare_rate,p_request_id)` edits ONLY companies.tax_rate and
companies.default_welfare_rate;0–100, max4 fractional digits. It uses the same
company/source CAS, new version/receipt/history. It never adopts old allowances or
updates any old rate/slot/identity column. Result adds id_map:[] to read-state.

`read_company_common_allowance_request(p_company_id,p_request_id)` returns
`{contract_version:1,company_id,request_id,found:false}` or adds:
`found:true,actor_id,operation,payroll_type,expected_version,request_payload,
committed_version,result`. Allowance payload is exactly
`{operation:'allowances',payroll_type,expected_version,expected_source,items,
legacy_slots,confirm_adoption}`. Tax payload is exactly
`{operation:'tax',expected_version,expected_source,tax_rate,welfare_rate}` and
payroll_type null. Receipt binds actor/company/request/operation/full payload.
Same request/actor/payload transport replay returns original result without a
second write; different operation/actor/payload raises22023. UI must NOT resend
unknown outcomes: freeze journal before dispatch, resolve by exact receipt read.
found:false is unresolved, not proof of rollback. Historical receipt result is
not current state; reload before another write and preserve other-type drafts.

`read_company_common_allowances_history(p_company_id,p_before_version default null,
p_limit default50)` returns `{contract_version:1,company_id,entries,before_version}`.
Descending versions,1–100 per page. Entries contain company/version/actor/time/
request/operation/payroll_type/before_value/after_value. Allowance values contain
`{items,legacy_refs}`; tax values `{tax_rate,welfare_rate}`. Cursor oldest returned
version only when older entries remain; never delete old history/retired items.

## Authorization, locks and failure boundaries

New checked-definer functions in a private RLS schema have fixed empty search_path;
public invoker wrappers only. No direct table grants or PUBLIC/anon/service execute.
Current DB owner/admin/viewer can read prices/history; only owner/admin can edit or
read their own receipts. Managers/members/other companies/anonymous are denied.
Existing account helper must return TRUE. Original verified JWT role, nonanonymous
status and UUID session_id must match a live own auth.sessions row/not_after. This
changes no existing auth/roles/providers. Existing legacy source/owner/SD/search_path/
execute grants have strict drift guards before any new DDL.

Lock order: company row -> existing settings -> old identity state -> membership /
original session shared locks -> new state. Recheck permission/session AFTER waits.
Session locks serialize revocation during a write; account restriction insertion
has no phantom-row lock, so no instantaneous global cancellation claim is made.
Concurrent source changes reject40001; invalid data/ID/operation reuse22023;
authorization42501. Missing API, malformed success response, network/unclassified
5xx/unknown outcome is not success and must not fallback to a legacy write.

## Verification and deployment stop

PGlite/PG17 harness replays the real existing three savers and random-ID migration.
Tests cover unadopted raw NULL/blank/spaced preservation, confirmed adoption,
old ID continuity/retirement/new generation, all/day grouping, extras stable IDs,
strict limits, duplicate/foreign/retired IDs, old combined +2 version detection,
tax-only first-save no adoption, tax two-column-only equality, exact operation-
bound receipts after later updates, viewer/role/actor/session/expiry denial,
failed history rollback of old+new data, pagination, source/config drift, original
function OID/body/owner/ACL equality except the one explicitly guarded unit-read
body change, and all finalized payroll/daily/admin/session equality.
Native two-connection tests must observe actual lock waits for new/new and old/new
writers in both directions, and role/session revocation before waiting write.
The new catalog is snapshotted only in memory, dropped/recreated and restored in
isolation with old source unchanged. This is NOT full production recovery proof.

No full migration deploy or production write is authorized. Full protected backup
(DB/Auth/Storage/config), isolated full restore, real admin/company/Apple/Google
preservation, real JWT/Data API and UI comparison plus explicit rollout approval
remain mandatory. This staged dependency is not present in production; client must
show unavailable when missing, preserve drafts and never pretend successful save.

Supabase current functions/RLS docs checked through search_docs. Changelog markdown
fetch failed unsupported-content-type; no new version-specific API is assumed.


## Phase 1 past-unit compatibility (intentional behavior boundary)

At first explicit allowance adoption/save, save the EXISTING old RPC name→unit
projection as a price-free company baseline. This preserves its exact trim/default/
last-slot-wins behavior; it does not reconstruct pre-adoption history. The old RPC
then merges that baseline with current units. Renaming/retiring an item retains old
name/unit aliases, so month/day PDF and attendance consumers using the existing API
can still resolve their old names. Ordinary company members retain this price-free
read; new price/history access is not opened. No attendance/PDF source is modified.

A narrowly scoped AFTER UPDATE trigger on existing company settings protects only
companies with a baseline. A current map cannot change the unit of any name already
observed in a prior transaction or initial baseline. This includes a duplicate-name
winner being deleted and exposing a different unit. Such an operation raises22023,
rolls back old/new values and histories and leaves the UI draft intact. An entirely
new name first introduced by the SAME transaction may settle its final unit during
the old combined saver's two updates; first-observation transaction identity uses
postmaster-start time plus full transaction ID, not a reusable slot/user identity.
Other original writers and authorization remain unchanged. Source-unit editing is
therefore explicitly partial until dated records exist; do not claim all unit
changes are complete. Unknown current access is not evidence of historical values.

The candidate checks the actual old unit-read prosrc MD5
`17310735021c3a953a093ed196261468`, owner/SD/search_path and auth/anon permissions before
its sole body replacement. CREATE OR REPLACE preserves existing OID/ACL including
an existing service_role grant (the synthetic migration may omit that grant).
Restoration must first reinstall the exact pre-candidate unit function, then drop
only the new schema/APIs/triggers; tests restore its original OID/ACL before a
reapply and restore the price-free baseline together with the new catalog.
