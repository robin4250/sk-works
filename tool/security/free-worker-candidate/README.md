# Free Workers security runtime candidate — OFF, not deployed

This is the minimal executable continuation of the reviewed free-Workers design.
It creates no Cloudflare account, deployment, DNS change, paid plan, external
delivery or production DB mutation. Existing build20/IPA and attendance second
password behavior are untouched. No production DB/API key is configured.

## Implemented boundary

- `src/worker.mjs`: exact synthetic hostname/GET/path routing. Query, unknown
  routes, normal SKO API routes and all operator/manager paths are unavailable.
  Incoming identity/forwarding/Authorization headers do not enter event records.
- `src/broker.mjs`: actual SQLite Durable Object. Both environment activation and
  durable policy activation are required. The default durable policy is OFF.
  Policy revision/epoch changes use synchronous transactional CAS with a bounded
  audit. Public code never calls the control transition function.
- Public capabilities have a dedicated audience/method, 60-second expiry, epoch
  and one-use nonce. Rotating/quarantining/releasing the durable policy changes
  real admission before Wasm execution. Old epoch/invalid/expired/reused tokens
  do not execute Wasm. This is application admission MTD for the decoy only,
  not a managed Cloudflare WAF rule or Supabase direct-access defense.
- Events/outbox use one SQLite transaction with nonce consumption and sequence
  advance. Defaults are 100 events/500 capability issuances per UTC day, 1000
  retained events and 1000 control audit rows. Any bound/clock/CAS/storage error
  refuses admission. These are conservative application bounds, not a guarantee
  against account-wide free-quota exhaustion. Old rows are never silently dropped.
- Durable outbox claims have bounded leases/attempts. A workerd restart can
  reclaim the same original body/ID after an ambiguous outcome; an old claim
  cannot ACK a new lease. Exhausted attempts remain held for operator review.
- `src/protocol.mjs`: WebCrypto adapter preserves PR1435's producer domain and
  seven-field body. The live connection format is collector **v2**, including
  key-version in the signed domain. V1 exists only to compare the unchanged
  historical protocol. No network sender or successful-delivery stub is wired.

## Exact Wasm artifact, with a narrow isolation claim

`tool/build_wasm.py` reproducibly generates the checked-in `src/decoy.wasm`, WAT
source and manifest. The 150-byte binary SHA-256 is
`072f7e18d8b7d3b285c3bdfc62afc543397fb189b5cd7e32da980b0d710d2127`.
Its imports are empty, exports are fixed, and its sole memory is 1 page with a
1-page maximum. It returns only the existing DecoyLab constant synthetic body.
No imported JS function, WASI, memory, network API, environment or key is supplied.

CI hashes the **actual compiled binary** and verifies it equals the manifest.
The Worker checks manifest bytes, compiled module imports/exports, memory growth
refusal, status/pointer/length and exact returned bytes. Compiled modules cannot
be serialized to rehash at runtime: the actual-file hash assurance comes from
the reproducible generation/build artifact and CI, not an invented runtime
serialization API. No arbitrary module/code is accepted from a request.

Only the constant response body executes in Wasm. Routing, policy, crypto, event
metadata and DO persistence are **trusted JavaScript**, not Wasm-isolated logic.
The Worker runtime itself has network APIs; this is not OS-wide egress denial or
Docker network-none proof. It does not imply protection from engine/host compromise.

## Actual runtime verification

Exact development dependency: Miniflare `4.20260730.0`; locked workerd
`1.20260730.1`; compatibility date `2026-07-30`. The dependency lock includes
integrity hashes. No package install lifecycle scripts are needed.

The new tests run real local workerd, native Workers WebCrypto, compiled Wasm and
SQLite-backed Durable Objects on a disposable persistent directory. There is no
Map/SQL mock. They cover actual production entry OFF/no-fixture routes, valid
admission, replay/epoch/expiry/tamper refusal before Wasm, real CAS race, actual
transaction rollback, quota refusal, quarantine/release, workerd replacement,
same-byte outbox retry/stale-ACK refusal and collector-v2 public test vector.
The existing DecoyLab source is hash-checked and its constant body/state shape
compared; old successful suites are not rerun.

```sh
npm ci --ignore-scripts --no-audit --no-fund
python3 tool/build_wasm.py
node tool/verify_artifact.mjs
SKO_SECURITY_SOURCE_ROOT=/absolute/repository/tool/security npm test
```

The runtime fixture exports a test-only subclass that can initialize/change
synthetic policy and inspect SQLite. The production entry does not import it.
Never deploy `tests/runtime-fixture.mjs`; review configuration points only to
`src/worker.mjs`. Test keys/IDs/vector are public synthetic fixture values.

## Still blocked / not complete

`wrangler.review-only.jsonc` has no account, hostname, route, destination or
secret; workers.dev/previews are disabled, activation is false. There is no
deploy command/workflow. Root owns any real host/account/key/activation work.

Missing: authenticated Master control/capability issuer, independent key
provisioning/rotation/recovery and configuration identity binding, signed audit
head/independent anchor, bounded real delivery/alarm and collector-key rotation,
retention/coverage reporting and real Master notification/iPhone display. The
current control audit is unsigned SQLite metadata, **not** tamper-proof audit.
Trusted daily ingress source pseudonymization is not wired; correlation remains
`decoy_generation_only`, never a person/attacker identity. No real attack is generated.

No public control hook is exposed until those prerequisites exist. Test-only
policy setup does not prove Master authentication. A local workerd restart is
not proof of Cloudflare account/volume disaster recovery. Actual free-tier CPU,
quotas, provider metadata logging, deployed negative/normal-access tests and
operational recovery remain unverified. Platform exhaustion may prevent even a
health/notification call; the normal SKO app is deliberately outside this route.

The candidate is implemented/tested, not main-integrated, deployed, enabled or a
completed honeypot/MTD security system. Other-user distribution remains blocked.
