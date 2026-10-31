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

Initial local PGlite extension passed 229 checks using an actual canonical Dart
PDF, exact original-byte reuse, original/share COMMIT ACK losses, one package and
one notice set, late-notification rollback, OFF/new SID observation, stamp-change
refusal preserving original bytes, and legacy owned-route refusals. The
manager/renderer/reply regressions and new boundary units passed. Native four-schedule race tests are now implemented but not yet verified;
complete current-head CI, SDK/UI execution-stage wiring and independent review
are unfinished. This draft must not be described as a completed delivery feature.
