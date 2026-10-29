# Invoice notice unhosted transport candidate (default OFF)

Base main bffd6dc6609fc66d3e67724afdad2b8795f46c9e.
The new invoice-specific Request-to-Response handler connects directly to the
existing private confirmation and scoped immutable-result functions. It creates
no listener and returns null by default; no deployment, public RPC or grants are
added. The production client factory and fixed release flag remain unchanged.

The handler captures one bearer header, rejects cookies and credential/actor
body fields, and validates it with a fixed GoTrue `/auth/v1/user` request without
redirects. Verified user/subject, issuer, role, audience, expiry and SID must
match. In a transaction it sets only this verified JWT context and invokes the
existing private.require_reauthentication_session() gate before the private
notice command/reader. That gate retains account/anonymous/banned/deletion
barrier/user/session conditions and lock ordering; a decoded claim is never its
replacement. PostgreSQL derives the canonical expected-preview hash and compares
it to the operation. No client SQL/function name/issuer is accepted.

Only fixed confirm/result paths and exact fields are accepted. Both explicit
financial and seal confirmations are mandatory. Requests are capped at 64 KiB,
10 seconds for body, 5 seconds for GoTrue, 10 seconds statement and 5 seconds lock
wait. Errors are generic and responses are noncacheable. One confirmation query
is issued; errors never retry it. A COMMIT-ACK failure stays unknown to the
caller. Historical result lookup uses the original actor/SID and full operation.

The dedicated CI reuses exact-hash canonical consent/invoice fixtures in private
temporary source copies, plus the existing disposable local GoTrue runner.
Original canonical files and auth.uid/auth.jwt definitions remain unchanged.
The sensitive require_reauthentication_session body is copied verbatim from
its existing staged source. Existing synthetic application membership/source
proposal/core-integrity and deletion-barrier-key adapters remain explicit
fixture boundaries; this does not prove all production source calculations or
an account-deletion worker race. Actual Auth users/tokens/sessions and actual
financial/seal SQL writes are used. There is no Auth-table mutation by the
application fixture: users/login/logout use GoTrue itself.

The real HTTP fixture drops the confirmation response after the SQL COMMIT,
requires fetch to fail, and uses fresh HTTP result readback to verify one
immutable result and one financial/seal mutation. It rejects foreign users,
wrong hash, a new SID for the same user, and the old SID after actual GoTrue
logout while its JWT has not expired. Missing results never resubmit approval.
The HTTP fixture listener is loopback-only and ephemeral; all local stack
containers and temporary source files are cleaned up. Hosted credentials are
rejected by the inherited isolated runner and are never logged.

Remaining: connect the existing Flutter factory/panel to a reviewed transport
and validated ticket/preview/hash flow, real SDK-to-handler end-to-end proof,
production source/authority adapters and secret/DB-role provisioning review,
public hosting/grant decisions, rollout gates, delivery and iPhone verification.
No production data, original, signature, shared Auth file, migration or release
flag is changed by this increment.
