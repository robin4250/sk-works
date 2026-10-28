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


## Approved expense cost reader integration (2026-10-28)

The composition installs `private.expense_cost_components` verbatim from the
existing original-cost migration, retaining its denied client EXECUTE rights.
Synthetic claims cover explicit cost allocation and current approval, withdrawal,
month/company/party/kind isolation, and consumption by the same versus another
document. Pending, unapproved, unallocated and already-captured foreign-document
claims do not add money. This does not create approval or allocation authority.

A nonempty 2000-yen expense result is recalculated by the real daily preview.
It is then combined with the real +1000/-250 adjustment reader and passed through
notice, financial approval and seal confirmation in one transaction. Revoking an
expense approval after ticket issue refuses confirmation without consuming the
ticket or publishing a seal. The existing late-failure rollback and exactly-once
successful confirmation checks run again for this combined scenario, and the
outer fixture restores all synthetic rows.

Expense approval/allocation/finalization mutation APIs, route providers, live
Auth/session and production mapping remain incomplete. These fixture rows are
not real expenses or business approvals. No product SQL, grant, source invoice,
production database or signature is changed. Native CI must pass separately.


## Signed route reader integration (2026-10-28)

The isolated extension now loads the existing signed-checkout source, rate,
component and invoice-component functions verbatim. Source/component/blocked
bodies retain their independent existing MD5 expectations. The scenario uses
two synthetic visits for one worker/day/customer and confirms one man-day,
20000 yen plus 2000 tax, rather than charging once per visit. Other-company and
other-customer reads return no amount. A missing visit exit or mismatched site
rate rejects readiness. Client EXECUTE remains revoked.

The combined daily-price, +1000/-250 adjustment, approved 2000 expense and route
proposal is passed through the existing durable notice and financial/seal
transaction. Removing a visit exit after ticket issuance refuses approval and
leaves ticket, approval, seal and receipt untouched. The existing late-failure
rollback and exactly-once success checks also run on this combined scenario.
All synthetic rows are rolled back. PGlite passes the complete extended suite;
Native PostgreSQL CI must pass separately.

This closes the empty route *reader* boundary for this synthetic scenario.
Actual route/expense/adjustment mutation APIs, live GoTrue/session composition,
notification delivery, public transport, deployment/recovery and iPhone checks
remain incomplete. Existing production invoices and test invoices are unchanged.
The earlier sections describe progressive scenarios, not a claim that every
source type or real production path is now verified.

## Private committed-result readback (2026-10-28)

The default-OFF notice composition now records an immutable result in the same
transaction as ticket consumption, the real financial approval and issuer seal.
It stores the exact actor/session, company/local document/revision, ticket and
request IDs and the canonical expected-preview hash. No token, password or seal
image is copied. The private reader requires the same live session, current
issuer authority and view/manage permissions and the original complete scope.
It reports a historical `recorded` result, not a new approval or an assertion
that the invoice remains current. An expired ticket does not erase the receipt;
a missing receipt remains unknown and is never an instruction to approve again.

The PGlite composition passes 357 checks, including actor/session/preview and
permission rejection, immutable rows and denied client access. All four actual
calculator scenarios check receipt insertion exactly once, outer rollback and
failure at the result-store insert after the existing financial/seal writers:
that failure rolls back ticket consumption, approval, seal, result and permit.
Canonical fixture hash verification and generated Node syntax also pass.

The new Native-only scenario observes a competing confirmation's company lock,
requires an uncommitted result to be absent, denies the duplicate consumed-ticket
command after COMMIT, and reads the same single result after reconnect. This
scenario is pending CI; it does not establish an unknown-COMMIT-ACK protocol.
Live Auth/full public transport, secure client reconciliation across logout,
deployment/restore/retention and device verification remain incomplete. No
public function/grant, automatic retry, production change or activation is added.

## OFF compatibility before any integration (2026-10-28)

The earlier UI candidate removed the normal approval action even though its new
notification controller was disabled. That was an OFF regression, not a desired
restriction on existing approvals. The PDF preview now restores the exact
`_approve` method from main `7355d28f` (SHA256 of the complete method:
`ee97cf5da13fbad5dba45d1826dd7c096c4cc35eed23bca1378b97f8a8682c3d`).
Its actor, assigned-approval, surname, explicit confirmation and saved-result
checks remain byte-identical. The original approval button stays in its row.

One fixed-false `invoiceNoticeApprovalReleased` constant selects the existing
action and prevents candidate controller creation, messaging or panel mounting.
The future ON branch receives no legacy callback and cannot fall back after a
missing controller, failed ticket read or uncertain submission. It remains OFF;
this is not authorization to enable the still-incomplete notification flow.

Eight added contract/Widget cases pin the canonical method and production wiring,
test the OFF normal/notification entries without candidate transport, preserve
permission/busy restrictions and require ON failures to avoid legacy fallback.
The local exact-source/gate checks and whitespace check pass; Flutter analysis
and Widget execution are pending the dedicated CI, not claimed as locally run.

## PostgreSQL COMMIT acknowledgement loss (2026-10-28, OFF)

A new Native-only loopback fixture puts a bounded PostgreSQL wire proxy between
the pg client and the disposable database. After the actual invoice/notice/seal
command returns a provisional transaction result, the proxy is armed. It drops
the backend's real `CommandComplete(COMMIT)` and following `ReadyForQuery`, then
closes the transport. The client must receive a failed COMMIT future: a known
successful ACK is not merely hidden later by the test. Synchronous commit is ON
for that disposable connection. A fresh same-scope connection must then recover
one immutable recorded result, one approval/seal/financial receipt and a consumed
ticket, without calling the approval command again.
The isolated synthetic wrong-SID and missing-SID contexts must still be refused
before the original valid context can read that result again.

The opposite case disconnects after the provisional command but before COMMIT.
It waits for that backend to disappear, then requires the original complete
financial/seal state and ticket to remain unchanged and the explicit result
read to remain missing. Missing still means unknown to the future client; the
fixture does not add automatic retry or infer success from a network exception.

The proxy accepts only explicit CI review mode, loopback and the exact disposable
database/user/password, binds an ephemeral loopback port and permits one client.
It rejects hosted credential environments, caps each direction/buffer/frame at
8 MiB and applies a 15-second absolute connection lifetime plus socket idle
limits, and a 5-second drop-observation deadline.
No URI, credential, raw protocol payload or SQL is logged. Six local Node tests
exercise unarmed forwarding, fragmented/coalesced ACK loss, false-positive text,
target/gate rejection and invalid/oversized frame lengths. Canonical fixture
generation and the unchanged 357-check PGlite suite pass locally; the new real
PostgreSQL failure scenario is pending CI and must not be called passed yet.

This is deterministic PostgreSQL transport fault injection, not a completed
HTTP/client recovery protocol, OS/network outage or database crash proof. Auth
and SID setup remain the existing explicit synthetic adapters; real GoTrue
logout/session invalidation and client reconciliation across logout are still
unproven for this new result reader. No application/controller/rollout changes,
public endpoint/grant, production write or deployment is introduced. The legacy
OFF approval method and fixed-false rollout selection remain unchanged.

Protocol reference: [PostgreSQL 17 message formats](https://www.postgresql.org/docs/17/protocol-message-formats.html)
and [protocol flow](https://www.postgresql.org/docs/17/protocol-flow.html).
