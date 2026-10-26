# Google primary verification: OFF internal port

The verifier and read-only network adapters are implemented and tested; a usable Google primary broker is NOT complete. This module is not a public broker endpoint and issues no operation proof or login session. The existing `sko-reauthentication-v1` protocol remains the only proposed operation-proof protocol. `reauthenticate-operation`, its SQL proof table, and its generic Flutter repository are not edited here.

`verifyGooglePrimary({exactBearer,challengeId,idToken}, ports)` returns internal server evidence only. No boolean or evidence supplied by a client may authorize an operation.

| Port | Required trusted-server contract |
| --- | --- |
| `enabled` | Explicit server rollout flag; false performs no network/auth/challenge operation. |
| `authenticateExactBearer(token)` | Validate this exact JWT with GoTrue `getUser`, then decode its authenticated `sub`, `role`, `session_id`, `exp`; return `{user,claims}`. Preserve the caller's current session. |
| `loadChallenge(id)` | Read a server-generated, operation-bound record: `actor_id`, `session_id`, `operation`, exact `target`, unpredictable unique `nonce`, integer `issued_at`/`expires_at` (at most 120 seconds), consumed status. Never derive it from request JSON. |
| `resolveGoogleKey(kid)` | Bounded, cached HTTPS Google JWKS at `https://www.googleapis.com/oauth2/v3/certs`; reject redirects/oversized replies/private keys. No token-selected URL or client key. |
| `audiences`, `authorizedPresenters` | Exact server-configured Google client-ID allowlists. The optional token `azp` must match the presenter allowlist. Preserve existing configured Google clients. |
| `consumeChallenge(binding)` | Atomically match challenge ID, actor, SID, operation, exact target, nonce, issuance/expiry and token hash; require unconsumed/unexpired record and live original session plus existing deletion/access barrier; consume once. Only a real server adapter may return true. |

The verifier checks Google's real RS256 signature, issuer, subject, audience/presenter, nonce, expiry, issuance and **recent auth_time at or after challenge creation** (5-second clock tolerance). A new `iat` for an old Google SSO session is rejected. Google `sub` must match a Google identity returned by the original exact bearer. Email is never used to identify or link an account. The same exact bearer and Google identities are checked again before consumption. The existing proof issuer must still independently validate the live actor/session/operation/target and return the same 120-second one-use proof format after successful internal verification.

There is deliberately no challenge storage or issuance RPC in this candidate. The security workstream owns a reviewed extension of the existing staged proof path; it must supply the challenge issue/consume adapter without weakening ordinary proof consumers or creating challenge/proof nonce collisions. Until it exists, this verifier remains unavailable rather than accepting a client-generated nonce as proof.

`google_primary_ports.mjs` supplies the fixed-origin GoTrue exact-bearer validation and fixed Google JWKS adapters, with response limits, timeouts, no redirects and no auth mutation. It remains OFF unless trusted challenge adapters are supplied. The verifier does not observe client A→B→A history; the eventual Flutter operation must guard that history for the entire acquisition/proof flow.

The Google credential-acquisition route is also not enabled. The current Google Flutter plugin initializes its nonce once; blindly reusing that nonce is unsuitable for per-operation challenges. A reviewed acquisition adapter must request the challenge nonce and `auth_time` claim, and the configured Google client must actually support returning that claim. Missing/old `auth_time` fails closed. Current official Google OIDC reference lists only `none`, `consent`, `select_account` prompt values; neither `prompt=login` nor `max_age` has a documented supported contract there. Requesting `auth_time` reports the existing Google-session authentication time and does not force new authentication. Therefore this candidate cannot guarantee fresh reauthentication for a long-lived Google session, cannot be called a completed broker, and must remain unavailable until a supported acquisition method is actually proven. Do not call Supabase Google sign-in to obtain this verification token, replace the live session, auto-link by email, or treat Face ID/token refresh as Google reauthentication.

Sources checked 2026-10-25:

- [Google OIDC reference](https://developers.google.com/identity/openid-connect/reference): immutable `sub`, audience/presenter, nonce and requested `auth_time` semantics.
- [Google security bundle](https://developers.google.com/identity/siwg/security-bundle): Google-session authentication and application ID-token issuance are distinct moments.
- [Google OIDC flow](https://developers.google.com/identity/openid-connect/openid-connect): Google client and redirect configuration; request `auth_time` via the essential ID-token claim.
- [Official Flutter Google plugin source](https://github.com/flutter/packages/blob/main/packages/google_sign_in/google_sign_in/lib/google_sign_in.dart): nonce is an `initialize` parameter and initialization is once per instance.

Validation uses real generated RSA signatures and synthetic exact-actor/challenge adapters, including same-email wrong subject, stale auth_time, nonce/audience/presenter tampering, replay, disabled capability and server identity/session changes. This does not prove a live Google challenge or a production proof issuance.

## Apple Flutter/native connection boundary

`lib/features/auth/apple_native_credential_preparation.dart` is compiled and tested through dedicated CI only. Default OFF; unsupported devices or missing native registration show a Japanese 準備中/error. No new button, AuthGate route, AppDelegate registration, entitlement or provider setting is added. It verifies the existing Google actor through `getUser(exactToken)`, listens to historical auth events, and invokes only `com.skworks.sko/apple_credential → requestAppleCredential` with no arguments. The response must contain exactly `id_token` and `nonce`; any A→B→A actor or token switch invalidates the result. It performs no sign-in, identity linking, profile update, proof issuance or session adoption.

The prepared Swift `SKOAppleCredentialSource.request` supplies matching native ID token/raw nonce. A future reviewed AppDelegate bridge must map its successful value to `{id_token: value.idToken, nonce: value.rawNonce}` and map cancelled/unavailable errors to `PlatformException`; retain the native source until completion and use the active UIWindow. That bridge stays disconnected until the PKCE identity-write policy, Google proof/enrollment adapter and actual Apple capability are proven. Never enable the compile flag alone or make the control appear usable while server/native/provider gates remain missing.
