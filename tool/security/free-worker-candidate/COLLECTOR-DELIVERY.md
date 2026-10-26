# Collector delivery companion — OFF and unscheduled

This adds the missing bounded transport between the existing durable observation
outbox and PR1438's reviewed collector-v2 ingress. It does not install a collector,
connect a host/account, provision a key, send a real observation or notify anyone.
`src/worker.mjs` does not import it; no public control/send route or alarm is added.
Existing policy, capability, management, Wasm and collector SQL are unchanged.

## Exact connection and trust

`createCollectorSender` is a trusted internal companion, disabled by default. An
operator must supply a dedicated collector ID/version and 32-byte HMAC key. The
transport key must differ from the existing capability and event-derivation keys.
The sender contains no Supabase service key, user bearer or recipient. It posts
only to the fixed project `security-collector-ingest` URL. Request data cannot
select an origin, company, recipient, account or key version.

The seven-field body and event ID are the exact saved producer bytes. Body and
event rows must agree, JSON must round-trip without added/duplicate fields, and
the event time must remain within the collector's ten-minute acceptance window.
Expired/invalid evidence is held, never retimed, deleted or relabeled to force it
through. Fresh v2 transport timestamps/signatures can be generated on retry;
occurrence time and original body remain immutable.

Actual workerd rejects `redirect: 'error'`. The adapter uses `redirect: 'manual'`
and holds every 3xx response without following it. This was verified in the real
runtime, rather than assuming Node/Deno fetch options work at the edge.

## Durable claims and receipts

One SQLite transaction claims a due event, increments its attempt count and
stores an `inflight` receipt. A ten-second claim lease exceeds the hard five-second
fetch deadline. Competing calls claim once. A failed/unknown acknowledgement
retries the same bytes after fixed one-/five-second backoff, at most three times.
After exhaustion the evidence remains `held_attempts`; unauthorized, redirect,
invalid, clock and expired states are distinct durable holds. A rollback or crash
can reclaim the same event only after its lease expires.

Only an exact 204/no-body response from the fixed ingress acknowledges delivery.
The reused ingress independently verifies the v2 MAC and returns 204 only when
the database response matches the signed event ID. A wrong database ID remains a
retry. Outbox ACK and the `collector_delivery_receipts` update commit atomically;
a local receipt failure preserves the inflight claim for duplicate-safe recovery.
This receipt means collector acknowledgement, not notification delivery, display,
Master review or attribution of an attack to a person.

The new receipt table has one row per existing event, whose admission is already
bounded to 1,000. It is created only when trusted enabled delivery is called, not
by OFF configuration. Event/receipt deletion and observation retention are not
introduced here. Root must connect retention and key/lease coordination before
production activation; an exhausted budget or stale key must not silently erase
coverage. Revocation is enforced by the existing trusted collector registry, not
by inventing a key from an incoming request.

## Evidence and limits

Nine new tests execute real workerd WebCrypto and SQLite and invoke the unchanged
PR1438 ingress handler through a fixture service binding. CI checks out exact
commit `20f516d662e8e50458db68ba3e8a39772d93454d` solely as proof source. Its handler
SHA-256 is `a893415c6cbbfb29df061c101fae1b802a25cabe343c8958c62916b423f75cda`
(Git blob `20c4e3cb1aedf506a05198957ff9342be0469196`). No copied implementation or
runtime dependency on an unmerged branch is added to the production module.

The tests cover OFF/no writes, key separation, exact v2 byte transport, committed
ACK loss plus restart, fixed retry/attempt bounds, held expiry/corruption/auth,
hard deadlines when abort is ignored, 3xx refusal, concurrent claims, wrong ACK
and local receipt rollback/recovery. The database response in this new connection
fixture is synthetic; PR1438's separate successful Native94/real-GoTrue37 proofs
remain the evidence for its real PostgreSQL/PostgREST/Auth boundaries.

Still required: hosted gateway/HMAC-only ingress deployment settings, real host
and key lifecycle/recovery, signed startup anchor enforcement, scheduled bounded
drain/retention, trusted incident/notification outbox and current-Master binding,
actual notification receipt/closure, rollout and owner iPhone verification. The
existing synthetic incident-import outbox must not be used for these live events.
No production or iPhone completion follows from these fixture tests.
