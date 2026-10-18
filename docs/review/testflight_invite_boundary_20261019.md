# TestFlight initial-registration and company-link boundary review

Baseline: `8711ae5212d7bf1cea238d806f101a87e7392242`. Read-only review,
synthetic tests only. Production data/Auth/RLS/permissions unchanged; no real
employee identities, credentials, SMS, invitation or company-link request used.

## Distribution scope

The owner will first test TestFlight on his own iPhone. No employee, friend or
partner distribution is requested now. The employee invitation E2E gap below is
an expansion gate, **not an automatic block on owner-only upload/testing**.
Do not globally restrict existing owner recovery, Google login, account roles or
all Auth users to implement an employee-invite rule.

## Exact QR path and remaining proof

1. `supabase/functions/create-employee-invite/index.ts` creates a normal GoTrue
   phone/password user (`phone_confirm:true`, app_metadata registration type).
   QR JSON contains `type`, `inviteId`, `phone`, `password`. No invite expiry is
   passed to Auth as a credential expiration or one-time consume contract.
2. `lib/features/auth/employee_invite_scanner_page.dart` validates type and
   nonempty phone/password, then returns only those two credentials. inviteId
   is not used to authorize or consume the invitation. Editing QR inviteId is
   therefore not an independent server authorization decision; password ownership
   is the current login credential.
3. `secure_onboarding_repository.dart::signInWithPhone` calls ordinary
   `auth.signInWithPassword`, as does the normal phone-login path after scanning.
   No invitation consume endpoint is invoked before Auth token issuance.
4. `employee_onboarding_state()` (captured definition in
   `tool/security/onboarding_storage_catalog.json`, original migration
   `20260922002000`) cancels an **invited** row after expiry. `auth_gate.dart`
   renders the invalid-invite page for cancelled state. This protects normal UI
   progression but is after login and is not proof of API/token denial.
5. `20261013210756_guard_employee_invitation_initial_password_expiry.sql`
   rejects `mark_employee_initial_password_changed()` when an **invited** row
   expired, even if the state-read UI was bypassed. Existing profile_pending and
   password_changed rows retain their documented behavior. This is implemented;
   do not reimplement or claim no expiry check exists.
6. `setEmployeePrimaryPassword` performs Auth password update **before** the
   guarded database marker. If the marker rejects, Auth password rollback is
   not part of that database transaction. A UI check alone cannot make the two
   remote systems atomic.

No invite-aware pre-password Auth hook/one-time consumption implementation was
found in this source review. This does not prove the hosted Auth configuration
contains none. Default GoTrue password replay before password replacement,
expired/cancelled QR token issuance, prechange JWT access and hosted hooks must
be measured separately before employee distribution. A local old-JWT result is
not proof of data access to another employee or company.

## Existing boundaries to reuse

* New ordinary employee invitations are intentionally permitted to company
  members: existing employee_invite_page.dart help states this explicitly.
  Do not remove that access based on a review assumption. Requesting manager /
  approver role or issuing guidance for an existing worker requires owner/admin.
* Existing-worker lookup is scoped by worker ID, caller-derived company and
  employee affiliation; linkage PATCH also compares user_id IS NULL. Cleanup
  checks the new Auth ID so it cannot undo a concurrent different owner.
* Invitation metadata table revokes anon/authenticated direct access and enables
  RLS. Approval selects the invitation FOR UPDATE, requires the same-company
  reviewer/assignee, disallows self approval, validates requested viewer/manager,
  and updates worker with both worker ID and company ID. Current deployed
  definitions and actual JWT requests remain separate evidence.
* Company-link migration `20261015005238` defaults each company OFF, uses a
  dedicated owner/admin helper including account restriction, scopes sender and
  recipient actions, locks requests and both companies in stable order, and
  attaches reciprocal directories only after recipient approval. Old bypass
  endpoint becomes a rejection. Existing SQL fixture covers these; no rewrite.
* Referral migration `20261015012003` keeps registration attribution disconnected
  and distinguishes composer-open from delivery/registration. Invitation ID
  alone grants neither account registration nor points. Its SQL fixture uses an
  always-true account helper, so it is not restricted-account/JWT evidence.
* Current main already has capability-based no-photo onboarding and dedicated
  atomic omission RPC calls with no fallback to legacy NULL save. The earlier
  onboarding_storage_review.md photo-required UI observation predates these
  changes; do not repeat its completed UI work. Actual backend availability and
  protected rollout remain distinct.
* Secure reissue/resend is explicitly unfinished in
  `employee_initial_registration_status_contract_20261009.md`; never retrieve
  old temporary passwords or create another Auth user as a retry.

## Verification performed in this worktree

* Existing `tool/company_link_sql_test.cjs`: PASS. Actual migration executes in
  PGlite; manager/restricted admin denied, reciprocal approval/repeat/old bypass,
  ambiguous legacy match atomic rollback and original ACL preserved.
* Existing invite auth_error_logging and persistence_error_logging tests: 2 PASS.
  Mocked HTTP/Node handler tests; not actual GoTrue token or company RLS proof.
* Existing `onboarding_safe_save_check.mjs`: 14 PASS. Exact captured legacy save,
  omission assertion rollback, data/photo/notification sink retention and ACL
  restoration. Not proof of real production notifications or Auth sessions.

## Minimal next experiment; no product changes

`tool/security/employee_invite_qr_gotrue_review.mjs` accepts only a fresh localhost
status file and pinned pg module. It reuses the setup approach from
`platform_auth_gotrue_e2e.mjs` and onboarding HTTP fixtures. Run in a disposable
CI stack created by pinned CLI 2.121.0, no hosted credentials, no product hooks.
It creates one synthetic phone identity with the exact Edge Auth payload,
installs exact captured state and current marker functions, tests expired and
cancelled QR login, valid QR repeat before password change, password-update then
expired-marker denial, old-password denial after replacement, replacement login
and old JWT Auth/Data API observation. No tokens/phone/password/keys/IDs/response
bodies are printed. The fresh stack, including Auth, must be disposed afterward.

The fixture is **NOT RUN against real GoTrue here**: docker and supabase binaries
are unavailable on this host. `node --check` succeeds; that is syntax validation
only. It is a reproducible baseline observation, not a passing security fix.
It intentionally creates no product hook and cannot establish hosted parity.
Reviewers must choose a minimum scoped QR-consumption/expiry design only after
this experiment and hosted hook catalog reconciliation. Preserve ordinary
employee login, old approved accounts, administrator recovery and Google login.

## Dedicated CI candidate

`.github/workflows/employee-invite-qr-observation.yml` reuses the existing
onboarding isolated-stack setup action pinned commit, CLI 2.121.0, Node 24 and
committed fixture dependency lockfile. Docker images/GoTrue version are those
selected by that pinned CLI; no separate image or Auth version is introduced.
The stack excludes outbound-mail and unrelated services. Cleanup stops only the
disposable workdir project, removes its local status/keys on success and fails
the job if cleanup fails. No artifact upload or private log printing is added.
CI success means the **current behavior was measured**, not that replay or
expired-token issuance is secure. Owner-only TestFlight work continues separately.
