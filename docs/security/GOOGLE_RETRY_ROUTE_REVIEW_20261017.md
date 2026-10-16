# Google retry and route-return follow-up

Base main7ab795f3b2da14dd09fd4a6fc72897ec15f84ed5. PR1163 Google login was installed as signed Release; the owner corrected the initial failure report to **できた**. This is an owner-reported login success, not independent confirmation of the same UID, owner role or employee records. No failure workaround is introduced here.

## Minimal candidate implemented

SecureAuthPage now observes its own ModalRoute dependency. If the route becomes current again without an OS resumed event, a post-frame check resumes the existing pending Google membership verification. Existing generation, actor/token, mounted, foreground, route and membership guards remain. No global RouteObserver/AuthGate changes or unconditional auth-state completion. A synthetic widget test covers actual Navigator push/pop with unchanged resumed lifecycle, one fresh membership check and one completion.

Existing-current-session and membership-error text no longer suggests that restarting clears authentication. This is explanatory UI only; unknown membership retry is not completed by this candidate.

## Explicit logout remains HOLD

Pinned gotrue2.27.2 signOut captures the target token and synchronously clears memory, then awaits PKCE storage removal before emitting signedOut and requesting server logout for that captured token. A concurrent new actor can enter during that await. A dedicated synthetic actual-SDK diagnostic injects delayed GotrueAsyncStorage to inspect target A server logout, later B memory, and a late signedOut event carrying B. This is SDK observation, not product permission to add a new logout helper. The Flutter2.17.2 persistence handler prioritizes a non-null event session, so deletion of B's persisted session is **not** established by this source; do not claim such an accident occurred.

Pinned supabase2.16.1 `_handleTokenChanged(signedOut)` also calls realtime.setAuth(publicKey), regardless of the event session. The diagnostic does not claim actual Realtime channel safety. Global SDK listener and PKCE verifier effects still need proof before promising another actor cannot be disrupted. No new product signOut button, storage clearing or auth-core patch is included. No real accounts, production endpoints, roles, identity linking, signup or password updates are used by the diagnostic (.invalid host/MockClient only).

## Priorities retained

1. Route-only pending return: implemented candidate, tests/CI pending.
2. Unknown Google session retry: explicit logout UI HOLD until full SDK race safety is established; existing SDK session is not revoked by UI cancel or restart.
3. Google-only Master server step-up: primary password is absent; retain existing proof requirements and default-OFF staged feature policy. No primary-password creation, anonymous Face reset, secondary-password substitution, server proof fallback or new OAuth proof scheme.
4. PR1157 saved/HOLD and primary-versus-secondary guidance: separate candidate; no primary SMS, secondary Face, Master, dual-email, registration or employee QR deletion in this branch.

Apple history belongs to the separate read-only lane. Native scheme/entitlements/Bundle ID and production database/Auth/provider/ID/role/company settings are untouched. Existing company/admin/employee preservation after owner login remains a separate confirmation item.
