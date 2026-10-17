# Master credential journal: logout and retention boundaries

Baseline: main `bb78cc0ca39f72ad0b00898041fc536a3458f365`, tree `741518af5cc81f22f9f9f23c0ab7e33639bf6b1f`.
This addition changes only a test, this document, and their dedicated workflow. Product authentication, logout, repository, SQL, flags and production settings are unchanged. Dedicated Master mode remains OFF.

## Existing behavior and limits

The durable journal contains only actor, original session ID, device fingerprint, request UUID, operation and expected credential version. It contains no token, password, device key or nonce. Existing repository methods do not subscribe to signedOut to remove this journal. An actor/session change therefore does not imply a failed write and does not erase unresolved operation identity.

| Evidence/state | Permitted cleanup | Automatic retry |
|---|---|---|
| Exact applied receipt | Remove exact original journal record | None |
| Exact terminal not_applied receipt | Remove exact original journal record; require new manual confirmation | None |
| not_found, timeout, malformed/corrupt record | Retain unresolved metadata | None |
| Logout, actor change, new session, nonce deadline | Not evidence that a write did not commit; retain metadata | None |

`forget(pending)` uses the captured actor/session/request key and checks exact serialized metadata before removal. It must not derive its deletion target from a later global currentUser or late signedOut session. The existing method is not a general-purpose atomic cross-isolate compare-and-delete primitive. These tests cover the present serial application call behavior, not arbitrary interleavings between independent writers or processes.

The receipt API binds the original actor/session/device. A new session for the same user cannot recover an old-session receipt under this contract. `pending(newSession)` returns no old-session record while the old record remains stored. This is session isolation, not proof that the old operation failed or a global block on all new-session manual actions. No product change in this addition automatically replays or clears old operations.

A finite TTL cannot safely be inferred from the 120-second challenge lifetime: a committed operation may have lost its response. Eventual bounded retention and cross-session reconciliation require a separately reviewed server contract, such as fresh same-Master authentication and authorized discovery of that Master's original request. No such API is introduced here. Unknown/corrupt records are not silently discarded.

## Three additional test boundaries

1. Reuse the existing pinned SDK PKCE-removal race: A starts local logout, B signs in while storage removal waits, then a late signedOut event carries B. Exact A and B journal snapshots both remain unchanged. The logout request still carries A's token and local scope. This does not prove that global Flutter persistence/Realtime listeners are unaffected by the SDK race.
2. For both applied and not_applied receipt results, captured A cleanup removes only A's exact record while B remains. Replaced metadata at A's same key causes rejection and remains untouched. No mutating RPC is sent.
3. A product repository commit has a synthetic lost response; not_found remains unresolved. After actual SDK local logout and same user re-login with a new session ID, original metadata remains, cross-session receipt is rejected locally, and the HTTP ledger contains exactly one mutation and one original receipt read. No automatic clear or resend occurs in this exercised path.

These supplement existing same-session restoration, corruption/device isolation and unknown-result UI tests; they do not repeat their whole matrix. Tests use the actual pinned Supabase SDK and SharedPreferences test implementation, synthetic .invalid HTTP responses/session tokens and a deliberately delayed PKCE storage adapter. They do not contact Supabase production or run a real GoTrue server, native OS secure storage, Face ID, or an iPhone. HTTP failure is synthetic and does not establish the server's committed outcome. Actual PostgreSQL receipt semantics were separately tested by the previously merged isolated server/API workflow.

## Validation

Dedicated analyze and three boundary tests: pending CI. Report the exact successful head/run separately; a test artifact alone is not a passing execution.
