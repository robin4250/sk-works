# Scoped, audited attendance administrator override

REVIEW-ONLY, DEFAULT OFF, NOT DEPLOYED OR NATIVE-PROVEN YET.

Install order is existing production modules → verified document-only signature module (SQL frozen at Native proof 6f636982; subsequent observed-trigger/NULL-category proof ffc08851 also passed) → this separate module. Document SQL/fixtures were read-only inputs; no document source was edited to build this module.

Place this directory in `docs/review/attendance-admin-override-candidate`; place the workflow in `.github/workflows/attendance-admin-override-native.yml`. The sibling verified supervisor-document directory must exist on the CI branch, including its trigger-source-pins JSON. The loader only extracts its installer, not its 91/255/331 cases.

## Behavior

The existing `public.force_manage_attendance(text,jsonb) -> integer` and the build-17 interface remain the entry point. Existing owner/admin/manager role, `current_feature_permissions.can_manage_attendance`, active-worker/company/site/payload checks, `lock_management_batch`, manual-clock handling and integer result remain. New behavior activates only for an explicit `attendance_admin_override_private.rollout(company_id,enabled default false)` row. No row is inserted by installation. No extra approval request is created.

For an enabled company, the same transaction additionally validates the live actor/session/account and current management permission, takes a complete before-state audit, and creates a private permit tied to backend PID, transaction, actor, auth session, exact company/cells/action, audited reports and the original worker rows. Guard changes permit only the narrowly scoped existing force operations. They do not disable normal signed-fact checks, public DML restrictions, other-company protection, or the document draft writer's independent rules.

Before the first worker deletion, all affected original reports and entire rosters, source clocks/attendance/leave/correction links, actual signature JSON, existing signature events, protocol rows, raw confirmations/ledgers and related vehicle/route evidence pointers are captured. Actual signatures are cleared, and existing audit triggers remain active. New/edited/revived work remains unsigned and requires new actual signatures. No prior strokes are copied into changed content.

The original physical parent DELETE for a report whose final worker was removed is replaced **only in an authorized override transaction** by a cancellation helper. The report and its protocol/ledger FK parent remain. A private cancellation record references the committed operation. Normal authenticated report SELECT gains a restrictive visibility policy; it hides cancelled parents even from ordinary management lists. An ID/company-scoped boolean filter gives false for foreign companies, does not certify arbitrary IDs exist, and returns no report data. The original permissive company policy and existing grants are retained.

Explicit administrative re-registration of the same company/site/day can revive that canonical parent. It records revival actor/time/operation without restoring old signatures. The previous cancellation state and full original documents remain in prior immutable operation snapshots. Current report identity is not replaced with a guessed source ID; no cascade deletion of enrollment, confirmations or ledgers is added.

## Audit and financial boundaries

`operations` records actor/session/action/items, original source snapshot, resulting source snapshot, completion time and a separate `requires_financial_review` flag. That flag is always true for successful administrative attendance changes; it is not an approval request, payroll completion, or fabricated payment evidence. A failed transaction rolls back both mutations and success audit, and leaves no reusable context.

The module changes no financial formula, receipt calculation, payroll confirmation or invoice writer. Existing attendance/report refresh triggers retain their exact observed bodies. It asserts byte-identical protected finalized/manual salary records, finalized salary document/history records, and non-draft invoices/payment certificates for the affected company/month/workers before commit. An unexpected change aborts the complete force operation. Automatic draft projections may be recomputed by their existing source triggers; financial review remains separate from master attendance correction. Old ledger rows/confirmations are retained as history, but cleared/revised report signatures and work epochs cannot silently authorize current facts.

Additional private schema tables are RLS-enabled and revoked from PUBLIC/anon/authenticated/service_role. No caller can issue or replay a permit. The only newly granted public helper returns a company-scoped visibility boolean; no audit or raw signature table is exposed.

The observed current force body is `7de4106cf653bb7b39ab0103ec462853`, including the deployed lock prefix. This is not the older October-4 migration body. Both guard functions are pinned to the verified document-only definitions; six production trigger bodies are pinned without editing them. Source mismatch or unknown install order fails before DDL. Existing function ACLs are retained by CREATE OR REPLACE.

## Verification

`verify_admin_override.mjs` uses the existing disposable-native-PG17 source installer. It loads the exact fresh force and six observed trigger definitions, original clock normalizer/group locks, current manual-writer table/default shape and the verified document module. It runs only new management cases: OFF compatibility; actual reporter and supervisor signature capture; signed-source refusal while OFF; manager edit without approval; complete prior-signature/source audit; other worker row preservation; first/last worker delete; FK parent retention; normal-list hiding; same-cell re-registration; role/feature/foreign-company refusal; late-cell failure rollback; batch integer/count behavior; finalized payroll/document snapshots unchanged; and no forgeable/live permit after completion.

Authentication surroundings and invoice producer surroundings are explicitly synthetic. Invoice refresh trigger body is real; its full invoice producer is not reimplemented or claimed proven. Finalized invoices/payment certificates and salary snapshots are synthetic immutable fixture originals, checked against source changes. Exact body preservation and transactional postflight protection are distinct from a real production business-data trial.

Local checks currently completed: original-force MD5 verification; source-pinned SQL generation; Node syntax checks for loader and generated focused proof. Native execution is pending the supplied GitHub workflow. No local Flutter/Dart was run. No production read/write or actual employee deletion was performed by this candidate.

## Deliberate limits and deployment prerequisites

- The observed force API has no client expected revision/hash parameter. It retains its existing locked source-set rechecks; this module does not claim preview-to-submit CAS or network retry idempotency. Duplicate worker/date cells are refused in active mode. A later command-id/CAS contract is separate work.
- Existing UI second-password protection must remain. The observed server verify-secondary RPC returns a boolean rather than a session-bound authorization receipt; this module does not invent a server-side proof of that screen interaction. It enforces the live session and original management role/feature. If server enforcement of a fresh second-password receipt is mandatory, add that independently reviewed contract before activation; do not infer it from a client flag.
- Review current catalogue/FKs/triggers and compare complete live metadata before application, and preserve private source/data backups. Unknown additional route/vehicle FK restrictions are not disabled. A new failure must remain atomic and be handled through preserved source review, never by dropping CASCADE or removing authorization.
- Finalized business documents remain immutable originals; the new audit is not permission to rewrite them. Any current financial recalculation/reissue uses its own existing review/finalization workflow.
- Switching rollout OFF stops new override entry, but does not undo used audit/cancellation records. Do not remove this module or its cancellation policy after use without a separately reviewed migration. Default OFF installation is not activation or evidence of device completion.
