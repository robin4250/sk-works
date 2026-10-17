# Disposable loopback transport fixture

This is a test-only adapter around the existing synthetic DecoyLab. It has no CLI,
SKO import, Supabase/LINE client, public listener, production credential read or
deployment configuration. `startIsolatedTransport` always binds an ephemeral port
on `127.0.0.1`; the caller supplies an ephemeral random 32-byte hexadecimal token.
Never substitute a production API key or user password.

Run `node --test tool/security/isolated_transport_test.mjs`. Real local HTTP and TCP
requests check body/URL bounds, chunked uploads, incomplete headers, request deadlines,
concurrency rejection/recovery, global rate rejection/recovery, authenticated operator
rotation/quarantine/release, current/retired paths, unrelated-route 404, secret/header
non-retention, bounded metadata/drop/expiry counters and clock-regression rejection.
The tests also preserve the existing offline controller/collector/review tests.

Only exact POST control paths accept the bearer token. The fixture never uses proxy
headers for identity or rate decisions. Body bytes are counted and discarded, never
parsed or logged. Every response closes the connection, and incomplete sockets time
out. Transport inspection is an in-process operator API, not a public HTTP endpoint.
The test process itself can observe synthetic operator credentials; this is not a
production credential vault. Retired-lure touches remain synthetic review events,
never proof of malicious intent, a real person, or real attack prevention.

`isolated_transport_manifest.json` records isolation requirements and explicitly has
`deployment_ready: false`. No outbound application client exists, but this does NOT
prove OS/container egress denial. No public hosting, firewall, WAF, network topology
MTD, durable ingress collector or production auto-blocking is provisioned. Host-level
egress/ingress isolation, durable monitoring, key lifecycle, independent review and
recovery exercises remain gates. Local/global limits protect only this disposable
fixture and are not Supabase API rate controls. Existing business data and normal
SKO routes are not connected or modified. Close the fixture after every test.
