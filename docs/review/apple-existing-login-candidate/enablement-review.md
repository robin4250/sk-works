# Apple enablement: source-backed boundary and concrete setup

This is a review candidate, not deployed capability. No portal, Mac, production database, Auth provider or signing operation has been performed.

## Supported Auth-side policy

Pinned upstream: [supabase/auth c3348e8f1cb31454e9783e4eb9eab1e71ad9652f](https://github.com/supabase/auth/tree/c3348e8f1cb31454e9783e4eb9eab1e71ad9652f), committed 2026-10-21. The production Auth version has not been identified, so upstream proof alone does not authorize activation.

- `internal/api/token_oidc.go:332` and `internal/api/external.go:216`: account creation/linking and token issuance share an enclosing database transaction.
- `internal/tokens/service.go:887,944`: session creation and `GenerateAccessToken` run within that transaction.
- `internal/tokens/service.go:735`: the Custom Access Token hook receives the transaction connection; an error returns up the stack.
- `internal/hooks/hookspgfunc/hookspgfunc.go:106`: the PostgreSQL hook uses that connection rather than an independent connection. Therefore it sees newly inserted identities and can abort the entire exchange.
- `internal/api/hooks.go:76`: Before User Created makes its own earlier linking decision and skips non-CreateAccount decisions. It does not protect automatic linking or the later decision race.

Official supported hook: [Custom Access Token](https://supabase.com/docs/guides/auth/auth-hooks/custom-access-token-hook). We do not add a trigger/constraint to managed `auth.identities`, modify GoTrue source behavior, or assume an HTTP hook can see uncommitted data. The test adds only an isolated test file to the pinned upstream checkout.

The candidate PostgreSQL hook keeps original claims unchanged. Default OFF/no rows, private explicit owner UID protection and Apple subject permits, no client enrollment RPC. For a protected UID, any Apple identity must have an exact server-verified subject permit for that UID. A reserved subject on any other UID fails. Thus an unapproved same-email link, reserved-subject re-creation after concurrent unlink, or cross-UID link fails before transaction commit. Nonprotected/unreserved users retain their existing signup policy; this is not a global signup change. Google identities, company rows and profile fields are never edited by the policy.

Enrollment remains deliberately unimplemented until a same-session Google operation-proof broker exists. Never populate permits from email, user_metadata, a client-selected UID, a pasted subject, or a new Apple-only session. Safe enrollment must verify the current exact Google session and membership, freshly authenticate that same Google subject with an operation-bound nonce without replacing the live session, verify Apple's signature/issuer/audience/nonce, and bind the verified Apple subject to that already existing UID. Before enabling, explicitly snapshot/approve any already linked owner Apple identity and compose with any existing Custom Access Token hook rather than replacing it.

The GoTrue test proves the source transaction path after verified provider data is supplied; it does not fake Apple signatures or claim a real Apple OAuth exchange. It checks rollback of users, identities and sessions plus unchanged Google identity ownership. Actual production-version equivalence, manual-link callback path, company preservation, existing-hook composition, blocked/deleted-account policy and concurrent enrollment/disable behavior require further validation before rollout. Existing broker rollout must remain OFF.

## Existing Flutter flow and native preparation

For adding Apple, retain `AppleAccountLink.readiness → begin → verifyCompletion` and its current exact-token/getUser/recent-OAuth/company/Google-identity checks. It already launches the pinned Apple OAuth URL and uses `com.skworks.sko://login-callback/`. PR #1418 fixes historical session/token switching. A long-lived Google session must first obtain the missing operation-bound Google proof; refreshing a token or using Face ID alone cannot substitute for it.

For returning Apple login, `native_AppleCredentialSource.swift.review-only` supplies a real AuthenticationServices request with independent secure nonce/state, SHA256 nonce challenge, no profile-name overwrite and no auth mutation. The caller must retain it and present from the active UIWindow. Native compile-only CI needs no provisioning profile or signing key. It is not registered in AppDelegate or Flutter and does not acquire real credentials in CI.

After server safety is proven: expose the source through one MethodChannel, send only ID token/raw nonce to the approved registered-login broker, and use an isolated nonpersistent Supabase client to validate the returned session/user/company before adopting into the live client. Capture live-session history for the whole attempt; any A→B→A change aborts adoption. No fallback to plain `signInWithIdToken` / email lookup / signup. Cancel/error leaves the current Google session intact. Add focused Flutter tests and a real-device Apple test before opening the UI gate. No sign_in_with_apple dependency or prepare_ios/signing change is made in this candidate.

## External setup to review concretely

Reference: [Supabase Apple guide](https://supabase.com/docs/guides/auth/social-sign-in/auth-apple), checked 2026-10-25.

1. Read the existing signed app's actual Bundle ID and Team ID. Preserve them. In Apple Developer Identifiers, enable Sign in with Apple for that existing App ID; regenerate the matching distribution provisioning profile only when authorized. The candidate does not invent a new app identifier.
2. For existing OAuth-based manual linking, use a Services ID associated with that App ID, website domain `ztktgquxvcxcjxtluspu.supabase.co`, return URL `https://ztktgquxvcxcjxtluspu.supabase.co/auth/v1/callback`. This HTTPS Apple return URL differs from the app callback scheme.
3. In Supabase Authentication → Providers → Apple, verify enabled state and Client IDs. With both web/manual OAuth and native enabled, the Services ID must be first, with the actual native App ID also listed as an accepted audience. Do not guess IDs or overwrite existing entries.
4. For OAuth only, securely configure Team ID/Key ID/private signing key/client secret using the portal's protected settings. Track the secret's expiry (Apple maximum six months) and rotation ownership. Native-only ID-token verification does not require that OAuth secret, but the existing manual-link OAuth route does. Do not paste key material into chat, repository, logs or CI artifacts.
5. Verify Supabase manual linking is enabled and URL Configuration permits the existing exact `com.skworks.sko://login-callback/` callback. Preserve current Google callback/provider entries.
6. Verify the deployed GoTrue build and any current access-token hook. Run equivalent isolated policy proof for that version, review policy composition and enrollment, then separately authorize/install the OFF policy and server candidate. Do not enable Apple login based only on provider=true or an available iOS entitlement.
7. Add the Sign in with Apple entitlement `com.apple.developer.applesignin = [Default]` to the existing app target only after matching App ID/profile capability is verified. Release build remains a separate operation using the next authorized build number; existing candidates must not be rebuilt or renumbered for this preparation.

Phone remains 準備中 without SMS. No existing user/company ID or payroll/signature data should be regenerated to make Apple testing succeed.
