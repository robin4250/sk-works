# Apple native-only continuation — not enabled

Baseline SKO main: `74d4c2f578e26ca1f7f21628f19a1da6b2fdeee9`.
Existing candidate PR #1420 head: `6a282c06726cd299c13ff41a9ceea07d6cf91bd3`.
The current app safety gate from #1429 remains unchanged.

## Current observations and version boundary

Root's read-only hosted settings observation on 2026-10-26 found Apple disabled,
Google enabled, phone disabled, email enabled and anonymous users disabled.
The public health endpoint reported GoTrue `v2.197.0`. No provider identifier,
secret, signing setting or account was read/changed by this continuation.

The official `v2.197.0` tag points to
`4eee58f296d9698a1c2c0ae14d7a0b379c7622d3`. The previous transaction proof used
`c3348e8f1cb31454e9783e4eb9eab1e71ad9652f`, 25 later commits. Changed files include
`internal/api/external.go` and `internal/models/sessions.go`; the older successful
proof cannot simply be relabeled as hosted-version coverage. The new CI runs
the existing transaction cases unchanged against the official hosted-version tag,
plus the new configuration/provider test. A reported version is still not a
cryptographic attestation of the deployed binary or configuration.

## Candidate way to close the PKCE availability boundary

Official Apple guidance supports native-only sign-in without an OAuth client
secret. Both reviewed source versions behave as follows:

- `NewAppleProvider` calls `ValidateOAuth`, which rejects an empty OAuth secret
  before starting OAuth discovery/authorization. Thus a native-only configuration
  must keep the OAuth secret absent; adding one changes that boundary.
- The native `IdTokenGrantParams.getProvider` path checks the enabled Apple
  provider and audience list without requiring the OAuth secret.
- Official Dart `linkIdentityWithIdToken` links a provider identity to the
  authenticated user without initiating PKCE, and rejects an identity already
  linked to a different account. It requires manual linking to be enabled.

The new upstream test uses generated RSA credentials, an in-process allowlisted
discovery/JWKS transport and actual provider verification. It verifies the
no-secret OAuth refusal, native ID-token verification and audience rejection,
disabled-provider refusal and the positive control that supplying a secret opens
the OAuth constructor. It makes no connection to Apple and writes no identity.
It does not prove the full hosted `/authorize` path, enrollment or device login.

The continuation also tests the actual reported-version `/token` native
`link_identity=true` HTTP route with generated Apple RSA credentials, the real
Auth middleware, existing owner-subject hook and disposable PostgreSQL. It
checks a permitted link, absent permit, wrong nonce and wrong original bearer;
the newly issued Apple session is logged out locally while the original session,
UID/email/profile, existing Google identity and a synthetic company snapshot
remain. This company table is a fixture, not the full SKO schema. A passing
test does not supply the still-missing primary-password/enrollment SQL adapters
or prove a real Apple credential or hosted configuration.

This is a candidate configuration boundary, **not permission to enable Apple**.
Before adoption, inspect actual provider settings without disclosing values,
verify that web/manual OAuth remains unavailable on the hosted instance, compose
the existing PostgreSQL hook and run the direct-GoTrue bypass/race matrix against
the actual version. Do not delete or overwrite an existing OAuth configuration
to fit this proposal. Existing Google settings and callback routes are preserved.

## Fresh primary verification remains explicit

The existing Google verifier correctly rejects newly issued tokens with an old
`auth_time`; official Google OIDC does not document a forced-login contract that
would complete this path for a long-lived Google session. It remains unavailable.

Root observed only the boolean that the current account has an Auth primary
password configured. This does not prove that the owner knows it or completed a
fresh verification. A separately reviewed alternative could use the existing
same-UID primary-password verifier with its isolated temporary-session cleanup
and original live-session barriers. That would be a **password-based** fresh
verification, not fresh Google authentication. It must not silently substitute
Face ID, token refresh, email matching or the second attendance password.
No new enrollment/proof/challenge store or protocol is introduced here.

`native_apple_enrollment.mjs` is an OFF internal orchestration candidate with
13 synthetic-port / real-Apple-RSA tests. It requires trusted live-session,
primary-credential-version and exact company/Google context, a same-UID primary
password verifier that has already closed its temporary session, an atomic
service-only subject reservation, native linking and completion adapters.
It discards the new native-link session after scoped local logout and returns
only a linked result, preserving the original Google session. Unknown link
outcomes are held rather than unlinking an identity to pretend rollback.
Those adapters, public endpoint and activation are **not supplied by this core**.
Its internal credential version must never be populated from request JSON or
returned to a client. No interface is treated as a completed enrollment broker.

## Small implemented hardening

The existing read-only Google port now bounds the entire fetch plus response
body with one hard deadline, including a fetch adapter that ignores abort.
Oversized declared/streamed replies, duplicate key IDs and private RSA fields
are rejected, and audience/presenter lists are immutable snapshots. Seven new
Node tests cover those changes. The network origins and GET-only contract stay
fixed; no sign-in, logout, account link, session adoption or profile write is added.

## Remaining setup and completion evidence

1. Owner-confirmed App ID `com.skworks.skWorks` and actual Team ID, native Apple
   capability and matching distribution profile. Do not invent a Team ID or
   regenerate build 20.
2. The hosted native Apple audience, provider/manual-link settings and supported
   native-only behavior; preserve Google and any existing hooks/configuration.
3. A reviewed fresh primary-verification and server enrollment/permit transaction
   that binds verified Apple subject to the original live UID and company.
4. Actual MethodChannel/AppDelegate registration and isolated session adoption,
   with auth-history, cancel/timeout and wrong-UID/company rejection.
5. Current-version Auth race/bypass proof, then separately authorized OFF
   deployment, activation and owner iPhone verification.

None of these are marked complete because code or synthetic CI succeeded.
Phone remains preparation-only without SMS. No Apple/provider change, user/company
ID change, real key creation, Mac operation, build, upload or external delivery
was performed.

Official sources checked 2026-10-26:

- https://supabase.com/docs/guides/auth/social-sign-in/auth-apple
- https://supabase.com/docs/reference/dart/auth-linkidentitywithidtoken
- https://github.com/supabase/auth/tree/4eee58f296d9698a1c2c0ae14d7a0b379c7622d3
- https://github.com/supabase/auth/compare/4eee58f296d9698a1c2c0ae14d7a0b379c7622d3...c3348e8f1cb31454e9783e4eb9eab1e71ad9652f

