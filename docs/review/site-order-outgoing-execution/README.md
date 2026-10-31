# Outgoing original and sharing — source draft

Based on frozen UI PR1690/970fee. No production installation, feature activation,
real invitation or counterparty send. No new database table, object or grant;
existing eight helpers, C, Auth and SQL functions stay unchanged.

A fixed identity-bound original command derives the job from the exact existing
purpose receipt. The shared approved registrar retains its lock -> fresh stored
original lookup -> same bytes or fixed approved render -> registration path.
Outgoing-owned jobs require current source/registered stamp checks after the job
and manager/pair locks. Legacy raw registration cannot bypass that purpose.

Sharing derives its request ID from prepared_operations, then uses the existing
package advisory -> job UPDATE -> manager/pair order. A fresh lookup rejects an
old same-job package under another request. Legacy raw HTTP send rejects every
outgoing-owned job, including after waiting on the new sender. Unobserved or
ambiguous ownership never falls through to legacy permission. This is a fixed
HTTP/worker guarantee, not a claim that arbitrary trusted postgres SQL cannot
call an owner-only legacy function directly.

Original status is read-only under OFF or a new valid SID and never authorizes a
mutation. Unknown COMMIT outcomes are reconciled under the same identity. A
stored package means recipient-side storage, not recipient approval or confirmed
device push. The general site projection excludes financial values and PDF URLs.

The dedicated fixture uses an actual canonical Dart PDF and verifies exact
original-byte reuse, registration/sharing COMMIT ACK reconciliation, one package
and one notice set per operation, late-notification rollback, source/stamp drift,
OFF/new SID observations and legacy owned-route refusal. Native schedules observe
real lock waits for concurrent registration, registration before sharing and both
new/legacy sender orders. A historical same-job package under another request is
retained as unresolved and never adopted or duplicated. Boundary and existing
manager/renderer/reply units remain in the workflow.

Current-head CI and independent review must be checked separately. Execution
SDK/UI wiring, real GoTrue/hosted Edge, production application and iPhone checks
remain unfinished. This draft is not a completed delivery feature.
