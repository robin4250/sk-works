# Bounded selected-allowance integration candidate

Review only. This supersedes the **quantity assumption** of the earlier all-working-date prototype, without changing that archived prototype or any shared product function. It is not authorized for production deployment.

## Quantity contract correction

The original payroll legacy loop counts `attendance_entries.allowance_names` once per work date/name. It does not require positive base man-days. `allowance_N_unit` is a configurable display label (default 回); it does not prove an automatic-all-days quantity rule. Therefore “reflect settings in every unfinished salary” must not imply paying every allowance for every work day.

The new plan explicitly binds each company identity/generation/source-unit to `attendance_selected_distinct_dates` plus its current exact name as an alias. Missing or invalid quantity basis blocks the preview/apply. Historical aliases, arbitrary numeric quantities such as a separate 1/2 selector, and automatic all-working-date selection are unsupported and must not be inferred. The product owner must confirm the actual daily report quantity contract before deployment.

`worker_plan_selected` retains all earlier permission, individual conflict, identity and original-row protections, while removing the earlier nonworking-date rejection because selected legacy payments on those dates are part of the preserved contract. `resolve_selected` reads the saved explicit quantity contract, counts selected distinct dates including zero-man-day selections, and returns the original display unit. Unselected working dates contribute zero common allowance.

## Full target preview and bounded application

`preview_scopes` covers active workers of the chosen payroll type at the selected nonpast start month, plus every existing statement in the explicit start/end range (maximum 12 months, 100 scopes). It reports targets, exclusions, unresolved reasons, worker hashes, statement hashes, attendance hashes, publication versions and binding suggestions. Different/missing payroll types and manual/finalized statements are excluded. An unresolved individual/quantity contract blocks batch application; no target may be silently omitted from explicit decisions.

`apply_bounded` locks company and ordered workers/statements, rereads the preview after locks, saves per-month publication/bindings/quantity contract/activation, then performs bounded recalculation with result readback in the same transaction. It checks unblocked calculation and the existing zero-floor net formula (`max(gross − deductions, 0)`), returns per-scope statuses/revisions, and verifies excluded rows stayed unchanged. Request receipts support exact request reconciliation. Calls fail unless the actual refresh, money trigger and tax calculator reference the selected candidate augmenter; merely installing review SQL cannot recalculate salaries with the old product augmenter.

This is not yet a complete production dependency closure: paid leave, tax, insurance and other source relations and their mutation lock order require native concurrency review. Known preview/worker/statement/attendance source changes are fail-closed. No previous-month repair is added.

## Read endpoint and individual UI candidate

`public.read_company_common_legacy_inheritance_review` returns only active/blocked/reason/month/version and inherited items after the existing per-worker read authorization check. It is explicitly revoked from all application roles until review. Raw settings, decisions and private company plan are omitted.

The companion `.dart.review-only` panel is a **non-shipped, not Flutter-tested** connection candidate for 支給→日. It consumes only this narrow display payload; inherited values never populate the individual editable controllers or their save. It displays 未適用/要確認/継承 states and selected-day quantity, company rate and amount. Help starts collapsed. The integration owner still needs repository loading, stale/loading/error states, localization and a bound-slot indicator, plus actual Flutter/PDF verification.

## Tests

The bounded fixture uses synthetic IDs and attendance. It checks missing quantity basis, selected/unselected dates, current plus existing future draft coverage, caller guard, exact retry, stale preview rejection, manual preservation, readback and narrow read-only endpoint. A separate private-rate run reads the current private snapshot without committing it. Native PostgreSQL execution is pending root CI for this new fixture; earlier publication/integration PR checks do not certify the new code.


## Excluded-original regression protection

Every excluded statement hash is captured after scope locks and before any publication, activation or target refresh, and must equal the original preview hash. After **all** target recalculations complete, each excluded final hash must still equal both its captured original and preview hash. Missing rows use the same `md5('absent')` sentinel on both sides; missing and SQL NULL are not confused with a populated statement. This also catches a later target's trigger modifying an earlier exclusion.

The negative-control fixture installs a disposable target-update trigger that changes an excluded manual statement. Application must reject and roll back all statements, payroll audit, publications, bindings, activations, quantity contracts and receipts to their exact prior state. Removing that trigger restores the ordinary successful path.


## Caller and interpretation boundaries

The calculation guard now requires three exact function signatures and their reviewed source MD5s, rather than looking for a matching call string. These hashes refer only to the known source bodies with the selected candidate call wired into the disposable fixture. A harmless comment change still rejects until explicitly reviewed. This is a source compatibility check, not a complete permission/configuration/dependency attestation.

The current preview **does not yet classify every attendance selection** into current company identity, regular individual allowance and interpretation-unconfirmed historical alias. An unknown historical name must not be reported as a completed zero-payment interpretation. A production path needs that classification plus an explicit reviewed interpretation/exclusion receipt. The present selected-current-name bounded test therefore remains on production hold even if CI passes.

The candidate covers the chosen start month and already-existing drafts within the explicit range. It does **not** establish continuing inheritance for later-generated months or newly added workers. The user request for every applicable unfinished salary from the start month remains unfinished. The next product design should persist an approved company inheritance policy, reuse the normal publisher for future scopes, preserve explicit individual overrides, and avoid indefinitely blocking unrelated individual changes. Current whole-settings-hash invalidation is a conservative review boundary, not the intended permanent user experience.
