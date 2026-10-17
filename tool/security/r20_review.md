# R20 selected definer reads and pre-enqueue recipient guard

REVIEW ONLY; stacked on R19. No live deployment, business-data read, source-data
move/delete, payroll calculation or attendance-record mutation is performed.
The catalog contains function source definitions/metadata already represented by
repository migrations, not real payloads, identities, emails or business records.
Catalog checkpoint: 2026-10-17 JST, main c9fe3dd8.

## Narrow changes

Five existing function bodies receive a guard immediately after their first BEGIN:

| Target | Additional rule | Existing behavior retained |
|---|---|---|
| public.invoice_approval_history | R19 invoice linked-read authorization | actor/company test, audit ordering and payload |
| public.invoice_approval_status_rows | same, before ensure-rows call | original company and approver checks |
| public.invoice_approval_status_rows_v2 | same | stamp/date/approver projection |
| private.trade_document_source | same for invoice kind only | payment certificates and existing company/feature/revision locks |
| private.enqueue_notification | positively linked known action requires enabled Master recipient | ordinary notices and legitimate Master recipient insertion |

The notification condition checks the RECIPIENT, not only the calling Master.
A non-Master recipient of a linked invoice-approval/correction-request notice gets
NULL before INSERT. Existing notice rows are neither deleted nor rewritten. R19's
known-action SELECT restriction remains separate. Invoice/attendance calculations,
approval writes, source rows, saved appendices and existing company roles are untouched.

Candidate SQL validates exact prosrc hashes and owner=postgres before mutation.
CREATE OR REPLACE retains function OID/owner/ACL, then verifies owner/ACL/config/
definer metadata unchanged. A mismatch aborts the whole transaction, including
new helper creation and prior patched functions. The new private classifier has
empty search_path and no PUBLIC/anon/authenticated execute. Original search_path
values are preserved, including the legacy enqueue path; they are not falsely
reported as all newly hardened. No function is moved or public access granted.

## Verification and restoration

The runner reuses the EXACT R19 source with SHA256 validation and single hook
anchors, emitting a mode600 disposable source copy. It does not edit or duplicate
the tracked R19 fixture. Each original R19 assertion and cleanup remains active.
The temporary copy embeds this file's exported hooks, avoiding a circular import;
finally removes only that file.

It installs exact captured target definitions in the existing isolated database
with minimal synthetic consumed-column models. ensure_invoice_approval_rows,
company-feature and seal dependencies are minimal fixture models, not claims
about their full production side effects. The trade/notice public probe wrappers
are explicitly fixture-only; they call the real candidate target with its original
internal authorization and cannot prove every production wrapper is guarded.

Before R20, the definer reads reproduce access to a linked invoice despite R19.
After R20, non-Master/disabled-Master reject, proper Master succeeds and ordinary
same-company data remains available. A Master calling enqueue for a non-Master
recipient creates zero new notices. Positive Master/ordinary notice insertion is
checked in a transaction then rolled back, leaving all R19 row snapshots unchanged.
The PG17 job sends real PostgREST signed LOCAL synthetic-JWT RPC requests, not
GoTrue-issued production credentials or device authentication.

Every original target is restored with exact definition/OID/owner/ACL/config
comparison. Deliberately drifting the last target proves earlier patches and the
new helper roll back atomically; then the original definitions are restored again.
No production rollback script or old-data restore instruction is supplied.

## Remaining matrix — not full closure / not TestFlight clearance

| Boundary | This candidate | Still unresolved |
|---|---|---|
| direct SELECT | R19 positively linked rows | null/unknown actions, missing lineage and unidentified legacy copies |
| selected definer reads | listed four read routes | other invoice/detail/expense/search/moderation/download RPCs |
| write / approval RPCs | unchanged | non-Master INSERT/UPDATE/DELETE, approval/cancellation and direct lineage modification windows |
| notifications | known linked enqueue recipient suppression | direct INSERT callers, other action keys, source-generated notices before lineage insertion, external push already delivered |
| ordinary invoices/attendance/payroll | calculation and rows unchanged | final accepted attendance and derived payment/payroll provenance not fully mapped |
| Storage | R19 metadata SELECT only | real Storage origin/service, malformed/unmapped paths, cached/signed URLs and exports |
| anonymous callers | existing ACLs remain | no blanket new anonymous guarantee beyond exact existing boundaries |

Absence of a link is not proof of ordinary provenance. Known null/mismatched path
or action references must not be labelled safe. This candidate only narrows positive
references; unresolved rows remain a rollout blocker, requiring protected audit
and explicit classification. It does not infer identity from titles or worker/date.
Source payload duplication/publication is not authorized by these changes.

Before live promotion: protected snapshot of all target definitions/full ACLs/
owners/config/dependencies, current lineage/settings/admin membership preservation,
actual scoped restoration, legitimate provider/admin/feature compatibility, remaining
read/write/push/Storage closure, impact report and explicit final user approval.
