# Deployed LINE access coverage inventory

Audit source: Supabase project `ztktgquxvcxcjxtluspu`, function/policy/publication catalog SELECT only, 2026-10-16 JST. Source baseline `04d90559c8929c71b0b91f743066795b28007067`. No business rows, media, signed URLs or production writes were used.

This is a manual source trace, not a claim that every listed endpoint passed dynamic tests. 35 deployed public LINE-named RPCs were inspected, together with their private callees. All public wrappers use explicit authenticated/service ACLs; service-only functions are separated below. The proposal in #1127 changes the common actor gate only; it has not changed the live gate.

| Public RPC | Effective existing route to authorization | Ordering | Evidence/limit |
|---|---|---|---|
| `begin_line_group_claim` | direct client gate | Before binding/group query | existing HTTP deny tested |
| `claim_line_chat_dispatch` | service-only → outbound actor gate | Reads ticket before actor gate | SQL queued claim deny tested; HTTP service not tested |
| `complete_line_group_claim_for_line` | service-only ACL | Signed external ingestion/claim path | Not general user callable |
| `create_line_historical_invoices` | require_quote → historical_quote_access → master/client gate | Quote lookup precedes gate | No invoice mutation/receipt response before gate |
| `create_line_history_analysis` | client gate + master | Before queries | Source reviewed; not executed in current fixture |
| `create_line_invoices` | import_access → client gate | Draft company lookup precedes gate | No invoice writes/receipt returns before gate |
| `create_line_shared_chat_group` | client gate → existing group/company | Before group/source query | Existing SQL deny tested |
| `disable_line_group_binding` | direct client gate | Before binding query | existing SQL deny tested |
| `finish_line_chat_dispatch` | service-only ACL | Updates bound lease state | Service completion intentionally preserved |
| `line_chat_sender_preferences` | outbound actor gate | Group company lookup precedes gate | No preference payload/write before deny |
| `line_historical_invoice_expense_preview` | require_quote → historical_quote_access → master/client gate | Quote lookup precedes gate | No expense response before gate |
| `line_historical_invoice_preview` | require_quote → historical_quote_access → master/client gate | Quote lookup precedes gate | No quote calculation/response before gate |
| `line_historical_invoice_workspace` | require_quote → historical_quote_access → master/client gate | Quote lookup precedes gate | No customer/quote response before gate |
| `line_historical_quote_workspace` | historical_quote_access → master + import_access → client gate | Before workspace read | Source reviewed |
| `line_history_analysis_ids` | account + existing group ACL | Reads authorized group IDs | Intentional exclusion metadata; no message/body/name |
| `line_history_destinations` | client gate + master | Before queries | Source reviewed; not executed in current fixture |
| `line_import_features` | account gate | Reads two saved feature flags | Intentional capability metadata, no business rows |
| `line_import_workspace` | import_access → client gate | Before draft/source query | Source reviewed |
| `line_invoice_preview` | require_current_draft → import_access → client gate | Draft lock/read precedes gate | No quote return/calculation before gate |
| `line_joined_group_workspace` | client gate → existing group/company | Before directory query | Existing SQL deny tested |
| `line_known_group_ids` | service-only ACL | Server directory listing | Not general user callable |
| `line_linked_talk` | client gate → existing group ACL | Before message query | Existing SQL deny tested |
| `line_reading_rules_workspace` | master → import_access → client gate | Master check precedes reads | Source reviewed |
| `line_release_capability` | client gate | Returns effective boolean only | Actual signed-JWT HTTP tested |
| `line_shared_chat_groups` | client gate → existing group ACL | Before list query | Existing SQL deny tested |
| `link_line_source_to_chat` | client gate → existing group management | Analysis-ID lookup precedes gate | Existing SQL deny tested |
| `observe_line_joined_group` | service-only ACL | Server observation writes | Webhook ingestion preserved |
| `prepare_line_chat_dispatch` | outbound actor gate | Own outbox/message lookup precedes gate | SQL deny tested |
| `refresh_line_historical_invoice_expenses` | require_quote → historical_quote_access → master/client gate | Quote lookup precedes gate | No invoice refresh/write before gate |
| `save_line_historical_quote` | historical_quote_access → master + import_access → client gate | Before saved quote read/write | Source reviewed |
| `save_line_import_draft` | import_access → client gate | Before saved command/draft read/write | Source reviewed |
| `save_line_reading_rules` | master → import_access → client gate | Master check precedes reads/writes | Source reviewed |
| `set_line_general_release_enabled` | account + master | Before setting write | Saved value cannot bypass distribution lock |
| `set_line_import_feature` | account + master | Before setting write | Existing master setting preserved |
| `submit_line_attendance` | import_access → client gate | Draft company lookup precedes gate | No attendance writes/receipt returns before gate |

