# Future common allowance connection — minimum review diff

**Review only; no production deployment, UI exposure or application authorization change.** This candidate depends on the earlier future-policy prototype. It replaces one shared SQL function inside a disposable database. No product migration, normal caller source file, role policy, help or workflow was edited.

## Existing call paths and smallest connection point

| Path | Existing route into salary calculation |
| --- | --- |
| Attendance insert/update/delete | `private.attendance_refresh_payroll()` → `private.refresh_automatic_payroll()` → `private.refresh_automatic_payroll_internal()` → shared augmenter |
| Attendance detail synchronization | `private.attendance_sync_payroll_detail()` → existing detail synchronization → salary money trigger → shared augmenter |
| Individual salary setting change | `private.settings_refresh_payroll()` → refresh/detail synchronization → shared augmenter |
| Current-month fixed monthly generation | `private.ensure_monthly_payroll_drafts(date)` → internal refresh/detail synchronization → shared augmenter |
| Tax calculation | `payroll_tax_private.calculate(uuid,uuid,date,date,bigint,bigint)` → shared augmenter |

The relevant existing sources are `20261013175452_payroll_unit_conditions.sql`, `20261008040428_generate_fixed_monthly_payroll_without_attendance.sql`, `20261009171504_payroll_refresh_scope_order.sql`, `payroll_refresh_scope_live_source_fixture.sql`, and the effective common-payroll candidate. These paths already share `payroll_unit_private.augment_settings(uuid,uuid,date,date,jsonb)`.

The new connection SQL requires that exact signature, the reviewed existing body MD5 `47ee121481cea77af1e0275c686c65db`, JSON return type, and existing security-definer mode. It then replaces **only** the augmenter body. The old individual-unit/common-publication resolver path remains in use. An explicitly approved effective future policy adds its selected-date items and its narrowly overlaid fresh settings. No policy retains the old path. A duplicate common identity/name from the existing publication path marks calculation unresolved rather than adding twice.

This is tied to the reviewed effective-publication baseline. A different live augmenter source must fail the prerequisite check, not be overwritten by assumption. The guard is not a complete transitive dependency/owner/configuration/permission attestation; deployment review still needs that closure.

## Permission and data boundaries

The normal salary/attendance caller definitions remain byte-for-byte unchanged. The augmenter keeps its owner, execute grants and security-definer mode. No new salary-view requirement is added inside calculation; the future internal resolver remains revoked from application roles and the display reader retains its separate salary-view check. The normal caller's company/worker scope validation remains the authorization boundary. This proposal does not grant a proxy new attendance or salary rights.

Individual source values are never overwritten by inheritance; selected-date quantities remain unchanged. Existing manual/finalized guards remain in their canonical callers. Unknown aliases and individual conflicts become unresolved calculation state. This candidate does not implement the final interpretation-receipt UI.

## Isolated evidence

The connection fixture installs the one-function candidate rather than rewriting refresh/tax/attendance caller definitions. It checks their exact source hashes before/after, and the shared augmenter's owner/execute ACL/security mode before/after.

Synthetic and observed-private-rate inputs use synthetic IDs/attendance; private input and logs stay outside git. Verified paths include:

- Attendance insertion creates an actual salary row with the selected inherited allowance once and unselected common allowance zero.
- Editing the attendance selection removes/restores exactly the selected company amount.
- A worker added after policy approval gets an actual salary row through the same attendance trigger without a preexisting worker effective-settings snapshot.
- Fresh basic salary/tax changes are retained; individual exceptions and renamed preferred names keep their earlier behavior.
- The existing security-definer attendance triggers run under claims without salary view, with no extra salary-view check in the candidate.
- An existing manual salary is unchanged by later refresh.

The no-view insert runs as the fixture owner with actor claims. It proves the internal trigger/calculation contract, **not** that the actor is an authorized real proxy at the public attendance endpoint. Application row authorization, real issued tokens and actual iPhone checkout remain untested. The monthly scheduler path is source-traced here; the fixture does not advance the real calendar or prove a later month's scheduled execution.

## Remaining production blockers

Native PostgreSQL checks for this new candidate, canonical public attendance/JWT/RLS/proxy tests, concurrent policy/settings/finalization and complete dependency closure, approved policy/interpretation UI, public display rollout, automatic new-month scheduled evidence, PDF/print/share and administrator iPhone verification remain unfinished. Original one-off selected binding candidates and the future policy must be unified under the normal product publisher before rollout; this must not become an independent competing production payment route.


## Exact security prerequisite correction

The installer now pins both the shared augmenter and future internal resolver to the expected signatures, reviewed source hashes, `postgres` owner, owner-only execute ACL, JSON scalar return, PL/pgSQL function kind, stable volatility, expected security-definer/invoker mode, empty search path, parallel-unsafe mode, and non-strict/non-leakproof/non-variadic attributes. It also pins the owners and normalized ACLs of both private schemas: the existing payroll-unit schema retains only its reviewed authenticated USAGE entry, and the future schema stays owner-only.

The connection fixture mutates owner, execute ACL, search path, volatility and security mode on each function, plus private-schema usage/ownership, inside disposable transactions. It also replaces the internal resolver with the **same source body/signature but a different return type**. Every mutation rejects before installation; rollback restores the baseline. Positive installation still preserves caller definitions and existing grants. These are expected-baseline checks, not merely a before/after-equality claim. Native verification for the updated negative controls is pending root CI.
