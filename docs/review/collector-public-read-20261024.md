# Collector public read RPC: separate review candidate

This new four-file candidate depends on the exact proof-registration candidate `145e9563cd1cabaa43d484d53296ad252a740e9f` (PR1345). It is not part of main, build 12 or a production deployment. It does not reset that proof PR, reconstruct its missing historical sources, add UI, activate a key or turn on any gate.

## Existing permission boundary

The captured read-only production catalog grants authenticated USAGE on the private schema. The exact collector candidate grants authenticated EXECUTE on `private.read_security_collector_events(text)` and revokes anon/service execution. The new review SQL requires those permissions and the exact existing private reader source/attributes/owner. It refuses a missing or different prerequisite and does not grant schema USAGE or alter the private function.

The new `public.master_security_collector_events(p_proof text)` is SECURITY INVOKER, VOLATILE, has an empty search path and delegates only to that fixed private function. No actor, company, operation or scope argument is accepted. There is no SECURITY DEFINER wrapper. PUBLIC/anon/service/bridge-role execution is revoked, authenticated execution is granted, and unexpected ACL entries abort the transaction. The private consumer retains its real actor/master/account checks, gate locks, exact proof consumption and read audit.

Only one new function is installed. Existing tables, gates, schemas, grants, source, stored values and controls are unchanged. The private reader remains from the exact collector SQL SHA256 `b96f6e4365e2e992886f38dad0f777e55665f18b03525cddf4edbdf746348207`; its prosrc MD5 is `a62cc46b5c9fbcee3e38e9699e44bd00`.

## POST and proof privacy

PostgREST runs GET and HEAD requests in read-only transactions even for VOLATILE functions. VOLATILE makes the successful POST transaction read/write, which is required to consume a proof and append its audit. Volatility alone is not a method or URL-logging guarantee.

The RPC therefore explicitly requires `request.method='POST'` before delegation and returns PT405 otherwise. A future client must put the proof in a POST JSON body, never a URL. Rejecting a request cannot undo URL logging if a caller already placed a secret in its URL. The Native fixture uses only a dummy value for GET/HEAD, sanitizes diagnostic routes to their pathname, and never places a real issued proof in a URL or emitted log.

## New isolated proof

The new test runs the already reviewed actual proof-registration sources with local GoTrue-issued JWTs, real Edge execution, PostgREST and PostgreSQL17. All collector reads use the actual new RPC candidate, not the previous fixture-only read bridge. A narrow wrong-scope bridge remains explicitly a negative test fixture only.

The fixture first removes authenticated private-schema USAGE and verifies installation fails without creating the RPC or granting that access. It then explicitly mirrors the captured actual permission and verifies wrapper installation changes no private schema ACL, reader definition, control values, event count or audit count.

Prepared cases include authenticated Master success, original/temporary-session preservation, one-time consumption, different Master actor, different session, scope/target/TTL/revocation/gates, existing NULL-helper guards, anon/service refusal, GET/HEAD refusal, extra argument rejection and malformed/unknown proof rejection without consuming the held valid proof or adding an audit. The original account/provider/company/member/master/device values and default-OFF gates are preserved.

Local Node syntax validation passed. Real Native execution is pending remote CI; prepared cases are not reported as passed. The dependent PR1345 proof succeeded separately and does not substitute for this candidate's test.

## Remaining work

Even a passing public-RPC proof does not supply a client repository/page, Master navigation, production deployment, key provisioning, an actual trusted producer, a honeypot, dynamic defense, operational monitoring or device verification. Production installation must separately bind and compare the actual catalog/roles/gates and preserve financial/account data. No SMS/email/invitation, provider OAuth, hosted credentials or production mutation was used here.

Primary references checked: [PostgREST function calls](https://docs.postgrest.org/en/stable/references/api/functions.html), [transaction access modes](https://docs.postgrest.org/en/stable/references/transactions.html), and Supabase database-function/custom-schema documentation. Existing function authorization is retained rather than treating schema membership as ownership.
