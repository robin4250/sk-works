# Existing account identity linking: preparation only

This candidate adds synthetic pinned-SDK tests, not a product linking UI/controller or a server feature. Current Google login and existing IDs, company membership, roles, secondary-password Face verification and dual-email recovery remain unchanged. No production requests or setting changes are made.

## Server and SDK boundaries

Pinned supabase_flutter 2.17.2 / gotrue 2.27.2 provide authenticated `linkIdentity` via `/user/identities/authorize`, PKCE and the current JWT. Browser launch or receiving an authorization URL is not successful linking. Manual linking must already be enabled server-side and the Apple provider and callback must be verified before enabling an app entry. Those production conditions are currently unconfirmed. Never substitute anonymous Apple sign-in, signup, email/name matching, UID reassignment or role promotion.

`updateUser(UserAttributes(phone/password))` is authenticated PUT `/user`, not creation of another user. Adding a phone requires phone-change ownership verification, normally SMS and `verifyOTP(type: phoneChange)`. Paid SMS is prohibited by the user. There is currently no approved replacement phone-ownership channel, so phone-login linking remains blocked. Contact phone data, Google/Apple login and local Face authentication do not prove telephone ownership. Admin auto-confirm, service-role updates and disabling verification are forbidden substitutes.

Password updates support `nonce` and `currentPassword`, but server enforcement depends on settings. Secure password change can exempt sessions created within 24 hours; therefore a current session is not proof of fresh reauthentication for this operation. `reauthenticate()` sends a nonce to a confirmed email, or confirmed phone if no confirmed email. Existing Google-only master has no primary password; existing password-only server step-up cannot be silently weakened or satisfied with the secondary password/local Face. Do not create recovery email registrations without authorization.

## Required action contract before a product implementation

1. Start from an authenticated, server-validated existing user. Capture UID, session/token and operation generation; server-read original identities and company/role snapshot.
2. Require approved server reauthentication bound to actor, operation and short expiry. Exact capability for Google-only users is still a gap; no local boolean substitute.
3. Call authenticated `linkIdentity(apple)` only when provider/manual-linking readiness is verified. Reuse exact allowed callback `com.skworks.sko://login-callback/` and PKCE. Never treat launch as completion.
4. On callback, server `getUser` must show the original UID, original identities retained and Apple identity added. Recheck company/role snapshot through existing authorized reads. Actor/session/generation changes, cancellation and late results must not produce UI success or modify another user's session.
5. Verify same linked Apple login separately in isolation before permitting real use. Do not test unlinked/wrong Apple in production: normal OAuth can create another user. Client cancellation cannot undo SDK global callback storage or server-side linking.

| Scenario | Required outcome | Current evidence |
|---|---|---|
| Current JWT / PKCE / exact callback | Authenticated identity-authorize, no signup | Pinned SDK HTTP fixture in this candidate |
| Authorization URL obtained | Not linked success | Fixture leaves original Google-only user unchanged |
| Existing identity collision | Fail; no unlink/update/signup fallback | Synthetic server-error fixture |
| Actor B arrives after capture A | Reject late A result; never log out B | SDK fixture demonstrates captured getUser does not pin global actor |
| Cancel/background/late callback | UI success 0; server rollback not promised | Required design, no new product controller implemented |
| Same UID + original Google + added Apple | Verify using real isolated server OAuth fixture | Pending; HTTP fixtures do not prove server linking |
| Company/master/admin preservation | Authorized before/after comparison | Required matrix; not production verified |
| Phone ownership without paid SMS | Must have legitimate verification | Unresolved; phone auth linking disabled/not implemented |
| Google-only server reauthentication | Fresh operation-bound proof | Unresolved; existing proof remains unchanged |

## Sources

- https://github.com/supabase/supabase-flutter/blob/gotrue-v2.27.2/packages/gotrue/lib/src/gotrue_client.dart (`getLinkIdentityUrl`, `getUser`, `updateUser`, `reauthenticate`)
- https://github.com/supabase/supabase-flutter/blob/gotrue-v2.27.2/packages/gotrue/lib/src/types/user_attributes.dart
- https://supabase.com/docs/guides/auth/auth-identity-linking
- https://supabase.com/docs/guides/auth/phone-login
- https://supabase.com/docs/guides/auth/password-security

Only synthetic `.invalid` endpoints and users appear in tests. They are actual pinned SDK calls with mocked HTTP, not real Apple/Google authorization, live Supabase server enforcement, native Face or iPhone verification. CI results must be recorded separately after execution.
