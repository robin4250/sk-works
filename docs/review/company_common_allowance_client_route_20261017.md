# Existing additive allowance client: isolated route composition

Base: PR1233 exact `1932bdccc17b2663ba0e97307109708a516633ba` (main `de0470d616b480d98ee84ec47fb67ee4b5ea036e` remains separate). User requested reflecting the existing additional-registration work on 2026-10-17. No SQL, production, Auth implementation, RLS, permission, dependency, individual payroll calculation or quantity change is included.

The seven allowance-only paths from PR1151 exact `145dee55a54d3c089c4fbf93f9a7f5b58254ff65` were first copied byte-for-byte in commit `dc174ce3cfec453fe47275d4ed183f8aef8c15cc`. The three core client files are also identical in PR1156 `34924663634fb90e5879d3d63070564bc42b4c4f`. Unrelated onboarding/security ancestors and PR1156's whole 30-file integration were not imported.

Prior final-head CI: PR1151 all five workflows succeeded (additive `38933958497`, Flutter `38933958438`, iOS `38933958643`); PR1156's final main-base set succeeded (additive `38935772743`, settings integration `38935772793`, Flutter `38935772728`, iOS `38935772759`, plus its other dedicated checks). These are previous composition results, not evidence this new route combination passes or production RPCs exist.

Only `company_common_allowances` now points through a company selector to the existing connected page. The selector is narrowed from PR1156's membership/actor/lifecycle logic to allowance-only scope. Multiple memberships require explicit selection; stale actor responses do not open a private child. The existing `SecondaryProtectedPage` wrapper is retained. `company_tax_rates`, the old tax/welfare/three-slot/four-rate settings routes and their implementations remain unchanged. PR1156's warning against replacing working settings before its new RPCs exist still applies; this change avoids that replacement.

The preserved repository calls exactly:

| Operation | RPC | Required evidence |
| --- | --- | --- |
| Initial/read and resume | `read_company_common_allowances_admin(p_company_id)` | Exact company/contract/version and server `can_edit`; no editor before successful parsing |
| Explicit registration | `save_company_common_allowances` | Existing expected company/source versions, stable IDs, actor, request UUID, original legacy slots and explicit first adoption |
| Unknown-result reconciliation | `read_company_common_allowance_request` | Exact actor/company/request/operation/payload and committed-version receipt; no automatic save retry |

Missing read RPC (`PGRST202`), permission denial (`42501`), transport failure or malformed response must not enable registration, write a command or invoke an old full-save fallback. The existing connected page hides the editor on initial read failure and reports that input/save has not started. This is a fail-closed read gate, not a separate complete schema inventory or a promise that all write RPCs exist. If a later explicit save has an unknown result, the original pending-command/receipt-only recovery remains in force.

PR1152/1155 server candidates were recorded as unapplied in the existing handoff. No fresh production query or application was performed here. Therefore production additional registration remains blocked wherever the required endpoints are absent; the client route is not proof of a successful production save, individual-setting reflection, payroll calculation or payslip integration. Existing tax/settings edits remain available through their unchanged routes. Formal backup/restore/impact/approval gates are retained.

Validation prepared: existing connected-widget/SQL-response/parser cases plus six new route/scope/fail-closed cases covering explicit multi-company choice, stale membership response and initial missing/denied/network reads without writes. Local Flutter/Dart SDK is absent, so runtime/analyzer results must come from this exact candidate's CI. Offline diff/scope checks only are recorded locally. Footer changes belong to a subsequent separately owned commit on top of the preserved allowance-page source.
