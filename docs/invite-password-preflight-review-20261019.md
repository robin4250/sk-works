# Initial password preflight (review candidate)

Base: a7c9647f070c7692813e1c5d69d03b9f11407be8. Owner-only TestFlight build in progress; do not merge or rebuild it for this candidate.

The App now reads the existing employee_onboarding_state RPC immediately before an employee's initial Auth password update. Missing session/invitation, disallowed status, cancelled/expired invitation, malformed/missing invited expiry, or a changed session blocks the Auth update. A still-valid invitation and profile_pending retry keep the existing update → marker order. No new Auth, RLS, grants, migration, Edge endpoint, or production action is introduced.

The RPC itself can mark an expired invite cancelled, as before. This candidate does not make that operation read-only. Ordinary password update methods are unchanged.

## Verification

Thirteen isolated tests use the actual Supabase Dart client with an in-memory HTTP boundary. Eleven rejected cases make no Auth PUT and no marker request. Valid invited and profile_pending flows retain the Auth PUT then marker sequence. Includes no session, null/non-map state, RPC rejection/transport error, and an actual SDK local sign-out while the state response is pending. Existing phone normalization tests also pass (20 combined tests). Synthetic identities only, no network credentials, users, or messages.

## Limits — not a security pass

Preflight and password update remain separate operations. Expiry/cancellation can race after the check; the marker can still fail after Auth changed the password. The client is not an authorization boundary. Do not reverse marker/password order: an Auth failure would then advance registration incorrectly. A server-side solution must bind initial credential lifetime to Auth itself and enforce registration eligibility at sensitive data operations; that needs separate review and isolated testing.

Existing PR1245 isolated GoTrue observation run 39176293798 succeeded at head 5b4d4c9c235e8f4d1e42e8acc50a51592fc37306. It observed hazards, not successful phone-QR verification: phone provider OFF returned 422. Email proxy expired credentials could mint sessions; marker rejected later; a newly updated password survived marker rejection. Old JWT /user rejected while a Data API request still returned cancelled onboarding state. Keep invitation distribution on HOLD pending resolution; the owner's existing account is a separate scope.

UI/help review: no page, navigation, field, feature name, or settings change. Existing password setup page already displays operation errors. New errors explain expiry/reissue and missing eligibility; no separate help entry needs changing.
