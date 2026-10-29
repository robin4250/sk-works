# Invoice notice client recovery candidate (OFF)

Base: main 16fe3e1f. This increment composes the existing ticket controller with
one immutable, memory-only confirmation operation and an explicit result reader.
It does not connect the production factory, panel or candidate RPC endpoints.
The release flag remains false and the legacy approval implementation is unchanged.

The operation snapshots ticket, local document, company, revision, request ID and
expected preview before dispatch. Confirmation is sent at most once per instance;
even a successful command response remains provisional until immutable historical
readback returns recorded financial approval and seal consent. Missing, malformed,
failed and timed-out readback never permits reopening or resending. Readback may be
retried only for the same captured operation, actor and SID. The server reader must
still independently enforce its existing exact scope and live-session checks.

`invalidate()` is terminal and must be called synchronously at logout, account
change, background and disposal. It clears memory-only operation scope, invalidates
tickets and cancels delayed submit/read results by generation. A different SID
invalidates the instance, even if the old SID later returns. Cross-login recovery
is deliberately unavailable. A newly created instance does not possess an old
operation; no operation persistence or restoration is added here.

Eight Flutter tests cover provisional success, ambiguous/missing/error readback,
immutable scope, SID change, delayed logout replies, concurrent read suppression,
malformed receipts and actual Supabase SDK HTTP error/readback composition using
synthetic loopback URLs and fixture-only RPC names. This SDK test proves client
request identity and no resend; it does not claim a real PostgreSQL/PostgREST/Auth
integration. The separately merged native wire proof remains evidence of the
private SQL transaction/receipt behavior, not an end-to-end client proof.

Still required before activation: authenticated public transport with the private
SQL result contract, real live Auth/logout event wiring, UI readback composition,
server-enforced scope through that transport, safe persistence/restart design if
needed, production gates and device verification. No SQL, grants, hosted database,
originals, signatures, deployment or delivery are changed.
