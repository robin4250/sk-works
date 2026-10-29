# QR scanner registration UI composition — OFF and unexposed

The new page/controller joins the real existing native signing bridge to the
existing HTTPS challenge/password-proof/PoP/receipt contract. No main.dart route,
menu, public listener, server SQL, permission, migration, activation or dependency
is changed. Controller, transport, journal and existing key preparation default
OFF. Generated iOS preparation retains the fixed-false native gate.

## Explicit new logical enrollment and recovery

Missing local state never triggers automatic identity generation, key replacement,
registration or retry. An absent, successfully read native journal offers a
separate explicit NEW logical device setup, with an affirmative UI confirmation
and fresh native user presence. Native initialization refuses any existing or
ambiguous journal/marker or scanner key namespace. It generates a UUID only in
this explicit path, commits a permanent scope marker first, then the pending
intent, and reads both back. A crash/unknown ACK between those items blocks;
there is no delete/reset/overwrite API. If all local evidence was erased, this
cannot prove a device's physical history or 'first ever' enrollment. An explicit
new logical enrollment cannot overwrite/revoke old server rows; the unchanged
server membership, manager permission, exact live SID, second password, PoP,
rollout and duplicate rules remain authoritative.

The non-secret record binds original actor/SID/company/device/keyhandle/nonce,
public key, challenge snapshot, monotonically increasing version, per-write
request IDs, stage and final immutable registration event ID. No bearer/password/
raw proof/private key/signature is persisted. Keychain uses fixed services,
non-synchronizing WhenPasscodeSetThisDeviceOnly and no shared access group.
Journal updates are atomic item replacements serialized on the app main queue,
not global compare-and-swap, a multi-item OS transaction, independent storage
attestation or physical identity. Cross-process writers/privileged rollback,
retention/erasure and signed-device persistence remain release blockers.

| Saved stage | Allowed next action |
|---|---|
| key_pending | Explicit local key preparation, no remote write |
| key_ready | Save challenge_sent ACK before challenge request |
| challenge_sent | Read original exact scope using challenge_result; missing result remains unknown |
| challenge_ready | Save proof_sent/request ID before a password request |
| proof_rejected | Only a known accepted=false response permits another explicit password attempt with a new saved ID |
| proof_sent / proof_delivered | Read proof_result; committed evidence cannot recover raw proof or authorize reissue |
| proof_lost | Block completion/reissue; historical status only |
| completion_sent | Read original result receipt; never resend completion |
| confirmed | Recheck exact immutable receipt, never register again |

A live raw proof exists only in the current controller call. After its known
receipt, proof_delivered is saved before native PoP; completion_sent is saved
before the registration write. An HTTP200 completion is still checked against
its exact immutable result receipt before confirmation. Late/failed local ACKs
prevent the next remote write. Reload reads original records; it does not
restart writes. Known wrong-password retries retain each request reference and
stop locally after five attempts; existing server failure counters/lockout are
unchanged. Unknown password outcomes never become known-negative by assumption.

The session guard captures the exact SDK Session/token, ignores only the first
identical cached Session object, invalidates fresh login/refresh/history/errors/
completion/background and verifies exact-token GoTrue user before each native
or server operation. The server independently checks actual live SID and scope.
Dispose/background settles logical waits and cancels owned native/HTTP work;
it does not claim a running server transaction was cancelled. Raw proof is
lost on disposal/restart and must remain blocked rather than persisted.

## HTTPS boundary and verification limits

Only a trusted constructor origin can select the fixed HTTPS path. Operation
inputs cannot select actor, SID, pool, project, origin or arbitrary body fields.
Redirects are disabled, exact request/schema/operation/scope/receipt status is
checked, and response data is capped before buffer growth. One monotonic fifteen
second budget spans headers/body/parse, with an owned abort timer. Auth has its
own five second bounded wait; the shared Supabase client is never closed.

Focused Flutter tests compose actual controller/journal/key bridges, pinned SDK
and typed HTTP contract against explicitly synthetic MethodChannel/storage/server
fixtures. They verify write-ahead ACK ordering, lost acknowledgement recovery,
no resend, same-UID other-SID denial and secret-free pending records. They do
not prove actual Keychain durability, user presence or database registration.
Separate real IOClient TLS tests use an ephemeral certificate trusted by its CA
(no certificate bypass) to check stalled/error/unconsumed-body owned aborts and
one total budget. Native fixtures execute the actual transition policy rather
than a mirrored policy. Actual Keychain success can remain unavailable on
hosted processes; this is reported and never relaxed. Existing foundation tests
already prove native CryptoKit signature interoperability with the Node verifier.

Still incomplete: signed iPhone presence/cancel/background/restart/Keychain ACK
and native-to-real-GoTrue/PostgreSQL full flow, real hosting/admission/least-
privilege pool, no cross-process journal writers, restoration/retention policy,
canonical attendance mode/writer and reviewed route/feature activation. Individual
document exemption and all production rollout settings remain OFF.

Pinned HTTP abort API consulted (http1.6.0):
https://pub.dev/documentation/http/latest/ and
https://pub.dev/documentation/http/latest/http/Abortable-class.html

The production transport creates the standard non-retrying http.Client; injected
clients are restricted to the explicitly named testing constructor. Only its
own client is closed on controller disposal, never the global Supabase client.
Local presence may itself cause real iOS inactive transitions: current guards
remain strict, and mocked channels/compilation do not establish that physical
Face ID/passcode UX succeeds. Signed-device inactive/background/cancellation
checks remain required before activation; no lifecycle condition is relaxed.

## Retired initial load continuation (OFF)

The original controller released its prior session owner with an await, then
unconditionally reacquired an SDK subscription. Immediate disposal or a newer
load could retire that continuation during the await (even the initial null
owner yields). A captured load epoch and disposal check now refuse reacquisition
before constructing the new owner. This does not change session, company, SID,
journal, key, password, or server permission rules.

Two focused regressions observe subscription/lookup requests while delegating
to the exact actual SDK Session and Auth event stream: disposal must acquire
nothing, and two initial loads must acquire only the latest owner. CI first
runs those tests against the exact original d7c105d5 controller, requires the
specific subscription assertion failures, and restores/hash-checks the corrected
source before the full focused suite. CI results remain pending until observed.
Physical Keychain/presence, hosting, attendance integration and activation remain
separate incomplete stages; this is not evidence of a registered new device.
