# First-use authentication candidate — 2026-10-17

## Scope and rollout

Staged policy only. SKO_FIRST_USE_AUTH_V1 defaults OFF; AuthGate is unchanged.
No server endpoint, RLS, Auth provider, account or production setting is modified.
This candidate does not make the app or REST API enforce MFA.

The user's requirement applies before initial app use. It does not require two
physical devices or two repeated prompts on each restart/login. Normal sessions
remain persistent. Existing Master, amount and important-operation gates remain
unchanged.

## Existing implementation and history

At c75d1099ab085c828edbc21a666df168de1228ef, AuthGate checks employee onboarding,
company membership and the admin setup guide, then opens Home. Existing Google
return verifies existing membership and returns to that gate.

82294d41e1943ca6927ddf466d03dfc4932cf5f4 (#115) added the secondary-password
setup gate. 2269206aacc013df0caa23dc8840be75e1c5ca4d (#219) intentionally removed
that universal gate for role-specific secondary authentication.
SecondaryPasswordSetupPage remains, with optional Face/Touch and a local
SharedPreferences flag. Reconnecting it wholesale would neither prove server MFA
nor safely preserve existing users.

## Future boundary contract

A server-authenticated read must derive the actor from a validated JWT and verify
the live session. It returns account-level first-use state, correlated with the
request's actor and session. States are needsSetup, completed, unavailable.
The client must not supply an actor, role, company or completion boolean as
authority. user_metadata and SharedPreferences are not authority.

A future completion operation needs verified primary identity and an independent
server-verifiable additional factor. Any challenge must be short-lived, single
use and bound to actor, session, operation, target and request identity. Concurrent
completion, timeout/unknown result and status lookup require idempotent receipts.
This policy implements none of that server write and never generates proof.

local_auth Face ID/Touch ID success is a local OS result. It is not a signed
server assertion, Supabase AAL2, an OAuth login or a REST authorization grant.
A passkey/WebAuthn or another approved independent server-verifiable factor
requires a separate design and implementation. A device key alone is not proof
of current human presence. Registration of two login providers is not
automatically two independent factors.

After server-confirmed account completion, another valid session reads the same
completion rather than reissuing initial setup. Session/device checks during
normal login are continuity checks; they must not be advertised as fresh two
factor authentication. Loss of local preferences cannot recreate/erase a server
completion record. Unknown state waits for retry, not automatic setup/reset.

## Existing proof reuse limits

tool/staged/reauthentication_proofs.sql already models a 120-second, single-use,
actor/session/operation/target-bound proof. Its operations do not include
first-use completion. The Edge reauthenticate-operation verifier uses a primary
password grant, so it cannot simply be reused for an OAuth-only account without
an existing password. No primary password is silently created for Google/Apple
users. Existing Google UID/company/roles and all data must remain intact.

## Work remaining before activation

- Implement and test server completion/read APIs and independent factor proof.
- Provide an accessible verified alternative for devices without biometrics.
- Restore verified Apple/email routes and safe same-UID linking separately.
- Keep paid SMS disabled; never auto-confirm a phone to bypass ownership.
- Define legacy-user enrollment without lockout; do not infer newness from
  missing local preferences or missing company membership.
- Validate OAuth-only users, recovery and late logout/session races end to end.
- Review native Mac/iPhone UX and server API/RLS enforcement separately.
- Protected backup, restore, admin preservation and explicit production approval.

The current behavior tests cover policy decisions and response correlation only,
not real Auth, biometric hardware, server factor verification or API denial.
