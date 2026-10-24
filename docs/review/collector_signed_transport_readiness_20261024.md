# Existing collector signed transport: source review and next verification

Reviewed main: `c3042d23e01a176e28b9ac51dfb91d814008e057`. Existing source: `support/collector-signed-transport-20261020` at `5b38188c0c16a358905f0ce5a55b4c288046e1d2`.

This candidate copies the existing five files under `tool/security/collector_signed_transport_candidate/` without edits. The four SHA256 values in the original manifest all match. No new authentication mechanism, DB migration, HTTP listener, credential lookup, role provisioning, gate activation, or production connection is introduced.

The existing server-only signer and receiver bind the collector UUID, millisecond timestamp and raw UTF-8 body to a domain-separated SHA256 HMAC. The receiver starts disabled, checks the exact route and content type, caps the body at 1024 bytes and one second, validates the seven metadata fields, and does not retain incoming IP/path/headers. The existing sink uses parameterized SQL, a single exclusive connection already assuming the dedicated collector role, and transaction-local statement/lock deadlines. It relies on the existing database function for durable same-ID idempotence and conflicting-payload refusal.

## Verified now

All 12 existing Node unit tests succeeded on Node 24.19.0. They cover default OFF, valid raw signatures/retries, tamper/wrong key, time/collector mismatch, metadata injection, routes/method/encoding, streaming bounds, malformed JSON/UTF-8, persistence failures, role refusal, fixed parameter SQL and transaction-local deadlines.

The 14-check loopback HTTP/PGlite SQL integration is retained from the original candidate and is ready for CI. Its original manifest records earlier success; it has not been newly executed in this workspace. The pinned collector SQL is already present in current main at `docs/candidates/security_collector_storage_v1_20261020.sql.review-only`, SHA256 `b96f6e4365e2e992886f38dad0f777e55665f18b03525cddf4edbdf746348207`.

Use the current paths (the preserved original REVIEW.md uses an older shorter directory name):

```sh
node --test tool/security/collector_signed_transport_candidate/collector_signed_transport_test.mjs
npm ci --ignore-scripts --prefix tool/security/fixture_dependencies
node tool/security/collector_signed_transport_candidate/integration.mjs "$PWD/tool/security/fixture_dependencies/node_modules/@electric-sql/pglite/dist/index.js" "$PWD/docs/candidates/security_collector_storage_v1_20261020.sql.review-only"
```

The dedicated `.github/workflows/collector-signed-transport-review.yml` runs these commands on relevant PRs and main pushes with contents:read, disabled checkout credential persistence, and no hosted secrets or environment. It verifies the preserved manifest before testing and uses the existing pinned fixture lockfile without modifying it. The integration binds only an ephemeral loopback listener and uses a generated in-memory test signing key. No shared workflow is edited.

## Remaining boundaries

This source/CI slice does not depend on the missing three-file collector scope-proof candidate and does not resolve it. The integration uses a fixture-only consume-proof function that always raises; Master proof issuance/read is not exercised. Never deploy that stub or the synthetic fixture roles.

Before production, retain the original candidate's unfinished boundaries: native PG17 integration, full reviewed proof prerequisite and original setter compatibility, explicit key-bound collector provisioning, restricted SET-only bridge login, trusted producer wiring, secret provisioning/rotation, TLS and server admission, finite connection/infrastructure deadlines, operational delivery and retention/monitoring, authorized Master read/UI and explicit gate control. Same-event retries are valid but signed conflicting same-ID payloads must remain errors. A honeypot contact alone is not proof of an attack or authorization for automatic blocking.

No production deployment, external send, permission change, or live honeypot/dynamic protection is claimed.
