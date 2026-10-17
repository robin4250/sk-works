# R19 selective linked-artifact candidate — REVIEW ONLY

This is a bounded follow-up to #1183, not a replacement or production deployment.
Source checkpoint: `c9fe3dd8b328966686a980d009315b52a7d65761`.
Catalog/column/definition-only inspection on 2026-10-17 JST identified the actual
private lineage column names used by the candidate. No business row, real media,
credential or generated document content was fetched. Production changes: zero.

## Actual candidate scope

`r19_candidate.sql.review-only` installs only six new boolean helpers and nine
additional restrictive SELECT policies. No existing function/policy is replaced,
no role/company/identity/link/source/payload row is updated, and no INSERT/UPDATE/
DELETE or payroll/attendance calculation path is modified. Existing RLS must be
enabled or the transaction aborts. Existing authorization remains an AND operand;
Master status grants no new company/group access. Helpers use empty search_path,
return no payload, and deny PUBLIC/anon execution. Existing-name conflicts abort.

| Artifact | Authoritative existing link | Candidate condition |
|---|---|---|
| invoices | line_invoice_submissions.invoice_id or line_historical_invoice_links.invoice_id | linked rows require enabled Master + account access |
| dedicated analysis groups | line_history_analysis_groups.group_id | same |
| notes, albums, album items | their group_id in analysis_groups | same |
| correction requests/items | line_attendance_submissions.request_id, including inactive history | same |
| notices | invoice_approval or attendance_correction_request action_id to above IDs | same on new database SELECT |
| note/album Storage objects | existing bucket + second path component analysis group UUID | same on new storage.objects SELECT/signing authorization |

No displayed title/prefix is used. Mixed ordinary SKO groups that merely have a
LINE source link are NOT globally restricted. Their ordinary messages keep current
permissions; existing origin-based LINE message and attachment gates remain separate.
The candidate does not relabel or move any data and cannot publish an artifact.

## What this does NOT solve — TestFlight remains blocked

Absence of a lineage row is NOT a declaration that an artifact is ordinary. This
candidate only narrows positively linked rows; unknown historical copies/links stay
unresolved under prior authorization and MUST be reconciled before claiming full
Master isolation. No title inference or speculative data migration is supplied.
An authorized protected audit and explicit classification of orphan/mixed legacy
records is required. Server-maintained lineage inheritance/immutability, transactional
creation ordering and direct mutation routes need a separate review before rollout.

The final accepted attendance entry is not reliably identified by request_id in the
existing lineage. Worker/date matching alone could capture later legitimate manual
edits or payroll results, so this candidate deliberately does not alter final
attendance, payroll, normal payment certificates or their calculation permissions.
Mixed document exports, payment documents derived from such attendance, manually
copied content and missing-link invoice snapshots remain unresolved.

SECURITY DEFINER RPCs can bypass the new RLS. Known review targets include invoice
approval/status/history, trade_document_source/workspace, read_expense_document,
correction approval/detail, moderation payloads and search. These require explicit
checks or safe projections; this candidate does not falsely assert closure.
Push/enqueue payloads may be produced before lineage insertion and bypass SELECT.
The notification policy only protects subsequent matching table reads. Other action
keys, websocket Realtime, cached responses and already delivered content are untested.

The storage policy test addresses metadata SELECT through PostgREST, NOT the actual
Storage service. Existing bearer signed URLs remain usable before TTL; hosted CDN
can retain responses independently. No object deletion, key rotation or cache purge
is proposed. Other buckets and arbitrary path/provenance variants remain unverified.

## Verification contract

One script runs the exact candidate SQL in PGlite and in disposable PostgreSQL17.
Minimal synthetic tables use the catalog-confirmed consumed columns; ordinary RLS
models company scope and deliberately reproduces linked-data access before candidate
application. Master, non-Master administrator, disabled Master, foreign-company
Master and anonymous HTTP cases are distinct. The PG job additionally uses actual
PostgREST v16.4 requests with short-lived LOCAL synthetic signed JWTs (not GoTrue
issuance), including storage.objects metadata with Accept-Profile: storage.

Assertions check linked-row denial, ordinary-row preservation, Master access only
inside existing scope, unchanged row bytes and exact original-policy metadata after
dropping the added policies. This is selected candidate enforcement and restoration
in a minimal fixture, not full production schema or provider compatibility.
No production credential is read; endpoint/database names must match the isolated
localhost fixture. Logs print only fixed summaries, never JWTs/URLs/user data.

Before any live change: protected current schema/functions/all ACL/owner/config,
lineage and related data/settings snapshots; full target restoration exercise;
real administrator/provider compatibility; unresolved-classification resolution;
RPC/push/Storage bypass closure; impact report and explicit final user approval.
The previous actual two-table device/admin restoration does not satisfy this scope.
