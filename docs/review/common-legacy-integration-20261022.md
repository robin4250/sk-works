# Legacy common allowance integration prototype

Historical prototype: its all-workday quantity hypothesis is superseded by the explicit selected-date bounded candidate. Success of these earlier fixtures is not proof of the selected-allowance business contract. Production remains blocked.


Review only; no existing source function, production row, or UI was changed. Requires the earlier legacy plan candidate. All new tables/functions remain ungranted in `common_payroll_legacy_review_private`.

## Implemented

`apply_plan` accepts a bounded explicit list of current-month worker decisions, expected publication version, observed company plan and worker hashes. It locks company and workers, rechecks editable automatic drafts and identity bindings, and saves immutable-by-interface publication plus bindings, activation and request receipt in the same transaction. An unresolved worker rolls back the call. A matching request returns its receipt, while changed request content rejects. The function does not invoke payroll recalculation or activate the product publisher.

`resolve` reads the active private publication and saved bindings. It provides daily quantities from distinct positive-work dates, original identity/generation, rates, amounts, `readonly` and `inherited`. Individual source changes and manual/finalized statements block instead of overwriting the user's newer settings. Unincluded workers fail closed if this candidate activation is encountered. Only the legacy daily earning snapshot is supported in this first integration; existing new-item snapshots are rejected before saving.

`augment_candidate` preserves the underlying individual row, uses the approved effective overlay, and appends common earnings once. Existing product common activation is rejected to prevent simultaneous old/new publication paths. No automatic copying into individual slots occurs.

## Individual salary screen integration contract

Place a read-only “会社共通から継承” group inside the **支給 → 日** view, separately from editable individual 手当1〜3. Show each item name, company daily rate, applicable payroll type/month, current counted days and calculated amount. Keep the individual source amount intact; show an inherited-slot note on an explicitly bound individual slot so the user understands why the amount is not added twice.

- `active=false`: “会社共通手当はこの月の給与へ未適用”. Do not display an empty group as applied.
- `blocked=true`: show the reason and a “設定を確認” action; never display stale or zero values as successfully inherited.
- `active=true, blocked=false`: render the items as read-only inherited entries. The same returned items feed the payroll detail calculation.
- An individual differing rate or ambiguous identity is resolved in the company application preview, not by editing the inherited display or copying names.
- “？” help explains company registration versus payroll application, effective month, individual exceptions and finalized exclusions. Detailed explanation starts collapsed.

This is a UI contract, not a shipped widget or a Flutter-tested screen. A narrow authorized read endpoint returning only display fields is still required; the private `effective_settings` payload must not be returned wholesale to the UI.

## Isolation evidence and limits

The companion fixture wires only disposable copies of the actual refresh/sync callers to `augment_candidate`. It verifies binding persistence, atomic activation, same-request retry, rollback on stale source, inherited display payload, actual attendance insert/edit recomputation, no legacy selection double addition, original settings preservation, and block after individual source change.

Synthetic and current private-rate inputs are tested separately. Private input/logs remain outside the repository. These runs use synthetic attendance and IDs; they do not prove the current production statement or PDF. Dedicated CI proposes PGlite and PostgreSQL 17; native results remain pending until root runs it.

Before production: review complete source dependency and finalization lock closure; implement all-scope preview/exclusions, bounded recalculation and post-readback, authorized endpoint/UI with durable pending request reconciliation, native races/rollback/RLS/real-JWT tests, then real screen/PDF/iPhone verification. This prototype's receipt retry is not a complete lost-COMMIT client workflow. An all-company application must never silently omit unincluded draft workers.
