# Saved reasons for deliberate payroll tax adjustments

This is an additive, review-only backend candidate for the approved per-item
manual-adjustment interface. No production DDL/DML, activation or payroll
recalculation has been performed. The existing saver, validator, calculator,
authorization functions and legacy API remain unchanged.

## Client contract, version 1

- `payroll_tax_adjustment_reason_contract_version()` returns `1` only with a
  valid live authenticated session.
- `save_worker_payroll_tax_conditions_with_reason` takes the existing six save
  arguments plus `p_reason`: trimmed nonempty text, at most 1,000 characters and
  4,000 UTF-8 bytes. Its result retains the existing response and adds
  `adjustment_receipt` with `starts_on`, `version`, `reason`, `actor_id` and
  `changed_at`.
- `read_worker_payroll_tax_adjustment_history(p_company_id,p_worker_id)` returns
  the echoed scope, `contract_version: 1`, the newest 100 `items` and `truncated`.
  Each item has the receipt fields plus `before_value` and `after_value`.
  Session IDs are stored privately and are not returned by this read API.

The new interface requires this capability and persisted receipt for manual
override creation, change, automatic reversion and deliberate individual monthly
amount adjustment. It must not silently fall back to the legacy writer or store
a reason only on the device. Unrelated profile/family updates keep the existing
path. Old clients and the existing general conditions page remain compatible;
this candidate does **not** impose a universal reason policy on those writers.

## Transaction and access

The new private saver reuses the existing account/session guard and payroll edit
authorization, then follows the same company-share/worker-update lock order.
It calls the existing exact versioned saver and obtains before/after values from
the exact resulting `condition_history` revision in the same transaction. The
existing omitted insurance-basis reference preservation is retained. A failed
reason insertion or receipt verification rolls back that entire transaction.

An identical retry requires the same actor, live SID, expected revision, saved
canonical JSON and reason. A legacy committed revision without a reason cannot
be backfilled as if this API originally wrote it. A same-version no-change call
does not create an audit revision. The private sidecar is RLS-enabled, has no
client DML grants and rejects updates/deletes. Child-support override restrictions
remain enforced by the unchanged validator.

The installer checks the captured dependency bodies, owners, ACLs, security mode
and search paths. It creates only new objects and rejects an existing module;
it neither edits old conditions/history/statements nor purges anything. Any later
deactivation must preserve accumulated audit records; no automatic destructive
rollback is provided.

## Verification boundaries

The verifier uses the exact captured deployed saver, read, validator, legacy
wrapper and live-session helper. Its authorization predicates, basis-reference
validation and payroll-refresh prerequisites are explicit synthetic fixtures,
not production implementations or live JWT/RLS proof. It verifies version/CAS,
canonical reference retention, retry isolation, reason/condition atomicity,
scope/role/SID denial, immutable history, automatic reversion, legacy compatibility
and bounded reads. PostgreSQL additionally competes a legacy writer against the
new writer under the same worker lock. Existing function metadata and a finalized
statement remain unchanged. No tax-rate or calculation correctness claim is made.

Issue #273 (body, 2026-10-19 06:46 JST) permits Work code/offline verification but
preserves production approval conditions. This review-only candidate is not a
production deployment authorization.
