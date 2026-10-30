# Canonical PDF runtime candidate

This candidate advances the missing server renderer. It does not enable order
sharing, install a public endpoint, grant a database role, deploy SQL, or switch
any master flag ON.

## Reused implementation

`CompanySealPdf` now selects a loader at compile time. Flutter app builds still
call the same `rootBundle.load/loadString`; the rendering, fonts, seal geometry,
PNG validation, original form renderers and terms source are unchanged. A pure
Dart VM selects an internal file loader with a fixed asset allowlist and hashes.
An absolute deployment root is configured once. Traversal, arbitrary document
paths, escapes through symlinks, and changed asset bytes are rejected.

`tool/render_site_order_canonical.dart` reads one bounded private render-job
**evidence** object from stdin. It requires the approved issuer's one seal and
matching consent, the exact legal source and valid attachment schema. It copies
the original body and adds only that consent-bound seal snapshot, then executes
`TradeDocumentFormRenderer.canonical`. It never creates defaults, rereads live
company/stamp data, writes a financial row, or replaces an existing original.
Only PDF bytes go to stdout. Rejections use a generic diagnostic without bodies,
company/person names, stamp bytes or local filesystem details.

`tool/canonical_renderer/pubspec.lock` is a separate pure-Dart dependency closure.
Every dependency version and archive content hash matches the app lockfile.
The app's pubspec and lockfile are unchanged. The renderer does not require a
Flutter engine, UI session, display server or network access at runtime.

## Internal transaction coordinator

`site_order_canonical_renderer.mjs` is called by an internal request-scoped
server coordinator with a dedicated privileged connection and original verified
request claims. It is **not** a public upload API and never grants `service_role`
access to private registration. A client must not supply its command path, repo
root, process environment, DB connection, evidence, stamp or PDF bytes.

The coordinator checks its connection role, actor and live master gate, loads
only the exact actor/SID's frozen job, invokes the fixed Dart command, then calls
the existing private registration function. That function rechecks current
actor/SID/company/site/counterparty/link/approved evidence/master and calculates
the original PDF hash from actual bytes. An existing original is reused exactly
instead of regenerating timestamps. A COMMIT response loss is UNKNOWN, never
success and never an automatic retry. Recovery must use the same job/request. The caller must discard that dedicated
connection after a COMMIT transport error and must not return it to a pool.
Raw SQL/render exception causes are not retained in the returned error.

The Dart subprocess has a 30-second deadline and bounded input/output, no shell,
no inherited secrets or network configuration, and no per-document files. The
server coordinator must be deployed in the existing trusted backend execution
boundary. Hosted Supabase Edge Functions execute TypeScript/Deno; this is **not**
claimed to run a Dart process in the hosted edge runtime. Selecting/deploying a
supported internal runner and connecting its authenticated command route remains
an operational prerequisite, subject to production HOLD. It must not be replaced
by a public client-PDF upload or new trust in possession of a service-role key.

## Verification and remaining work

Local official Dart SDK 3.13.7, revision
`416e33b0ffaef062a60ec966bb8c82ed2b83f128`; SDK ZIP SHA256
`eb99aed266efbcb615c6ae21c12f52cfe935b9f208bccc5fea7f64c21e867229`, verified against
its official hash. Node coordinator tests: 6 passed. Real Dart subprocess tests:
4 order/acceptance schema-1/2 PDFs plus 5 rejection boundaries passed. Each PDF is
A4 two pages and contains all 22 confirmed legal articles. Existing consent/API
SQL -> frozen job -> actual Dart PDF -> immutable private original/receipt ->
exact retry and OFF refusal succeeded in disposable PGlite. Existing 43 private
registration, 238 consent and 18 confirmed-terms checks ran unchanged as the
necessary fixture dependency, not as new live-Auth proof.

Dedicated CI compares actual Flutter application and server rendering: exact
page text and pixels for all four cases, preserving the original form sources.
That CI, native PostgreSQL/real-JWT server route, approved reply dispatch,
notifications/restart recovery, deployment and phone behavior remain separately
verifiable stages. Do not call site-order sharing complete from this candidate.
Production HOLD/default OFF/individual document exemption OFF remain unchanged.

## Review corrections

Recovered local recipient-binding WIP was newer than PR1632/bdc's published
five-argument prepare function. The first runtime CI therefore failed at the
six-argument fixture call even though local tests used that recovered WIP.
The forward candidate explicitly includes the recipient-bound SQL, fixture and
driver source. Success from that mismatched head is not adopted as final proof;
all changed blobs and the rendering dependency closure must match the published
tree before accepting latest CI.

A disposable actual-SQL RED reproduced first registration of a stale job after
the document current revision changed. The corrected private function checks
current approved revision for a first registration, while preserving exact
historical-original receipts for already registered bytes. Regression tests
cover both branches. New original/job tables also reject TRUNCATE, including
CASCADE, in addition to UPDATE/DELETE. This is defense against accidental
internal operations, not a claim that a PostgreSQL superuser cannot disable a
trigger or drop a schema.

The new original/job triggers also pin the existing immutable trigger function's
body MD5 `73660d9947f20d6f99c59d8451078e7e`, owner, search path, client EXEC and
SECURITY INVOKER attribute. A deliberately changed dependency is rejected before
new-schema creation in the disposable fixture, with the original definition
restored by transaction rollback. No dependency body or attributes are changed
by the real candidate.
