# Real Auth server session lifecycle — existing isolated stack reused

This test-only lane complements the Flutter/Face mock tests. No authentication
product code, provider setup, second-password/primary-password behavior, SMS path,
RLS or production config is changed. New files only. No iPhone is connected.

The existing `platform_auth_gotrue_e2e.mjs` (#1144) owns the pinned CLI2.121.0 local
GoTrue/Kong/PostgreSQL/Edge stack and always cleans up. It is deliberately NOT
copied as a tracked parallel fixture or modified. A new runner checks its exact
SHA256 `79c128c9c03c138084712512ebfcaa1e68cdd5b2641f02cf7c17cc6b99b3e655`,
one setup anchor and required origin/empty-DB/cleanup/assertion contracts. It creates
a private700/600 temporary source copy, adds one local helper import and hook
before app fixture creation, and imports that copy. The original adapter import
is resolved to the same repository-local module. Any drift fails BEFORE stack
setup; every original assertion/cleanup byte remains after removing the hook and
import adaptation (tested). The wrapper temp source is removed in finally.

All SDK keys/tokens/passwords stay in the original fixture's memory; the new hook
uses only its origin-checked request callback. It creates one separate confirmed
`example.invalid` user. No mail is sent. All request routes are the existing local
Auth endpoints, with redirects rejected. No direct network client is added. Hosted
SUPABASE_* credentials/environment are refused. Dependency/image bootstrap on the
GitHub runner still uses package registries; this is not a whole-runner network-none
claim. No hosted project, real credentials or production data is contacted.

## New actual server assertions

1. Password login creates real auth.sessions A. After that first legitimate login,
   capture user/provider identity fields as the stable baseline (not login times).
2. Serialize/rehydrate only the refresh token in MEMORY and call the real refresh
   grant. New JWT remains bound to session A; only one server session exists.
3. A separate password login creates session B for the same fake user.
4. LOCAL signout of A removes A's server row, refuses both its original and rotated
   refresh tokens, and retains B. B's own refresh succeeds with the same B session.
5. Explicit GLOBAL logout of B removes the remaining user sessions and rejects both
   B refresh tokens. This is extra server revocation coverage, NOT app default.
6. Legitimate password login C works and creates a different session. Identity and
   providers stay unchanged. The original master/admin/other fixture sessions stay
   valid. C is locally signed out to leave no extra active test sessions.

The existing entire real Edge/proof/platform suite then executes unchanged, including
original synthetic monitor, session-bound proof and provider/company/master checks.
There is no replacement of server authentication with a biometric boolean.

## Match to the pinned Dart logout behavior

The repository locks supabase2.16.1/gotrue2.27.2. Official gotrue-v2.27.2 source:
`GotrueClient.signOut({SignOutScope scope = SignOutScope.local})` forwards that scope
explicitly to `admin.signOut(accessToken, scope: scope)`, which posts `/logout`
with `scope.name`. Therefore the app's parameterless `.auth.signOut()` maps to the
LOCAL case, even though the admin API's independent optional default is GLOBAL.
The tag source was checked; the pub.dev archive's declared lock SHA was not
independently redownloaded/hash-verified in this lane.

- https://github.com/supabase/supabase-flutter/blob/gotrue-v2.27.2/packages/gotrue/lib/src/gotrue_client.dart
- https://github.com/supabase/supabase-flutter/blob/gotrue-v2.27.2/packages/gotrue/lib/src/gotrue_admin_api.dart
- Current Supabase signout docs checked through search_docs:
  https://supabase.com/docs/guides/auth/signout

## Explicit limits

This proves the HTTP/server half of refresh-token restoration; not a real Dart
process restart, iPhone secure-storage persistence, Face ID hardware, OAuth or app
navigation disposal. The access JWT of a revoked session may remain cryptographically
valid until exp; no immediate old-access-JWT rejection is claimed. Refresh rotation
reuse grace is a separate documented behavior, so immediate pre-logout reuse is
not asserted invalid. Post-logout old refresh chains MUST be refused and cannot
be counted as passing merely because a device forgot its token.

Synthetic user/session/provider rows are isolated and discarded with the existing
fixture. Full production config, original backup/restore and real administrator
retention are outside this test. No new sign-in method or production authorization
is introduced. Record exact CI head and outcome before treating runtime as verified.

## Additional PHONE/password case (separate from successful email snapshot)

The successful email-only baseline remains commit
`e184750df321a24981ca9b960982808f1d325c22` with dedicated CI38939479802 success.
A later test-only commit appends a real phone-password case after EVERY original
email/local/global assertion, in the SAME existing isolated GoTrue runtime. The
original runner source/hash/anchor/setup, product Auth and provider settings are
unchanged. New phone results must be reported against the later exact head.

A fixed fictional NANP555-0100..0199 E164 (`+12025550123`) is admin-created with
`phone_confirm:true` and a freshly generated local test password. It never names an
employee or actual recipient. Confirmed-at is required BEFORE password grant.
The added case permits ONLY admin confirmed-user creation, password grant with
phone, refresh grant and LOCAL logout, with exact allowed body keys. It records
and asserts those six routes; signup/OTP/verify/resend/recover/provider/settings
and any nonlocal/other-phone request are refused BEFORE dispatch. The underlying
original callback still refuses any origin outside its generated loopback API.
No SMS/OTP/provider branch or configuration modification is invoked. Dependency/
container bootstrap remains the original fixture; no whole-host network-none claim.

Actual server assertions require one phone UID/session, refresh retaining its SID,
local logout removing it, both old refresh tokens rejected, stable phone/provider/
confirmation fields and untouched original master/admin/other sessions. The
original app/company/provider invariants and full Edge suite still run afterward.
This is admin-preconfirmed fictional-phone password semantics, not live employee
onboarding, SMS delivery, real provider setup, native persistence or Face hardware.
