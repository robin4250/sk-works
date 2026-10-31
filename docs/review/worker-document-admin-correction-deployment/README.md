# Combined document admission and administrator correction candidate

This source-only stack preserves PR1671's single-company admission, PR1674's
separate administrator-own correction and PR1675's actual entries. The merge
parents retain both reviewed histories. It is not a main merge, deployment or
activation approval.

## Database dependencies

The administrator-own purpose is independent of PR1669's employee request module.
It requires the current existing reauthentication / company-feature helpers,
current company membership, people permissions, active own worker, document
requirements/status/history, and saved-photo retention/Storage baseline.
PR1669 is optional. If its private changes table exists, unresolved old
draft/pending requests block the new correction; the old approval guard and
other-actor rule must remain unchanged and be included in composition evidence.
Do not install the whole old request module solely to enable this purpose.

The new SQL only adds four private tables, three private functions, one public
RPC, three triggers and two restrictive Storage policies. It never alters the
old request module or an existing helper. Its state singleton starts OFF.
Existing private objects are owner-only except the narrow authenticated
saved-photo-retention predicate required by the restrictive Storage policies.
The public RPC requires current live SID, owner/admin/manager role AND
can_manage_people, explicit company and own active worker on every action.
New uploads remain unavailable. Employee and non-own targets keep the original
request route; absent old request infrastructure remains unavailable.

This new switch is global across companies, limited to the authority above. It
does not toggle individual document exemptions, ordering or other rollouts.
The already-approved exemption switch is unrelated and must not be changed.
ON is a distinct production action from installing an OFF module.

## Review and deployment sequence

1. Validate this combined client, actual SDK/form/full-row CAS and current-source
   helper/trigger/Storage composition, including both old-request-absent and
   old-request-present deployments.
2. Prepare an exact-catalog guarded OFF install, separate guarded ON, and
   unused-only restore. Before/after original status/history must match.
3. Present production scope, hashes, expected impact and recovery conditions
   for explicit approval. HOLD remains until then.
4. Integrate only the connected approved scope; build Release and verify
   overwrite install, standalone launch and actual editing/save on iPhone.

## Results and recovery

The ID-only journal is written/read back before one correction request.
An uncertain response is reconciled under the same ID; it is never blindly sent
again. OFF and removed list rows must retain the recovery entry.
A committed terminal receipt survives later requirement/status removal while
current own-worker/company authority remains valid. If there is no committed
receipt and the original status has disappeared, the worker binding cannot be
proven: keep the unknown ID for reviewed operational resolution. Do not claim
cancellation, change identity or weaken authorization.

An unused restore is allowed only before any activation/use, after exact module
and dependency checks, with OFF and no correction/ticket/photo rows. After
activation or use, preserve receipts/revision archives/originals and use a
reviewed forward fix. OFF stops new corrections but must not erase existing
evidence or pretend to undo a committed correction.


The deployment generator also supplies a distinct guarded global stop and a
read-only reconciliation query. Stop acquires the state row UPDATE barrier
before locking original status/history tables, so it waits for an in-flight
correction without inverting the normal write lock order. It changes only this
purpose's enabled flag to false, retains activation evidence, records a fixed
stop ID, and preserves every original/archive. A repeated stop command refuses
changed receipt state: reconcile with the read-only query before any retry.
Recovery-only get/reconcile_cancel remains supported after OFF; stop does not
cancel unknown device journals or restore older content.

## Coordinating the guide and correction deployments

The guide's two new functions change this full function catalog. The correction
trigger changes the guide's relation catalog. Never execute both existing
standalone capsules in sequence without rebuilding the second guard.

The preferred sequence is the separately approved guide install first, its
committed receipt and independent readback, then a fresh complete document
catalog and `guide-function-delta.read-only.sql`. `guide_delta.py` only accepts
the exact two sealed guide functions: every pre-existing function and all other
catalog keys must match, and each new function's full attributes hash is bound
to its exact source/owner/language/ACL receipt. Extra functions, overloads or any
other difference stop. The immutable guide seal is checked by SHA256.

This offline proof never grants application permission or automatically
rebaselines. Root must review the actual known-delta manifest, retain the old
capsule, regenerate a new second-stage guard with the same reviewed correction
runtime SQL, verify its new hashes and independent review before applying the
previously approved semantic scope. Unknown changes require investigation and
any necessary new approval. The guide is not currently installed by this tool.
