# Future common allowance policy — minimum review candidate

This is a separate, ungranted private candidate. It does not change normal payroll/attendance callers, production tables, authentication, authorization or the Release application. It is **not** a completed continuation feature.

## Explicit company approval

`save_policy` requires company administrator authority, an approved selected-quantity publication and quantity contracts, expected policy version, request identity, effective start month and explicit future reconciliation rule. Without that approval, no future inheritance applies. It stores company item identities/generations and quantity rules, never a worker's old effective-settings blob. A disable decision is also versioned. The resolver chooses the latest effective start at or before the salary month, then the latest policy version at that boundary.

The policy's explicit rule permits inheritance for new workers when a legacy personal slot is absent, or when one exact name has the same rate. It **does not overwrite** personal source values. The calculated JSON only zeroes that matched slot to avoid adding the same selected payment twice. Different rates, duplicate individual names and overlapping custom/unit earnings remain unresolved rather than being silently overwritten. Such exceptions need an administrator decision.

`prefer_individual` records an explicit individual-priority exception tied to company, worker, payroll type, common identity/generation, policy version and the exact current individual slot/name. The source personal rate stays in use and the common item is omitted. Subsequent individual rate changes are preserved under this preference. If the preferred individual name changes, its old alias is **not** automatically interpreted as common: the resolver returns `preferred_individual_name_changed` with interpretation unconfirmed. Historical unknown selections are not automatically mapped to company identities or reported as completed zero payments.

## Fresh settings and actor boundary

`resolve_internal` uses a fresh current settings row and overlays only the necessary legacy slot. Unrelated base salary, resident tax and other personal setting changes are retained without an old whole-row checkpoint permanently blocking inheritance. Its input must match the fresh row; a transient stale caller input is a calculation-contract mismatch, not permission to reuse an old snapshot.

It intentionally does not call `admin_state`, `company_plan` or payroll `view/edit` authorization during calculation. An actor authorized to register attendance, including a legitimate proxy, may not have salary-view rights. The resolver remains revoked from all application roles and must be reached only from an approved canonical payroll caller that already validates company/worker operation scope. `read_display` separately checks salary-view authority and omits raw effective settings and earnings payload.

Unknown attendance names are an interpretation-unconfirmed state. This prototype conservatively marks the calculation unresolved; it is not the final classification/interpretation-receipt workflow. Manual/finalized statements return a frozen state and are not reinterpreted.

## Fixture evidence

Both synthetic and observed-private-rate fixtures use synthetic company/worker identities and attendance. The public fixture contains synthetic defaults; private input/logs stay outside git. Verified minimum cases:

- No policy means no future inheritance; exact request retry returns the same policy result.
- An explicitly approved policy applies to a later, not-yet-generated month and a worker created after approval.
- Fresh unrelated basic-rate/tax edits survive resolution.
- Same-name different rate is unresolved; explicit individual priority preserves the personal amount.
- Renaming an individually preferred slot is unconfirmed, not silently mapped to common.
- An internal caller input with an actor who lacks salary view still resolves; the salary display reader rejects that actor.
- Unknown historical name is unconfirmed; a future disable affects its month while the earlier month retains its policy.

The no-view test exercises only the **trusted internal input boundary** as the fixture owner. It does not grant, invent or prove actual proxy-attendance rights. No existing role policy was changed.

## Remaining work / production hold

Normal caller/checkout integration, a reviewed exact caller/dependency contract, actual proxy attendance plus real issued tokens, native PostgreSQL concurrency/RLS tests, atomic current activation plus durable policy approval UI, source/identity lifecycle review, bank-change end-to-end evidence, interpretation classification/receipts, saved final-document display, salary/PDF totals, and administrator iPhone verification remain unfinished. The minimum resolver tests do not demonstrate actual future payroll creation or actual checkout success. The normal product publisher must be the final integration owner; this private policy must not create a competing production payment route.


## Source classification correction

Attendance selections are now classified against the approved company policy, legacy personal slots, personal unit-condition items, personal custom earnings, and existing product common publication items. The display returns `selection_classification` with the actual source kinds/IDs/slots. A known personal or product-common selection is not automatically renamed or reassigned to a policy item and does not create an unconfirmed-history block merely because it is absent from the legacy three slots.

A same-name policy/personal legacy pair is accepted only under the already-approved same-rate inheritance rule or an exact explicit individual preference. Other multiple-source matches are `attendance_source_collision` and unresolved. Truly unknown historical names are `attendance_interpretation_unconfirmed`, never a silent successful zero. Tests separately cover known personal custom/unit selections, a known product-common selection, personal-source collision, policy/product-common collision, and an unknown historical name.
