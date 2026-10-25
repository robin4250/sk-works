# Apple identity-link preparation: keep the verified session

Based on main `045169174188262f05b17c38495359e1059ea03b`. Separate follow-up candidate: build15 keeps that exact main; do not merge this while its creation/install is in flight.

The readiness reader already distinguishes provider unavailable/disabled/enabled. That existing feature is reused. Its older review notes are historical, not an instruction to implement it again.

## Repaired boundary

`begin()` verifies an exact JWT and recent OAuth, then awaits company membership, provider settings and the PKCE authorization URL. The old subscription checked only the current UID. A same-UID token replacement could therefore reuse the old verification while the authorization call/browser handoff used a different token. A queued other-user event could also be missed after currentSession had already returned to the original UID.

The candidate pins the original access token until browser handoff and checks it after each awaited preparation boundary. The auth subscription checks the identity in the event itself and permanently revokes an observed replacement before handoff. Old-generation events cannot revoke a newer operation. Refusal leaves the replacement session in place: no logout, login, refresh, password/identity update or account creation is invoked.

After browser handoff, a same-account token update remains supported; existing server-verified UID, Google identity and company/role comparisons still govern completion. This is not a new same-session reauthentication flow, nor proof of an independently bound PKCE/challenge callback. Those remaining Apple enrollment conditions are not removed.

## Verification

Four focused regressions cover same-UID replacement during provider read, replacement while the authorize response is pending, a historical other-UID event delivered after current UID restoration, and legitimate same-account token replacement after browser handoff. They assert no browser launch for revoked preparation and preservation of the current session. Existing Google, Apple readiness/card and account-settings cases are reused through remote CI only.

Static diff validation passed; remote results are pending at creation. No local Flutter/Dart, production Auth/provider/roles/credentials, existing sessions, Edge or business data were changed. No actual Apple identity or signature is fabricated.
