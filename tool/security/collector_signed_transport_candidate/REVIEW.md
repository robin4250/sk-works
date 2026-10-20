# Collector signed transport integration candidate — review only

The native collector proof rehearsal succeeded as `collector-proof-rehearsal-a1agy9dn`; that success did not authenticate a network sender. Existing `isolated_transport.mjs` is a decoy loopback lab; `platform_log_adapter.mjs` uses HMAC for pseudonymization, not event transport authentication. Neither is replaced here.

This server-only candidate adds a handler, signer and fixed parameterized PostgreSQL sink. There is no automatic listener, environment/credential lookup, DDL, role grant, production deployment or client import. Default OFF is required and tested. Collector ID and a copied 32-byte random signing key are supplied by the trusted server operator. The signed input is domain-separated `sko-collector-v1\n<collector-id>\n<millisecond-timestamp>\n` followed by the exact raw body bytes. The receiver pins collector ID, accepts only ±60 seconds timestamp, compares SHA256 HMAC with timingSafeEqual, limits streaming body to 1024 bytes/1 second, rejects encoded bodies and wrong routes, and validates the exact seven metadata fields. No incoming IP/path/header/body is persisted or logged.

The sink sets transaction-local statement_timeout=5s and lock_timeout=1s before any role check or persistence call. The exclusive PG connection must already assume `sko_security_collector_ingest`; the sink checks current_user inside its transaction before using only `private.ingest_security_collector_event($1::jsonb)`. It never borrows service_role/owner privileges or creates membership. Same signed event retries intentionally reach the existing durable DB idempotence check. Conflicting same-ID payloads remain errors. DB gate OFF, bad role, write failure and unknown COMMIT outcomes return an empty unavailable response; no private error detail is returned. Unknown outcomes can be retried with the identical event ID/payload, never a new generated ID.

Validation:
- Node unit tests: 12 passed (valid raw signature/retry, wrong key/tamper, timestamp/collector mismatch, field injection, route/method/encoding, streaming bounds, signed malformed JSON/UTF8, sink errors, role refusal, fixed parameter SQL and transaction-local statement/lock timeouts).
- Real loopback HTTP + generated ephemeral HMAC key + exact existing SQL candidate (`b96f6e4365e2e992886f38dad0f777e55665f18b03525cddf4edbdf746348207`) on PGlite PostgreSQL17.5: 14 checks passed. Gate OFF refuses, ON persists one event, retry stays one, changed payload refuses, bad signature/extra IP refuses, API roles refuse, final gate OFF refuses.
- The test-only consume-proof function always raises and is never called. This slice does not test Master proof issuance/read. It does not replace the reviewed proof prerequisite in native rehearsals.

Still required before deployment: parent review; native PostgreSQL17.6.1.166 integration against the full reviewed proof prerequisite; trusted producer integration and secret provisioning/rotation; TLS/server admission controls and finite DB connect and infrastructure admission deadlines; explicit key-bound collector provisioning and bridge login SET-only role review; signed event delivery/operational coverage; Master real reauthentication/read UI; honeypot/dynamic gate control. Public binding and autonomous deployment are deliberately absent. This is an integration candidate, not live honeypot/dynamic protection.

Run unit tests:

```sh
node --test tool/security/collector_signed_transport/collector_signed_transport_test.mjs
```

Run integration with an explicitly pinned PGlite module path and reviewed collector SQL file (the exact collector SHA256 is enforced before use):

```sh
node tool/security/collector_signed_transport/integration.mjs /absolute/path/to/pglite/dist/index.js /absolute/path/to/security_collector_storage_v1_20261020.sql.review-only
```

Signing authenticates exact bytes. JSON whitespace is permitted; a trusted producer must emit unique object keys using JSON.stringify, never user-provided serialized JSON. The handler retains only JSON.parse's validated seven-field result; it does not log the raw signed document. Signing keys and all generated ephemeral test secrets remain outside the repository.
