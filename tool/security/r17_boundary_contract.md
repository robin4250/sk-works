# R17 boundary design exercise — not a deployment

Source checkpoint: main `c9fe3dd8b328966686a980d009315b52a7d65761`.
Read-only deployed definition/policy inspection: 2026-10-17 JST.
No business records, images, credentials, notifications or signed URLs were read.
No production data, settings, Auth, permissions or storage objects were changed.

## Required boundary

LINE-imported historical sources, analysis, derived attendance and generated
documents stay within the existing enabled Master identity and existing legitimate
company/group scope. Ordinary SKO chat, invoices, attendance and payroll retain
their current behavior. Existing shared generated records must be preserved;
neither deleting them nor silently reverting ordinary payroll data is acceptable.
No title/name/prefix inference is an authorization rule. No new credentials or
Master IDs are introduced. Neutral internal names do not replace authorization.

## Confirmed current gaps

The already implemented two-script TestFlight candidate closes the common LINE
actor gate and eleven public RPC entry points while preserving saved settings.
It does not protect every derived artifact:

* `private.create_line_invoices` inserts ordinary `public.invoices`; historical
  generation also embeds source messages/rows in `line_historical_quote_evidence`.
  Deployed invoice SELECT uses `can_view_invoices`, without LINE lineage gating.
* `private.submit_line_attendance` delegates to ordinary
  `public.submit_past_attendance_request`; ordinary correction/attendance readers
  are not Master-only. Do not alter calculations or payroll integration here.
* Analysis creation uses an initially creator-only ordinary company chat group.
  Later membership is handled by ordinary group authorization, not Master status.
  Notes/albums/items and their Storage helpers also lack LINE lineage boundaries.
* `app_notifications` SELECT checks recipient identity; hiding its destination
  does not retract an already delivered title/body. Generation and payload handling
  need explicit lineage-aware protection. No actual notification was inspected.

Existing message-origin restrictive policies protect LINE chat rows and referenced
chat attachments once the staged actor lock is applied. They do not automatically
classify copied notes/albums or ordinary generated invoices/attendance as LINE.

## Classification contract before any deployment

Authoritative server-owned references exist in
`private.line_history_analysis_groups`, `private.line_chat_source_links`,
`private.line_invoice_submissions`, `private.line_historical_invoice_links`, and
`private.line_attendance_submissions`. Treat these as evidence, not writable client
labels. Follow exact company/object FK relationships, including descendants.
Invoice evidence keys can detect a missing-link inconsistency; they must not be
the sole mutable authorization authority. Never classify by displayed text.

A new protected registry would require complete, transactional, server-maintained
coverage of group descendants, generated invoice IDs, correction request/items,
accepted attendance IDs, exported objects, notices and search projections. A known
LINE object with missing/inconsistent lineage is unresolved and must not become
ordinary by omission. Master review must resolve it without data deletion. The
fixture denies unresolved/mismatched references even to Master; a legitimate
separate repair/read procedure is still needed before rollout to avoid lockout.

Absence of a registry row DOES NOT prove an old object is ordinary. The synthetic
fixture's absence-means-ordinary rule is limited to explicitly seeded known ordinary
objects. A production solution cannot use that rule until completeness is proved.
Legacy mixed data and copies with no trustworthy provenance remain unclassified;
do not apply guessed restrictions or claim full isolation. Preserve all originals
and use a protected reconciliation plan before granting normal publication.

## Proposed selective enforcement and remaining work

Use additional restrictive predicates on positively classified linked artifacts,
AND with existing authorization, rather than replacing ordinary company/group
rules. An enabled Master remains subject to existing account/company scope. Do not
rewrite `can_access_communication_group` globally. SQL definers and generic payload
RPCs need explicit checks because RLS alone may be bypassed by their owner.

The required reachability matrix includes direct REST, ordinary invoice preview/
approval/trade-document RPCs, correction/acceptance RPCs, notes/albums moderation,
global/group search, notification enqueue/read/push payloads, Realtime subscribers,
Storage new downloads/signing, cleanup alternatives and exports. Existing signed
URLs and already downloaded bytes are not recalled by row-policy changes. Hosted
CDN/cache behavior requires separate proof; deleting preserved objects is excluded.

Before production change: protected definitions/ACL/owner/config and dependencies,
settings and membership snapshots, tested exact restoration, real Master/admin/
delegated-user compatibility, complete lineage classification, actual endpoint
negative/positive tests, impact report and explicit final approval. Current two-table
device/admin restore does not prove restoration of this data boundary.

## What this fixture proves

An in-memory PGlite fixture uses NEW synthetic tables/functions and actual SQL RLS
to demonstrate the ordinary company-policy bypass, then a selective restrictive
predicate for ten artifact kinds. It checks ordinary-data preservation, legitimate
Master company access, non-Master/foreign/anonymous denial, unresolved/mismatched
reference refusal and restoration of the original behavior without row changes.
This is a design feasibility test, NOT execution of deployed SKO definitions,
PostgREST, GoTrue, real Storage, RPC payloads, Realtime or complete provenance.
No production-ready SQL or automatic migration is supplied by this change.
