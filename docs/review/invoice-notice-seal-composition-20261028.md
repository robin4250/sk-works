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
