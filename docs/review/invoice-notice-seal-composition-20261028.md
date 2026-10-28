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
issuer seal-consent writers but **synthetic notice/session/readiness adapters**.
It checks OFF, wrong financial parent, wrong session, readiness failure, missing
explicit consent, rollback, one financial audit/consent/receipt, replay and ACL.
It does not prove real JWT, full month-close source locks or concurrent lock
ordering across both candidate systems. Separate native integration with the
actual month-close adapters is required before merging or enabling this path.
Payment-certificate confirmation, counterpart review/delivery, full UI/PDF stamp
consumption, deployment guards/restore and iPhone verification remain incomplete.
