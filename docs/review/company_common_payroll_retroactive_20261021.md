# Past-month common payroll: isolated reviewed plan candidate

Baseline main `2853e2d8d530f3fc65ce74ef307a1c63b21b0496`, latest Issue #273 read on 2026-10-21. Four new files only. No product route, database deployment, real employee condition/amount read, data repair, Auth/RLS permission change or invitation occurs.

## Current insurance connection

Individual payroll settings opens PayrollFixedDeductions with a selected month. Its openConditions callback opens PayrollTaxConditionsPage with that month. The page reads read_worker_payroll_tax_conditions, offers rates/fixed and server-advertised manual mode only, sends confirmed effective month and expected condition version to save_worker_payroll_tax_conditions, then validates returned scope/version/value. The original save_conditions loops all automatic draft statements from that month, calls refresh and sync and rejects blocked tax calculations. Closing conditions reloads the selected month in PayrollFixedDeductions. The statement/PDF uses saved named insurance totals; aggregate social insurance must not be divided into invented premiums.

No missing save/recalculation connection was established by this source trace. The historical exact-target investigation found no personal conditions; this is historical evidence, not a fresh person-data query. Current person/month/enrollment/base/monthly premium are unread. Do not populate example values or claim the real statement fixed. The existing manual candidate and guarded source must be reused. Its supported-mode capability is separate from the confirmed existence/matching of the six common-payroll bodies and activation/publication tables.

## Contract gap and staged change

The existing publish API explicitly rejects a past start month. Its current/future operation is unchanged. The new review-only internal plan/apply candidate admits a past canonical month only when existing company activation already covers it. It never silently moves activation backwards.

Plan enumerates existing statements from the chosen month, not inferred or newly created historical payroll. It returns eligible count, exact statement IDs/revisions/full-row digests and reasons: finalized_or_locked, manual_statement, missing_worker_settings, other_pay_type, later_publication_preserved, worker_edit_denied. No amounts or raw input rows are returned. Later effective publications retain their own settings. Recalculating those months using their own already-effective publication is a distinct future action; replacing their rates with this selection is also distinct.

Explicit apply compares the full plan after company/ordered-worker locks. It invokes a private, ungranted copy of the exact existing publisher, changing only its past-month refusal. The original function definition must match fully before installing the candidate. The old current-month API remains byte-for-byte unchanged. Recalculated count must match the reviewed eligible count; every excluded statement full row must remain exact, otherwise the transaction aborts. Individual payroll settings/conditions are inputs to the original calculation, not rewritten. Blocked calculations are counted separately from recalculated scopes. A matching actor/request/plan receipt replays without another calculation. A late receipt failure rolls back financial rows, publication and both receipts.

## Guard limits and rollout gates

This is an isolated design candidate with no client grants or UI route. Even authenticated admins cannot call its private schema directly. UI/repository/HTTP, lost-COMMIT durable reconciliation and native concurrency are not complete.

The source guard is intentionally overinclusive: company-scoped public tables plus all tables in enumerated payroll/common private schemas are hashed internally; payroll statement outputs and publication/receipt outputs are guarded separately. The actual refresh appends public.payroll_audit automatic_recalculation records (original tax migration line 767); these are outputs, not source inputs. Existing audit rows must remain as a multiset, and new rows must identify eligible statements, current actor and a newer revision. Removing or changing historical audit entries, or unrelated appends, aborts. It is not the old single-draft digest, and it includes common items/state/history and private insurance/unit/rate/resident inputs. However, **catalog-driven enumeration is not a proven production dependency closure**: public inputs without company_id other than companies, other schemas and external effects are not covered, unrelated rows in private global tables can cause false conflicts, and runtime cost is unbounded. Do not deploy this adapter. Before deployment replace it with a reviewed, bounded explicit dependency manifest and prove all source writers follow the lock protocol. No post-hoc hash proves transient concurrent changes cannot occur.

Native CI exercises PostgreSQL behavior, but this first fixture has no true two-connection races. Required next tests: source change while waiting on company/worker/month lock, finalize/manual transition, new eligible statement insertion, reciprocal actor/session revocation, source change during refresh, receipt ACK loss/recovery. Lack of these proofs is a deployment blocker, not a request to broaden grants.

Use the existing D readiness/backup/restore gates. A financial backup must cover every planned statement, revisions/details, source rows, publication timeline and receipts, final snapshots/reviews/adjustments/consumption. Function-only restore does not undo recalculated rows. No real historical publication, recalculation or data restore has run.

## New isolation fixture

verify_company_common_payroll_retroactive.mjs reuses the original effective fixture setup unchanged, loads real migrations and the actual existing common saver/bridge/effective candidates, then this SQL. It exercises read-plan no-write, confirmation, three historical drafts through real refresh, later-boundary preservation, exact replay, changed-plan/source CAS, real final snapshot, existing manual statement, retained individual earnings, late receipt rollback and ungranted schema. Dedicated PGlite/PostgreSQL CI is configured. Results must be recorded after execution; source preparation alone is not a pass.

Suggested future help text: 「過去月を含む適用では、反映前に対象と除外理由を確認します。確定済み・手入力給与と後続の適用設定は保持します。保留件数は再計算件数と別に表示します。」 No shared help/translation files changed.

Initial CI failed because the overinclusive source digest treated the real refresh's payroll_audit append as an input mutation. Diagnostic table hashes identified the table; the correction classifies this exact original-SQL output and separately guards old rows and permitted appends. One diagnostic-generation delimiter syntax failure was corrected without changing the financial/ACL contracts. Final CI status remains separate.