## Findings and boundaries

- The historical invoice/quote and reading-rule routes already require master access and ultimately use the LINE client gate. No new ungated business-payload return or write was established in these traced bodies.
- Some wrappers delegate to definers that read/lock internal draft/quote/outbox metadata before their later gate. This is **not** strict authorization-before-every-read. Draft lookup errors can differ (missing ID 22023 versus valid ID then access denial 42501). Their business payload is not returned and mutation/receipt reuse occurs after authorization. New separate review-only `line_testflight_early_rpc_gate.sql.review-only` adds an early guard to 11 public invoker wrappers before delegation. Existing private bodies/calculations are unchanged, original ACL/owner/volatility/config/arguments are retained, and changed source definitions abort the whole proposal. PGlite denial and metadata/drift checks passed locally; the expanded real HTTP matrix still requires current-head CI. The actor-helper proposal alone does not fix this ordering gap.
- `line_import_features` exposes only two feature booleans after account validation. `line_history_analysis_ids` exposes only already-authorized group IDs and is used for exclusion from general lists (#1084); blindly denying it would defeat that filtering. They are intentional metadata exceptions, not permission to use LINE or read invoice/message contents.
- Shared service-only ingestion/observation/finish functions are retained; blocking all service traffic would damage incoming data and valid completion. Queued outbound claim rechecks actor permission before returning the outbound body; already-started external sends are not recalled.

## Direct data, attachments, Storage and Realtime

Actual public policies include restrictive `line_general_release_read` on LINE-origin `chat_messages`, and on bindings/claims/audit. The actor lock therefore intersects every permissive message/read moderator policy. Ordinary `origin='sk_works'` messages remain intentionally unaffected.

Attachment metadata has restrictive `chat safety visible attachments`: sender visibility **and EXISTS a visible chat_messages row**. Its EXISTS runs as the caller (not a definer), so the referenced LINE message's restrictive RLS applies. `storage.objects` has restrictive `chat safety attachment storage`: chat-attachments objects require a visible `chat_attachments` row. This source path means newly authorized reads/signing requests inherit the row gate; it is not an HTTP Storage test and it does not revoke pre-issued bearer URLs. Other restrictive review policies continue to apply.

Group avatar objects (`custom-chat-photos`) use existing group membership, not LINE release capability. They are shared SKO group presentation, not evidence of LINE message access. Notes/album copies with SKO origin are likewise not automatically classified as LINE by message-origin RLS. Whether an existing copied note/album contains historical LINE data requires lineage verification; no production records were read. The deferred #1084 general-list exclusion is separate and has not been silently merged.

The `supabase_realtime` publication includes `public.chat_messages`; this inventory did not perform websocket subscriptions or verify role/permission invalidation timing. Publication presence alone proves neither delivery nor leakage. RLS-based source protections, in-flight event behavior, and historical already-delivered/cached records are distinct. Actual Realtime and Storage signed-URL cancellation/expiry remain separate validation items owned by the authentication/Storage lane.

