# Administrator's own document correction — review-only candidate

An administrator with no other eligible reviewer cannot finish a correction to
their own registered document through the employee request/other-actor approval
workflow. This candidate introduces a separate purpose and never approves those
requests. The old request module, its source and its OFF deployment proposal are
unchanged.

Authority follows qualification PR1497: current owner/admin/manager **and** the
existing `can_manage_people` permission. The target must belong to the same actor's
active worker in an explicit company. Every call checks the actual live SID using
the existing reauthentication helper. No role or permission is granted. Employees
with a delegated people permission still cannot use this purpose.

The candidate starts OFF. It is not a migration, deployment approval, connected
UI, new-photo implementation, or an iPhone-ready fix. Source CI is not production
evidence. Production HOLD and all unrelated switches remain unchanged.

## Contract

`public.worker_document_admin_self_correction(action, data)` supports:

| Action | Input beyond explicit company/target | Result |
| --- | --- | --- |
| capability | None | Exact purpose, actor, target, availability; new uploads false |
| correct | Fixed request ID, full reviewed snapshot, reason, exact three metadata fields | Atomic correction and opaque ID-only receipt |
| get | Fixed request ID | Applied/cancelled/unknown; unknown never means success |
| reconcile_cancel | Fixed request ID | Returns applied, or records a cancellation tombstone fencing delayed corrections |

The correction only changes expiry, notes and the order/subset of saved photos.
It resets original verification and records submitted status; attachment/expiry
completion still depends on the normal document evidence rules. It does not write
Storage bytes, add a photo, verify the document or modify an employee approval.
Existing pending employee requests block correction and remain untouched.

Full snapshot CAS, transaction-bound single-use ticket and an append-only private
revision archive retain the original metadata, selected photos, actor, reason,
SID and resulting revision. Original object identities, including removed photos,
are archived with additional restrictive-only Storage UPDATE/DELETE policies.
No public/private archive read or new upload permission is added. The archive is
formal revision history, not temporary prepared command storage.

Unlike PR1497's prepare/apply privacy-v2 workflow, this smaller operation has no
server-stored prepared body. The intended client persists ID-only recovery data
before a single atomic `correct` request, and never stores notes, paths, snapshots,
tokens or file bytes in its journal. Thus it adds no cleanup Cron dependency. A
lost response must be reconciled under the same ID before a new command is made.
The journal and actual UI are still to be implemented and verified.

## Remaining gates

Before production approval: independent review; real helper/catalog/trigger/ACL
composition; Native two-connection lock/cancellation tests; exact original object
retention proof; client captured-Bearer/session/target binding; ID-only durable
journal readback; visible management-correction reason/confirmation/error/recovery;
health-expiry save through the actual entry; guarded OFF installer and unused-only
restore; separate scoped ON approval; Release and iPhone verification.

The isolated tests use pinned actual helper bodies but synthetic users, sessions,
memberships and Storage. They do not prove real GoTrue/Storage deployment, file
bytes, current production authority, or the final product workflow. The actual
old request module is not replaced with a weakened fixture helper.

After use, recovery must be forward-only; do not delete revision archives or
restore original metadata over newer records. Disable new corrections first,
reconcile fixed IDs, preserve receipts and originals, and review a forward fix.
