# Invoice notice and explicit issuer seal composition — review only

The private default-OFF wrapper consumes the existing notification ticket,
requires its invoice to match the acceptance document's saved financial parent,
rechecks the existing month-close source gate, and invokes the existing combined
financial approval plus explicit issuer-seal command in the same transaction.
Any parent mismatch, readiness failure, stale document or later mutation error
rolls back ticket consumption and the transaction-scoped approval permit too.
Consumed-ticket retries are rejected, not sent to a legacy approval fallback;
lost-response reconciliation still requires reading the durable approval result.

This reuses `trade_document_invoice_confirmation_20261021.sql.review-only`;
it does not infer another company's seal permission from internal approval.
The original exact customer FK, formal connection, assigned final approver,
parent/attachment/body/seal versions and explicit two confirmations still apply.
No public endpoint, grant, production trigger, notification send or activation
is introduced. Current broad month-close locks are not removed.

The isolated composition test uses real existing invoice approval, freeze and
issuer seal-consent writers and loads the existing durable notice prepare,
current-revision check, ticket issuance and consumption SQL verbatim. It also
loads the existing `precheck`, `guarded` and `notification_readiness` SQL verbatim, using
a retained synthetic source proposal. Mutations during both notice revalidation
and the final guarded revalidation must reject and roll back ticket/financial/seal
writes. Its closed synthetic month has linked clock-in/checkout, signed report,
worker and attendance rows; removing the supervisor signature is rejected by
the actual precheck. Session, source preview/fingerprint and core-integrity adapters
remain **synthetic**; this does not verify the actual source calculation or locks.
It checks OFF, wrong financial parent, wrong session, readiness failure, missing
explicit consent, rollback, changed invoice revision, one financial
audit/consent/receipt, replay and ACL. A foreign-session ticket and wrong-parent
ticket remain unconsumed after rejection. This is not notification delivery:
the test invokes private notice preparation/issuance directly.
It does not prove real JWT, full month-close source locks or concurrent lock
ordering across both candidate systems. Separate native integration with the
actual month-close adapters is required before merging or enabling this path.
Payment-certificate confirmation, counterpart review/delivery, full UI/PDF stamp
consumption, deployment guards/restore and iPhone verification remain incomplete.

## Pinned source integrity and revalidation extension

After the successful notice/financial/seal composition, a separate extension
loads the verbatim source fingerprint function from pinned commit
`4f04488f77ff909d0d48a9a74247eb549823ca83` and the existing exact
`generate_approver_core.py` output. Missing source relations are explicit empty
fixtures; existing attendance and financial rows are retained. It verifies
company-source hash stability, other-company isolation, actual approver/notice
revalidation and rejection after an attendance-source mutation. The real
MD5 catalog guards must reject replacement preview bodies before granting ready
or notification readiness. UTC is explicitly selected for independent invoice
row hashing, matching the generated SQL's timezone contract.

The successful financial/seal approval still uses a synthetic source proposal.
This extension runs the actual fingerprint, source-locking revalidators and
catalog guards, **not the full source calculator's successful preview**. It is
not full source-calculation/GoTrue integration and is not production evidence.
The broad existing table locks remain unchanged.

## Actual daily-price preview extension

The extension now executes the pinned generated preview body against a closed
synthetic month containing one linked attendance/report day. It reuses the
existing rate-formula functions and the existing adjustment-aware refresh body
with its expected independent MD5. Fixture-only missing columns are added;
product SQL is not changed. The real daily-price preview computes 100,000 yen
plus 10,000 yen tax, and its exact saved result passes the real approval and
notification readiness functions. A duplicated source day recalculates to
220,000 yen and the real guard returns `data_changed`; rollback restores ready.

Route components, expense components and named adjustments are explicitly empty
fixture providers in this extension. The earlier financial/seal composition
runs before this extension with its synthetic proposal; a later scenario below
now confirms the actual calculated daily-price invoice. This is a minimal
actual daily-calculator-to-readiness bridge, not full route/expense/adjustment
calculation or a single end-to-end real-Auth financial/seal approval proof.


## Calculated invoice through financial and seal confirmation

The actual daily-price proposal now also passes through the existing durable
notice prepare/issue/consume SQL and the combined financial approval plus issuer
seal-consent command in one database transaction. Because recalculation changes
the financial parent, the test uses the existing attachment save API and creates
a new immutable consent revision; it does not rewrite an old binding.

The fixture checks current-source rejection, late financial-receipt failure and
complete rollback of ticket consumption, approval, consent, receipt and permit;
then a fresh successful confirmation produces exactly one audit/consent/receipt.
The enclosing test transaction is rolled back, restoring the original unapproved
invoice and document revision. PGlite passes 162 checks including this extension.
Native PostgreSQL runs through the same existing composition CI.

Auth/session remains synthetic, and route/expense/adjustment providers remain
explicitly empty. This is not all-source/real-GoTrue production approval, public
rollout or iPhone evidence. No production records or existing test invoices are
modified. The previous paragraph's statement that successful financial approval
only uses a synthetic proposal describes the earlier scenario; this new separate
scenario closes that gap for the daily-price branch only.

## Named-adjustment reader integration (2026-10-28)

The isolated composition now installs the existing `ledger_items` and `active_items`
readers verbatim from the reviewed adjustment source (including their revoked
client EXECUTE permissions). It tests monthly and once-only settlement entries,
plus/minus amounts, effective stop versions, occurrence overrides/cancellation,
company/party isolation and OFF behavior. A nonempty +1000/-250 settlement case
is recalculated by the actual daily calculator and passed through the real
notice, financial approval and issuer-seal transaction, then the complete
synthetic scenario is rolled back. The saved invoice total is 110750 rather than
110000. PGlite has 201 successful checks; Native CI is required separately.

This replaces one empty provider boundary, not the adjustment mutation APIs.
Auth/session, route and expense remain fixtures, production mapping and the
full-source/GoTrue composition are incomplete. No production SQL, grant, approval
or existing invoice was changed.
