# Collector client connection — isolated review candidate

Source baseline: main `22ecb36d0b15bc0fb498f3c23016508507ea5a99`.
The only existing product edit is the collector entry in
`security_incident_page.dart` (original Git blob
`5289eb16fe7195608857e061ee78cdb99c6a9950`). The sparse directory must not be merged as a repository root;
adopt only its seven changed/new owned paths onto the selected main tree.

## Existing evidence reused

PR 1345's actual local GoTrue/Edge issuer and PR 1346's public POST reader proof
already establish the isolated actor/session/operation/target/TTL/replay/gate
boundaries. This client does not recreate the three missing historical sources,
replace SQL, activate gates, add keys, produce collector events, or send telemetry.
Those successful backend cases are not rerun just to add this client.

The new repository requests exactly `master.security_collector.read` with target
`{"scope":"decoy_collector"}`, then calls exactly
`master_security_collector_events(p_proof)` through the existing Dart POST RPC.
The proof lives in one call only; it is not persisted, put in a URL, retried after
failure, or passed to the platform monitoring scope. The response parser follows
the actual immutable collector consumer's five-field envelope and nine-field
event schema, rejects extra fields/unknown provenance/attack-confirmed claims,
limits 100 events and 128 KiB, and never displays raw credentials/network errors.

The existing MasterProtectedPage and SecurityActorBoundary protect navigation.
Client availability requires the server Master helper and existing master_security
capability; a client user role/claim does not grant read access. Every read still
requires the server proof consumer's current Master/account/session checks.
Actor or session replacement is sticky during requests. Backgrounding clears
records/passwords, invalidates pending requests and requires a fresh explicit
read. Cancellation before consumption prevents the read; cancellation after a
POST has started cannot undo the server transaction, but its result is discarded.

Missing RPC or disabled read gates are shown as unavailable, distinct from empty
records. Empty records never assert safety or uninterrupted monitoring. No export,
print, automatic refresh, cache, collector sender, or dynamic blocking is added.

## Verification and outstanding boundaries

New remote Flutter tests cover proof-per-read, authorization denied before issue,
session switch-away-and-back, cancellation before consume, unavailable public RPC,
malformed/wrong-scope/extra-field response refusal, unavailable UI and lifecycle
clearing. Local Flutter was not run because the session's prior restriction
continues. Exact PR1372 head `99e663f72b821018891adb6441daa4e2ab61eb5d`
passed the dedicated SDK3.47.5 analysis (No issues) and all 13 tests (repository8,
widget5) in run `40134201068`, job `120992127086`. Platform monitor UI and security
PDF checks also passed. Whole-app Flutter/iOS checks were still running when this
receipt was recorded; they are separate from the dedicated success.

Widget fixtures explicitly create and await their read-stage witness in the same
real async zone, then drain the repository's nested subscription-cleanup boundaries
before normal frame settling. The paused scheduler cannot paint a replacement
tree, so lifecycle tests assert stale/late response discard and no old record or
password after resume. They do not prove an iOS app-switcher screenshot cover.
Native privacy-cover behavior, if required, is a separate device/platform task.

## Async session-event correction after the 13-test receipt

The original successful head used void session notifications and reread the live
session when a notification arrived. Independent review identified a P2: an async
same-user session A→B→A queue can already have returned to A before callbacks run,
so the intervening session was lost. The upper actor-only boundary cannot detect
same-user session changes, and a still-live original session is not a substitute
for this sticky cancellation rule. No production exploit or collector operation
is asserted; the backend remains undeployed/default OFF.

The locked package is gotrue 2.27.2. Its official
[tagged client source](https://github.com/supabase/supabase-flutter/blob/gotrue-v2.27.2/packages/gotrue/lib/src/gotrue_client.dart)
(Git blob `225f928ac7ada94bb3cf53c37a3717035b3f5dd4`) uses the default async
ReplaySubject. The same tag's
[ReplaySubject implementation](https://github.com/supabase/supabase-flutter/blob/gotrue-v2.27.2/packages/supabase_common/lib/src/replay_subject.dart)
preserves event values through an asynchronous broadcast by default.

The correction emits each event's own user/session identity instead of void,
preserves signed-out null, and compares both that emitted identity and the current
session in repository/page listeners. Current-session before/after checks and
current expiry checks remain; only historical event identity avoids consulting
an already-restored current session. No raw bearer token is retained in the
signal, returned to the UI, persisted or logged. Revocation remains sticky.

Two default-async repository regressions cover same-user SID A→B→A and signed-out
null→restored A during proof issuance, both requiring zero consumer reads. One
default-async widget regression clears already displayed records and keeps the
route locked after same-user SID A→B→A. These three additional tests and the source
correction require fresh remote CI; the earlier 13 successes do not validate them.

The existing isolated real GoTrue tests do not prove production RLS or deployment.
PRs 1345/1346 are separate dependencies; this page on current production remains
unavailable until the issuer/public reader are correctly reviewed and deployed.
The unrecovered three historical sources, trusted producer/collector keys,
production gate/privilege/catalog audit, actual honeypot/dynamic defense,
leaked-password-protection setting, production monitoring and iPhone verification
remain unfinished. This patch changes none of them and does not hold the payroll
Release merely to recreate backend validation.

Primary documentation checked: Supabase Dart RPC and Auth session docs. The
changelog markdown endpoint returned unsupported-content-type through browsing;
no Supabase dependency or API convention is changed here. Dependencies remain
the repository's pinned versions.
