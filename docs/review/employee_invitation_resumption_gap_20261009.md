# Employee invitation resumption: existing code boundary

The combined registration screen is implemented, but persistent **send only** for an existing invitation is unfinished. TestFlight distribution URL alone installs the app; it does not authenticate the employee or recover their initial credentials.

## Evidence from the existing code

- `supabase/functions/create-employee-invite/index.ts` generates a random temporary password, creates an Auth user, and returns the password and QR only in that response. A linked worker is rejected with 409. Its QR contains `type`, `inviteId`, `phone`, and `password`; there is no reusable credential-free invitation URL/token.
- `lib/features/auth/employee_invite_scanner_page.dart` requires nonempty phone and password. An invitation UUID alone cannot log in.
- `lib/features/auth/secure_onboarding_repository.dart` calls `signInWithPassword` with phone and password.
- `20260922002000_add_employee_invite_foundation.sql` stores invitation identity, Auth user reference, state, and timestamps, but no original password or login token. Client SELECT is revoked. `employee_onboarding_state()` requires the authenticated employee and cannot be used as an anonymous resume link.
- `EmployeeOnboardingRepository` provides authenticated profile submission and approval operations, not a credential recovery or administrator resend endpoint.

Existing create/QR/approval behavior is preserved. The response can still be shared while it remains in the current screen's memory. No password/QR is persisted. Closing the screen loses that response; fetching the invitation UUID does not recover it. Opening SMS/Share is not delivery evidence.

## Safe current behavior

The exact-company status contract uses approved plus approved_at for completion, with explicit manual-sending history separate from actual delivery. OFF or missing RPC leaves state unavailable. Unknown remains unknown.

Multiple historical invitations for one worker do not establish which one is current: the status RPC lacks a workers.user_id-to-invite.auth_user_id match/current-invite marker. Selecting the latest row, an arbitrary UUID, or any historical approved row would invent current state. The first UI follow-up therefore marked only that worker as ambiguous. The additional current-identity contract below resolves this without selecting an arbitrary historical row. No Auth, role, RLS, registered values, or history is changed.

## Minimum contract needed for complete persistent resumption

A future authoritative endpoint must identify exactly one current invitation through the worker's actual linked Auth identity, then authorize the requesting company administrator and the exact employee. It must reject completed/cancelled/expired invitations appropriately and preserve any already chosen password. It must not return the old password, grant wider roles, or create another Auth user. The employee must prove identity through an explicitly supported recovery/authentication flow; a public invitation UUID or app-install URL is insufficient. Any expiring one-use continuation credential would need a reviewed authentication contract and recipient verification before implementation.

This is a requirement boundary, not implementation or production activation. Under the current instruction to preserve existing Auth and avoid secret reconstruction/new Auth creation, the complete persistent credential-dependent resend cannot be added safely by a UI change. The UI remains Draft until this gap is resolved. Production migration/gate changes, actual external sending, and device verification remain separate.

## Additional exact-current read contract (source only)

`20261009010620_employee_initial_registration_current_identity.sql` adds a new `employee_initial_registration_status_rows_v2` RPC, preserving #807 and its historical rows. It returns a `current_invitation` boolean only when the same company/worker row has non-NULL `workers.user_id = invite.auth_user_id`. It does not return the Auth UUID, password, or token. Current identity is not completion: historical approved records remain in the response, and the client accepts completion only from exactly one marked current record with approved + approved_at + explicit completed=true.

The production read-only metadata inspection confirmed a validated unique constraint/index on invitation auth_user_id, UUID identity columns, and nullable identity values. The addition refuses a missing/non-immediate/non-validated single-column uniqueness constraint or wrong worker identity type. NULL linkage, missing matches, or multiple current markers are unknown; no timestamp-based winner is invented. The UI isolates only the affected worker. All reads still use the #807 exact-company owner/admin and business-eligibility helper and existing OFF rollout gate.

Isolated PGlite validates historical approved/current pending separation, NULL-vs-NULL false, missing linkage, actual identity changes, gate OFF, company/admin/anon ACL, untouched old RPC/history, and uniqueness guard. Dart model tests check both row orders, zero current marker, and multiple current markers. This is source verification only: no production DDL/DML, rollout activation, external delivery, or phone update. Permanent credential-dependent resend is still blocked by the separate authentication contract described above.
