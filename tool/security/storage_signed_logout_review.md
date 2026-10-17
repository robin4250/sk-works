# Issued signed URL after actual logout: isolated HTTP follow-up

Baseline: `de0470d616b480d98ee84ec47fb67ee4b5ea036e`. Test-only addition to the existing actual GoTrue/Storage fixture; no product, SQL, production or main changes. Existing checks are retained unchanged. The existing `storage-session-real-http.yml` path trigger and disposable local stack are reused; no new workflow or dependencies.

Before the existing logout, the fixture's self user issues a 15-second signed URL for the same generated PNG. An unauthenticated HTTP GET must return its exact bytes. After the existing actual GoTrue logout and auth.sessions-removal assertion, the identical URL is fetched without Authorization/apikey/cookies, with redirects refused. Both request and response must precede the token's actual exp. HTTP 200 requires exact PNG bytes and is logged as a **LIMITATION**, never immediate-revocation success. Explicit 400/401/403/404 is an observation, not a production guarantee. Service failures or a probe that missed expiry fail the fixture.

After actual signed exp plus 2.5 seconds, the same URL must return explicit denial and must not return protected bytes. Only status/classification is printed. URLs, signed tokens, JWTs and generated credentials remain in memory. The existing fixture enforces loopback endpoints, empty schemas, fixture-only credentials and cleanup. The signed GET additionally checks same origin and refuses redirects.

This short expiry measures local Storage origin behavior, not the app's 600-second expiry duration, hosted CDN behavior, cached/downloaded bytes, immediate revocation, Flutter navigation or production equivalence. Existing session lifecycle, feature-revocation and refresh-chain cases are reused, not reimplemented. No restore/TestFlight completion is claimed.

Local verification: `node --check tool/security/storage_session_http_check.mjs` passes. Docker is unavailable locally; actual Auth/Storage HTTP result is pending the existing dedicated CI. Source presence is not execution evidence.

Official primary sources checked 2026-10-17:
- https://supabase.com/docs/reference/javascript/storage-from-createsignedurl — signed URL validity is specified by expiresIn seconds.
- https://supabase.com/docs/guides/auth/sessions — access JWT/session semantics are separate from refresh-token revocation.
- https://supabase.com/changelog.md was requested; retrieval returned unsupported markdown content-type. No new API is introduced: existing pinned CLI 2.121.0 and existing HTTP issuance are reused.
