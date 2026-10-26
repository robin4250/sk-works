# Independent anchor authority storage companion

This supplies the missing **storage adapter core** for independently retaining
the existing signed management/recovery/retention audit head. It reuses
`security-audit.mjs` and its exact `sko-decoy-anchor-v1` receipt format. The
existing `acceptIndependentAnchor` and `verifyAuditChain(minimumAnchor)` consume
the result without changing their trust rules. Original core SHA256 is pinned
in the tests; no second cryptographic implementation is introduced.

## Implemented

`initializeAnchorAuthority` pins the deployment/company/owner, original audit
public key, and a different anchor public key/key ID. SQLite holds only the
public trust configuration, monotonic head, the last signed audit witness and
signed anchor receipt history. The witness binds the separately saved audit
clock to a signed body and head hash, preventing audit-time drift across batches.
It never holds SKO service credentials, a Google session, or an anchor private
key. Existing trust mismatches refuse rather than replacing keys or resetting
history.

`preserveIndependentAnchor` checks at most100 actual signed audit records from
the expected prior head (450KB overall, 4KB per audit body). Signatures, SHA256,
sequence, previous hash, deployment, company, owner/system-retention actor and
nondecreasing audit time must match. A valid audit signature for a different
company/owner is insufficient. There is no request-controlled configuration,
destination, key lookup or account. The independently supplied nonextractable
signing key must produce a signature under the pinned anchor public key.

Receipt insertion and monotonic head advancement commit in a single SQLite
transaction after rechecking the snapshot. Concurrent publication accepts one
head; SQL failure rolls back both. Lost-ACK resends of the exact verified head
return the saved signed receipt, with its original timestamp and signature.
Earlier heads, forks, gaps, clock regressions and changed trust reject. The
1,000-receipt limit fails closed without deleting evidence or buying capacity.

`latestIndependentAnchor` verifies the saved signature and matching immutable
receipt/head before returning it. Restart or restored source data can use that
receipt as the existing verifier's minimum anchor. Source rollback below that
retained head fails without asking the source to invent a new history.

## New actual-workerd verification

Seven tests execute actual workerd WebCrypto/SQLite with two separate synthetic
Durable Objects and the unchanged real management/signed-audit core:

- signed source → durable authority receipt → unchanged source acceptance;
- restart, same-head ACK loss and continuation from the retained head;
- malformed/gapped/forked/tampered/wrong-key and trust configuration rejection;
- validly signed wrong company/owner/deployment/future-time denial;
- competing publications and actual receipt INSERT failure with rollback;
- authority corruption refusal and source rollback below the independent head;
- cross-batch audit-time regression refusal, while delayed valid records before
  the previous receipt issue time remain acceptable.

All seven passed locally using the already-pinned Miniflare/workerd dependency.
Local Flutter/Dart, original unrelated tests and production writes were not run.
The isolated authority and source objects in one test runtime prove the adapter
and protocol; they do **not** prove independent hosted failure domains.

## Still required before activation

This is not an HTTP endpoint or a real hosted anchor service. Source public
Worker imports remain unchanged, no service binding/route/account/alarm is
configured, and no anchor publication or notification is sent. A real authority
must live outside the decoy's restore/admin failure domain, with separately
controlled private keys, key-recovery/rotation, authenticated transport,
budget/availability/retention monitoring and durable backups. Startup must fetch
the independently trusted latest receipt and fail closed on missing/stale trust;
an old/empty caller-provided receipt is not enough. Delayed batches must be
published in bounded consecutive chunks; a source may not prune unanchored rows.

This covers existing **management/recovery/retention** signed audits only. It
does not relabel legacy observation/control rows as signed. The real Master
proof-to-management-capability issuer, observation signing and notification
outbox/recipient/current-Master binding remain separate missing integrations.
No real host, real keys, notifications, public deployment or iPhone verification
has happened. It is not production-complete honeypot/MTD protection.
