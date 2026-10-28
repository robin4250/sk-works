# Successor possession ACK and lost-ACK response recovery — OFF review

The private review SQL adds an independent false-by-default ACK rollout and one
request-keyed possession record. Its two functions reuse the existing native
enrollment context, request snapshot, claim and completed successor receipt.
They require the **exact recorded successor SID**, actor, live Auth session and
unchanged company/Google/profile/password/Apple-permit evidence. The original
caller SID and another same-UID SID cannot read status or acknowledge the receipt.
Neither a supplied successor ID nor user metadata selects the server identity.

The server port independently validates the exact bearer through its trusted
Auth adapter, snapshots UID/SID/expiry before pool awaits, binds those scalars to
transaction-local privileged context, and passes only fixed SQL parameters.
Input accessors/inheritance/extra metadata are rejected. Raw bearers/passwords/
access or refresh credentials never enter SQL or result bodies. All public,
authenticated, anonymous and service-role access to the private tables/functions
is revoked, RLS is enabled, and no execution role/owner/grant is broadened.

`status` returns only a request-bound `server_completed` or
`successor_possession_recorded`; `acknowledge` can only record the latter.
Both return `retry_allowed:false` and `application_adoption_confirmed:false`.
Possession ACK means a client with the independently authenticated successor
session contacted this boundary. It cannot prove isolated SDK inspection,
secure credential persistence, global application adoption, or a human action.
No security-sensitive action is authorized by this record.

ACK retry is idempotent on the original request/actor/SID and retains the original
timestamp. In a tested real-SQL composition, COMMIT executes, its response is
discarded at the adapter boundary, and a newly authenticated lookup/re-ACK finds
the one unchanged record. This does not retry native enrollment, retransmit a
credential, erase a durable pre-link claim, or interpret loss as rollback.
An unresolved enrollment with no recorded successor receipt remains unavailable;
the original caller cannot infer its status. Losing all successor credentials
therefore still needs separately reviewed recovery, not a token resend here.

Tests import the existing owner-policy/native enrollment/successor SQL verbatim.
Local Node contract tests: 6 passed. PGlite 0.5.8: 7 passed, 2 Native-only skipped.
They cover OFF/ACL/RLS, exact successor-only access, stale company/identity/
credential/account evidence, record immutability, rollback, no Auth/business
writes, and lost post-COMMIT response recovery. Dedicated PostgreSQL 17.6 CI
adds real two-connection ACK races and token expiry during a lock wait; its
result is pending and must not be presented as successful before completion.
Auth tables and verifier responses here are explicit synthetic fixtures, not
an actual GoTrue/provider/iPhone test.

Still required: managed Auth configuration/session validity review (the existing
context alone does not prove inactivity timeout), deployed least-privilege
JWT-to-DB composition, bounded HTTP/rate-limit boundary, app-side ACK integration,
global Auth-write serialization/CAS and secure persistent adoption, device and
restart checks, retention/deletion compatibility, guarded install/unused restore,
and real owner approval. There is no public route, app feature enablement,
migration, production connection, provider change or main merge in this review.
