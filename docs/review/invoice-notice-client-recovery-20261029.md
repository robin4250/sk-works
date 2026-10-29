# Invoice notice client recovery candidate (OFF)

Base: main 16fe3e1f. This increment composes the existing ticket controller with
one immutable, memory-only confirmation operation and an explicit result reader.
It does not connect the production factory, panel or candidate RPC endpoints.
The release flag remains false and the legacy approval implementation is unchanged.

The operation snapshots ticket, local document, company, revision, request ID and
expected preview and server-issued canonical expected-preview hash before dispatch. Confirmation is sent at most once per instance;
even a successful command response remains provisional until immutable historical
readback returns recorded financial approval and seal consent, and a stored scope
envelope exactly matches ticket/local/company/revision/request/hash/actor/SID.
Legacy unbound envelopes and foreign/stale scopes are rejected. The new private, ungranted `read_invoice_notice_result_scoped` adapter first calls
the unchanged reader for all enabled/company/feature/live-session/hash checks,
then derives the envelope exclusively from immutable persisted receipt columns.
It never attaches caller-supplied scope to an unbound response. Missing, malformed,
failed and timed-out readback never permits reopening or resending. Readback may be
retried only for the same captured operation, actor and SID. The server reader must
still independently enforce its existing exact scope and live-session checks.

`invalidate()` is terminal and must be called synchronously at logout, account
change, background and disposal. It clears memory-only operation scope, invalidates
tickets and cancels delayed submit/read results by generation. A different SID
invalidates the instance, even if the old SID later returns. Cross-login recovery
is deliberately unavailable. No automatic global Auth event/history subscription
is installed by this class; application wiring must call invalidate at the boundary. A newly created instance does not possess an old
operation; no operation persistence or restoration is added here.

Ten isolated Flutter tests cover provisional success, ambiguous/missing/error readback,
immutable scope, SID change, delayed logout replies, concurrent read suppression,
malformed receipts and actual Supabase SDK HTTP error/readback composition using
synthetic loopback URLs and fixture-only RPC names. This SDK test proves client
request identity and no resend; it does not claim a real PostgreSQL/PostgREST/Auth
integration. The native lost-COMMIT fixture additionally reads the scoped receipt over a fresh
PostgreSQL connection and exports that actual synthetic committed receipt to a
CI temporary file. In the same dedicated job, one additional Flutter test feeds
this SQL-generated envelope through the real SDK response decoder into the Dart
lifecycle, accepting only exact scope and rejecting every foreign field. This
is an actual saved SQL receipt-to-client contract bridge; it remains distinct
from authenticated public HTTP/Auth end-to-end proof. The bridge fixture is
skipped outside its dedicated job; that job requires the generated file.

Still required before activation: authenticated public transport with the private
SQL result contract, real live Auth/logout event wiring, UI readback composition,
server-enforced scope through that transport, safe persistence/restart design if
needed, production gates and device verification. Only review-only private candidate SQL is extended. No public endpoint/grants,
hosted database, originals, signatures, deployment or delivery are changed.
