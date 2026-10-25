# V2 manager-attested manual attendance source

Review-only owner module. No production access, activation, fake GPS records,
old report conversion, direct salary repair or existing writer replacement.

## Evidence and authority are separate

`checkout_shared_managed_private.managed_source_scope(report,worker)` is a pure
owner-only evidence reader. It requires exactly one formal attendance entry for
the report's company/worker/day/destination, with a full one-day quantity. A NULL
`source_report_id` is eligible; a different report is never overwritten. No
employee authentication UID or clock record is invented. Its SHA256 basis binds
the exact manual row, revision, all same-day attendance and all actual clock
evidence, including an empty real clock set.

The v2 public confirmation API must separately authorize a current company
manager, require an explicit reason, normalize all worker facts, then call
`validate_managed_facts(report,worker,canonical_facts)` BEFORE confirmation. The
original entry's day/overtime/early/night/category/manual amount/labels must
already match what the original sign writer would save. A fractional day,
different currency or incompatible labels remain pending; this is not an
authorization to rewrite them.

Immediately after inserting that managed v2 confirmation, call
`record_manager_confirmation(report,worker,confirmation_id,source_fp,facts)`.
It revalidates manager role, live actor, exact source, confirmation kind, reason,
facts and fingerprint and writes an immutable manager receipt. A proposal is
not a receipt. `propose_worker_facts` uses actual AE facts plus existing
normalized company choices/vehicle facts; it returns NULL on incompatibility,
never falls back to zero or fabricated attendance.

## One atomic final-sign transaction

Installation requires v2 core, worker-facts normalizer and the exact observed
canonical lock/private signature sources. The existing public sign body is
recorded in the test source fixture, not replaced by this module.

1. V2 obtains ALL sorted report worker/month locks, then report locks.
2. V2 creates its private supervisor context and per-worker materialization
   permit for the same transaction, authenticated actor and exact facts/hash.
3. While the permit exists, call
   `prepare_managed_adoption(report,worker,source_fp,facts)` for managed sources.
   It requires the latest confirmation's immutable manager receipt and locks the
   actual entry and every existing scope payroll row. Only a NULL source pointer
   is bound to the report. The original ID, factual numeric fields, creation
   metadata and all amounts are preserved. Before-entry and payroll component
   vectors are saved immutably. Manual/finalized/approval-protected salary or a
   missing existing payroll snapshot are rejected.
4. Run the existing confirmed-worker materializer and original sign writer.
5. Immediately after the original sign writer returns, call
   `assert_managed_adoption_unchanged(report)`. It verifies the same private
   supervisor context, original AE identity/facts/cash and full saved scope
   payroll currency-component vector. Any difference raises PT409 and rolls
back the entire pointer/signature/payroll transaction. No substitution or
repair is attempted. A deferred private-audit constraint also forbids commit
without that explicit verified event, a fully signed v3 report, the exact
accepted row hash and the same final payroll vector. Omitting the hook or
changing money later in the transaction cannot leave a partially adopted entry.

Only exact audited pointer/server-stamp changes may alias the original source
fingerprint. The current complete AE row hash must match an accepted `bound`,
`materialized` or `verified` event. A BEFORE UPDATE trigger appends the exact NEW
row hash only in the same private adoption transaction and supervisor context,
after validating all identity/facts/numeric fields and any new company receipt.
Thus the original writer's server-stamp update is visible to normal AFTER payroll
refresh without a broad metadata wildcard. Final post-sign currency validation
still must succeed or the entire transaction, including those events, rolls back.
Any other AE update or any changed same-day clock/source
set yields a different source; old confirmations cannot remain current. Later
salary finalization does not erase a verified immutable source history.

All receipt/adoption/event rows are append-only, unexposed and without caller
grants. The adapter's AE triggers are inert for untouched v1 scopes. For a v2
managed confirmation scope, both OLD and NEW canonical worker/day scopes are
locked and passed to the v2 owner `invalidate_worker_day(cid,wid,day)` helper.
That helper must refresh only eligible v2 automatic drafts and preserve
protected payroll history. Existing authorized parent cleanup is not replaced.

## Verification boundary

The dedicated PG17 fixture installs exact observed public sign, private
signature and canonical lock definitions and checks their body hashes. It tests
manual attendance without employee UID/GPS, manager receipt, private permit,
same-ID original sign, source alias, financial drift rollback, protected salary,
other-report/fractional rejection, immutable audits, OLD/NEW invalidation and
caller ACLs. Auth and the payroll-refresh callback around those original writers
are synthetic and explicitly identified. It does NOT prove the full deployed
refresh chain, current catalog triggers or real GoTrue. Those must be composed
with the existing v2 actual-payroll proof before deployment. No local Flutter or
PostgreSQL execution has been performed here.
