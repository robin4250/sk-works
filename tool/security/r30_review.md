# R30 — moderation SECURITY DEFINER boundary candidate

Review-only SQL outside migrations; no production DML/DDL, business-row reads, user/role changes or payroll calculation changes. Five new files only. Reuses R26 classification/policy work and full R19–28 fixture chain. The new catalog captures function source/owner/ACL/config metadata only; it contains no business records.

## Concrete residual path

The actual `public.content_review_queue()` invoker wrapper calls the actual private definer queue, which calls postgres-only `private.content_review_payload(text,uuid)`. The latter bypasses table RLS. It checks reviewer/review-required/author-visibility, but note/album/photo paths have no group classification. Its message/attachment origin gate allows ordinary-origin content inside a known private analysis group, and when the LINE capability is enabled does not filter by known analysis group at all. Thus R26 restrictive row policies do not close definer return values. Direct authenticated EXECUTE on payload is not asserted: the actual payload ACL is postgres-only.

Actual `public.chat_report_queue()` returns stored body_snapshot through a private definer using company-admin and origin/capability gates, without analysis-group classification. Actual `review_chat_report` similarly changes hide/status on a known analysis message without group classification. The report-creation RPC already calls `can_access_communication_group`, whose R26 guard is reused; it is cataloged but not patched again.

## Minimal candidate

A private non-client-executable helper resolves an existing message/attachment/note/album/photo to its actual group ID and calls authoritative R19 group classification. Unknown/missing kind/content returns false; NULL classification fails closed. It neither infers provenance from titles nor changes ordinary group membership or moderator authority.

Four exact-source patches add this predicate to payload entry, content queue BEFORE LIMIT, report queue and review-report entry. Filtering queue rows avoids leaking kind/ID/revision metadata with null payloads and avoids consuming the original 50-item limit with protected rows. All original company/reviewer/author visibility/review-required/origin/capability/status checks and the original ordinary mutation body remain intact. Known analysis content remains available only where both Master classification and original moderation conditions allow it. This does not turn all moderation or ordinary SKO chats into Master-only features.

Source hashes, postgres owner, SECURITY DEFINER and empty search_path are prerequisites. Replacements preserve OID/owner/ACL/config. A late source drift causes the transaction to roll back earlier replacements and the new helper. No approval decisions, review state or content rows are migrated/deleted.

## Isolated evidence

The fixture installs the exact catalog definitions and public wrappers, creating only synthetic content/reviews/reports. Before candidate an ordinary company admin receives all 10 queued kinds (5 ordinary plus 5 known-analysis) with non-null payloads, receives both report snapshots and can hide known-analysis content. After candidate only ordinary 5 content entries / 1 report remain for that admin; Master retains 10 / 2 subject to original rules. Ordinary report hiding and Master protected report dismissal still work. Other-company reviewer receives zero; disabled-Master ordinary admin retains ordinary content only; NULL helper yields zero content and denies protected mutation. Exact original source/OID/owner/ACL/config restoration and late-drift rollback are verified. Full prior chain remains unchanged.

Local PGlite: 24 checks PASS; actual PostgreSQL17/PostgREST CI must be recorded separately. HTTP exercises real public content/report queue wrappers and protected report-review refusal. It does not expose a new public payload probe. Role/reviewer/author/capability helpers in the fixture are explicit synthetic dependencies, not full production provider/role/UI proof.

## Remaining conditions

- Production unchanged; this is a source candidate, not deployed protection or TestFlight safety approval.
- Full production backup/Auth/ACL restoration, exact live stage metadata comparison, normal moderation UI comparison, admin/role preservation and explicit approval remain mandatory per R29.
- Classification covers known authoritative analysis group lineage only. Unknown provenance, deleted-source report snapshots, cached/push/exported data and public/signed Storage delivery remain separately unverified; missing-source snapshots are conservatively excluded by the new helper.
- This does not resolve Master-private approval workflow, enumerate every service-role/definer writer, or erase already-delivered data.
