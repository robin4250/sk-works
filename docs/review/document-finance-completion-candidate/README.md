# Financial readiness and explicit document-to-financial re-signing

REVIEW ONLY. DEFAULT OFF. NOT DEPLOYED. Readiness71 and explicit re-signing86 Native checks passed at 74625c1b1a8f548419e622fa32dfc6b2c90ddcd2 / run40231886886 (jobs121285176600/121285176727). Subsequent proof-only changes add explicit salary day-count assertions; see the latest PR check. Product SQL is unchanged since b3a7fe71 terminator repair.

These candidates do not make six displayed clock-in days into six paid days. They do not invent a missing report, its work, a category, money, a confirmation or a signature. No production write was performed while preparing them.

## Observed contract gap

A document-only report may have two actual signatures and still have status draft, no individual factual confirmations, no shared-hours ledger and no formal attendance entries. That is the implemented document-only contract, not successful payroll/invoice completion.

The current confirmation writer refuses a report after its supervisor signature has been saved. The existing draft document writer also cannot correct work_category. Thus the current UI label implying factual confirmation is available after both signatures does not by itself provide an executable financial completion path.

The source normalizer requires an explicit work_category and valid registered allowance choices. It rejects an obsolete daily allowance for a currently monthly worker. It never treats NULL as day or silently removes/reprices the saved choice.

The observed worker trigger clears both signatures on any draft worker UPDATE, including a value-identical UPDATE. Existing prepare_supervisor calls materialize_confirmed_worker, which always performs that UPDATE. The new focused proof includes that exact observed trigger body, rather than assuming it away.

## Files and installation order

Existing production modules → verified supervisor-document candidate → verified attendance-admin candidate → optional financial-readiness.sql.review-only → financial-resigning-transition.sql.review-only.

The transition pins the current admin-extended guard_roster and original materializer, plus the exact security/validation dependencies. Readiness does not modify any existing routine. No installer inserts an enabled rollout row.

Publish these nine source files under docs/review/document-finance-completion-candidate (workflow under .github/workflows). Generated *.syntax-only.mjs files are local intermediates and are not deliverables.

## Readiness API is diagnosis, not the repair

public.read_shared_report_financial_readiness(report_id) uses an independent per-report default-OFF rollout. It checks the live actor/session, existing company/read context, actual document signature snapshot, category, current registration, source, confirmation and exact signed raw facts. It returns Japanese actionable reasons instead of technical exceptions. It never invokes a financial writer; can_finalize and completion_supported are false even at an otherwise valid boundary. Do not represent that API as fixing payroll.

## Safe repair path with actual input and actual new signatures

1. The original reporting actor or existing authorized manager uses the already-installed start_shared_report_document_edit. That RPC preserves the old real signatures and original documents in history and clears both current signatures.
2. An authorized manager explicitly supplies the real financial facts, applicable registered choices and actual paid-work hours, with a reason. No server default chooses a category, changes salary type, clears an allowance or infers work from the desired count.
3. Call prepare_shared_report_financial_resigning(report_id, expected_updated_at, expected_signature_scope, workers, reason). workers is an exact same-roster array of {worker_id, facts, hours, expected_revision, expected_scope}. facts is the existing 11-key schema-1 normalized-input contract (schema, overtime_hours, early_hours, night_hours, work_category, allowance_amount, allowance_label, company_allowance_selections, vehicle_id, route_assignment_id, odometer_km). expected_revision/scope come from a fresh existing read_shared_worker_facts for each worker, after the explicit edit/reset.
4. The candidate validates ALL payloads, current closed clocked source, company, manager feature, live session, document CAS and individual source CAS before writing any row. Manual money changes and vehicle changes are refused. It audits before-state/protocol/history, stages exactly the normalized supplied facts under private exact row permits, resets the pending work epoch, exits document-only mode and calls the existing confirm_facts with the real manager's explicit payload/reason.
5. The result remains an unsigned draft with zero new attendance/ledger rows. It explicitly returns new_actual_reporter_and_supervisor_signatures_required=true and the existing normal-v2 read context.
6. The user obtains new actual reporter and supervisor signatures through the existing normal APIs. Existing confirmation-bound receipt/ledger, sign_daily_report and its attendance/payroll/invoice triggers perform financial projection. This candidate never calls sign_daily_report with old or fabricated strokes.

The only materializer change occurs after the original normalizer/source/permit checks. For a new explicitly transitioned report whose current row exactly equals the already-staged facts and audited after-row, it returns before an identical UPDATE. Original clear-signature triggers are unchanged. A changed row, a different report, an unapproved materialization or disabled scope receives the original behavior/denial. No employee data changes during installation.

The transition never uses force_manage_attendance and never replaces real punches with manual clocks. An open/ambiguous source, NULL category, invalid choice, source/CAS change or authorization failure rolls the whole statement back, including its success audit and temporary permits. No finalize operation is exposed for a still-signed document.

## Current real-data implications

The reported signed document currently has a missing category, a saved registration inconsistency and zero confirmations. It must HOLD. The application must let the actual manager correct those values and obtain actual new signatures. This work does not assert that the other reported dates were never created; root owns their saved/partial/deletion history investigation.

Correcting only this one report would create that report's real financial source; it cannot by itself substantiate the other three clocked days. Those require their actual corresponding reports/facts/signatures or a separately authorized real management correction.

## Verification status

Completed locally: source pin capture using read-only catalog queries; Node syntax checks of both loaders and their generated focused proofs. No local Flutter/Dart, local PG execution, GitHub mutation, production DDL/DML, actual employee deletion or fake real signature.

Executed successfully: dedicated PostgreSQL17 workflow; additional explicit salary day-count assertions are in the current proof revision. The readiness proof tests OFF/invariance, real synthetic signatures, missing category/registration/confirmation/open-source holds, foreign/session privacy and an exact valid diagnosis that still cannot write. The transition proof includes actual observed clear triggers, default OFF, signed-document refusal, history-protected reset, explicit invalid-input/source/CAS holds, manager confirmation, epoch transition, fresh real re-signing, actual existing finalizer/attendance/ledger and retry invariance. The authentication/invoice producer surroundings inherited from the reviewed admin harness remain explicitly synthetic; invoice refresh body is actual, full invoice producer is neutral. Do not claim real production payroll/invoice totals were verified here.

Parent review and CI are required before any production rollout. Existing successful 91/96/255/331 broad suites are not replayed; loaders reuse only their installers.

