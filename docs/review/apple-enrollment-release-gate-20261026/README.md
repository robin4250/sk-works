# Apple enrollment release gate

Baseline: main `112b989978b2f784e66854d12315fec649ecbadf`.

The production manual-link source previously returned `ready` with provider=true, a recently verified OAuth AMR and company membership. Its `begin()` then requested an Apple PKCE identity-link URL. This did not require the operation-bound Google enrollment proof or an Auth-side pre-identity-write policy proven by the existing PR #1420 review. The broker being OFF did not close this separate entry.

The normal `AppleAccountLink` now returns a Japanese preparation state after successful read-only preflight and refuses `begin()` before PKCE storage, URL acquisition or browser launch. Existing server-verified Apple identity display and Google/Face ID login are retained. No provider/Auth setting, identity, company, credential, database or signing operation is changed.

The retained unreleased protocol is exercised only through an explicitly `visibleForTesting` named constructor in synthetic regression fixtures. There is no environment flag, production setup parameter or UI override that releases enrollment. This is a client gate, not a claim that direct Supabase identity linking is globally blocked server-side. A separately reviewed implementation must replace this hold once the Auth-side identity-write protection, same-subject fresh Google proof, actual Apple setup and real-device test are complete.

The existing PR #1420 proof still identifies unsupported PKCE identity commit timing and unproven Google recent-auth acquisition. Neither token refresh nor Face ID alone is substituted for Google reauthentication. No new broker, provider setup or automatic email link is added.

Second-password known-password change and server enforcement remain the previously reviewed candidates. Forgotten-password recovery remains unsupported/preparing; no bearer-only legacy reset fallback is reopened. Actual production enforcement and device confirmation are separate pending stages.

Validation: existing Apple protocol/session/history suite retained in isolated test-only fixtures; added normal-constructor tests prove provider=true + fresh OAuth cannot start linking and already-linked status is still readable; added Japanese non-actionable card regression. Flutter/Dart execution is CI-only.
