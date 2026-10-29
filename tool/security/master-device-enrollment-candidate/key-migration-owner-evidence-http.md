# Stored-issuer evidence in the existing HTTP candidate — default OFF

The existing migration request handler now accepts `owner-evidence` with exactly
`action`, `requestId` and a signed `receipt` whose request ID matches. The action
is disabled unless the server explicitly supplies `ownerEvidence.enabled=true`
and a `loadAuthorityCheckpoint` adapter. Default OFF/missing adapter returns 503
without fetching a checkpoint or acquiring the evidence DB pool.

The bearer verification adapter still exclusively supplies actor, live session
and request-scoped auth pool. Their scalar bindings, enable flag and checkpoint
callback are captured before the asynchronous request processing. The checkpoint
adapter receives only that verified actor/session plus cancellation signal; it
must obtain and authenticate a fresh external authority checkpoint. This handler
does not implement or invent that external authority or freshness proof.

The action always calls the existing `recordOwnerDecisionUsingStoredIssuer`:
private current-issuer/checkpoint validation and share lock, live owner/session,
owned device, original challenge/pending/request, cancellation, signature and
original-evidence checks all remain in the actual transaction. There is no fixed
pin import, mode selector, old-signature retry or fallback in this handler.
Body-supplied issuer mode, pin, checkpoint, actor/session and pool are refused.
A server-configured unused fixed pin cannot recover a retired-issuer receipt or
a stale checkpoint. Success says only `evidence_recorded`, never key activation
or independent owner approval. Responses are no-store; errors are generic.

Checkpoint/auth/body processing shares an absolute monotonic deadline, with lazy
work thunks and elapsed checks before invocation and after every awaited result.
This also catches synchronous callbacks that overrun before a timer can fire.
The evidence pool lease checks elapsed time again after acquisition and around
queries; a late lease is released once before BEGIN. Rollback/release remain
available for cleanup after expiry. A late checkpoint cannot start a new evidence
transaction after timeout. An in-flight DB commit
may still have an unknown outcome after the HTTP deadline; it is not cancelled
or undone by a timeout. There is no automatic replay or fallback. The new OFF
result action below reports an exact stored original without re-admitting it;
its public deployment and device UI remain unfinished.

## Exact historical result lookup

`owner-evidence-result` accepts the same exact request ID and full original
receipt, including its signature. It shares the OFF flag and monotonic/lazy work
and DB-lease guards, but does not need or invoke the checkpoint adapter. It never
chooses an issuer or calls the admission writer. A private transaction requires
the independently verified live actor and original session, current master role,
eligible owned device, consumed original challenge/pending key and exact owner
request/nonce. Another actor/SID, mutated receipt or changed source is refused.

Only exact equality with the immutable saved payload/signature, digest and
issuer/decision/time metadata can return `evidence_recorded`. The response also
reports the observed request state (`awaiting_independent_owner`, `cancelled` or
`expired`). This historical read remains possible after receipt expiry or issuer
retirement, but cannot override cancellation, extend expiry, approve or activate
a key. It does not revalidate an old issuer as current or fabricate fresh trust.
It reports matching stored evidence, not independent proof against privileged
DB insertion/rollback or a genuine independent human-verification issuer.

If no evidence row is observed, the result is `evidence_unconfirmed`, never a
definitive rollback/not-saved claim or permission to resend: an in-flight or later
writer can still complete. The action performs no INSERT/UPDATE/DELETE, retries,
request mutation or nonce consumption. A live original SID remains required;
reconciliation after original-session loss, device lock/revocation or account
restrictions needs a separately reviewed recovery path. There is no fallback.

This is a handler candidate, not a listener, public route, TLS/origin deployment,
real checkpoint provider, rate-limited production API or least-privilege pool.
Owner review requests still use the existing internal candidate; no complete
public owner-approval workflow or real independent-verification channel is claimed.
The internal fixed-pin test entry remains for existing disabled callers; other
future backend routes must also enforce stored issuer mode before any rollout.
There is no public grant, production change, active key/device registration,
old-key recovery, migration, document/signature rewrite or exemption activation.

## Verification

Nine new boundary tests cover OFF/missing adapter, body-selected privileges,
request mismatch, generic checkpoint failure, captured callback, late result,
synchronous checkpoint overrun and late DB acquisition. The last two failed on
the prior timer-only implementation (expired acquisition still reached BEGIN)
and pass after the monotonic/thunk/lease fix. The eight existing HTTP tests also
pass locally, for 17 total. The actual PGlite composition
now invokes this handler through real candidate pending/request/evidence code;
it checks current issuer success, retired/stale/replaced-history rejection,
ignored server fixed-pin fallback and verified-context mutation protection.
The same composition runs in Native PostgreSQL CI, including its existing
separate-connection receipt/rotation lock and fork tests.

The existing disposable real-GoTrue runner invokes the same HTTP actions
after real JWT verification and transaction-local claim installation. Its issuer,
checkpoint and master/device eligibility are explicit synthetic fixtures, not
independent human proof. It checks valid owner storage, body-mode spoofing,
forged bearer before pool, other-user/user-metadata denial, expired/deleted-session
refusal even for an already recorded receipt, and claim cleanup. Syntax passed
locally; real-GoTrue/Native CI outcomes must be checked on the new head separately.

The result increment adds five boundary tests (22 HTTP tests total) and extends
the actual PG/PGlite composition with a successful real DB COMMIT whose ACK is
then lost: the write returns HTTP409 and the result action reads its exact original
once without any lookup DML or checkpoint call. Wrong signature/decision/nonce,
actor/SID, unconfirmed absence and cancelled/expired/retired historical results
are checked without changing original evidence. The real-GoTrue runner adds that
same lost-ACK flow plus real forged-user/session/metadata/expired/deleted-session
result denial and local-claim cleanup. These signers/checkpoints and master/device
eligibility remain explicit fixtures; this head's Native/GoTrue CI is separate.
