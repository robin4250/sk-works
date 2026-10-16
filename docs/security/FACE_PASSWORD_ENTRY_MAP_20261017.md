# Face ID and password recovery entry map

Read-only evidence baseline: `02cab526df266cfede7c991fd9ba162b9b335c7f`.
Issue #273. No authentication, roles, company links, credentials, local preferences
or production configuration were changed to prepare this document. PR #1157 is
on hold; its partial SMS-removal proposal is not primary Face ID recovery.

## The credential being changed matters

| Entry and route | Required existing identity | Device check / secret check | Actual target |
|---|---|---|---|
| App `main.dart` → `app_v2.dart` → `SupabaseAuthGate` → unauthenticated `SecureAuthPage` → 本パスワードを忘れた方 | Logged-out phone account, then SMS OTP session in baseline code | Primary recovery requests SMS, verifies SMS, then updates Auth user password | Primary Supabase Auth password; no Face ID branch in this baseline page |
| Initial employee registration → `EmployeePrimaryPasswordPage` | Existing invited employee session | Initial password entry; onboarding RPC follows Auth password update | Initial primary password; not forgotten-password recovery |
| Protected payroll/site/payment screens → `SecondaryProtectedPage` → 第2パスワードを再設定 → `SecondaryPasswordResetPage` | Already signed-in current user; actor must survive checks and save | Face ID / Touch ID OR verification of login password when server proof is not required | Shared secondary password, via `set_secondary_password` |
| Same secondary-reset page when server capability requires proof | Already signed-in original session | Login password → operation/actor-bound server proof; biometric choice disabled | Same secondary password, via proof-consuming replacement RPC |
| Master entry → `MasterProtectedPage` | Signed-in master admin, trusted device or permitted first bootstrap | Face ID / Touch ID AND `verifySecondaryPassword` | Opens Master screen; does not update either password |
| Master entry → untrusted device → 緊急復旧 → `MasterEmergencyRecoveryPage` | Signed-in master account and configured secondary password | Face ID / Touch ID AND existing secondary password, then two email codes | Registers this device as trusted Master device; does not reset primary or secondary password |
| Initial secondary setup → `SecondaryPasswordSetupPage` | Already signed-in user in initial flow | Optional device biometric check plus new secondary password | Initial secondary password and per-user biometric preference |

The word “Master” does not identify a separate Master password in this code.
`MasterProtectedPage._authenticate` explicitly calls the same
`SecureOnboardingRepository.verifySecondaryPassword` used by secondary protection.
Its field label is 第2パスワード and its button says
Face ID / Touch ID＋第2パスで開く. Therefore resetting the shared secondary password
can change the password subsequently accepted at a Master entry. That is a
concrete code-level explanation for an experience remembered as “Master password
reset”; it is not evidence that the user's previous action actually used this
route or that primary Face ID recovery has been restored.

The Master entry itself has no password-reset navigation button. Its exceptional
navigation is `_openEmergencyRecovery` → `MasterEmergencyRecoveryPage`, whose
completion message is この端末を信頼済みMaster端末として登録しました. Distinguish this
device recovery from the secondary-reset page's 新しい第2パスワード inputs.

## Concrete code evidence

All paths below are in the pinned baseline above. These are source observations,
not proof of the binary currently installed on the iPhone.

* `lib/features/auth/auth_gate.dart`: `_loadState` returns unauthenticated when
  there is no user; `_signOut` calls SDK sign-out and reloads; the unauthenticated
  branch constructs `SecureAuthPage`. There is no separate post-logout Face-login
  selector here.
* `lib/features/auth/secure_onboarding_pages.dart`: `SecureAuthPage` contains the
  primary SMS-reset request/verify/update sequence in the baseline. Its later
  `SecondaryPasswordSetupPage` is a separate signed-in setup component.
* `lib/features/auth/secure_onboarding_repository.dart`: primary password updates
  use Auth `updateUser(UserAttributes(password: ...))`; secondary updates and
  verification use `set_secondary_password` / `verify_secondary_password` RPCs.
  `setEmployeePrimaryPassword` additionally marks the invitation's initial
  password changed. These are different credential stores and purposes.
* `lib/features/auth/secondary_protected_page.dart`: `_resetPassword` pushes
  `SecondaryPasswordResetPage`; its visible action is 第2パスワードを再設定. The page
  is used for payroll settings/review, admin site and payment-certificate settings
  routes and applicable notification targets. Successful reset returns to a
  locked secondary gate and asks for the new secondary password.
* `lib/features/auth/secondary_password_reset_page.dart`: current actor is checked
  before authentication, after authentication and before/after save. The
  biometric prompt says 第2パスワードを再設定するため本人確認します. Capability-driven
  proof enforcement switches to login-password reauthentication; this document
  does not claim production capability activation or successful live execution.
* `lib/features/settings/master_protected_page.dart`: `_load` checks master role,
  device status and whether a secondary password is configured. `_authenticate`
  checks local biometrics, then `verifySecondaryPassword`, and grants only a
  short local unlock. `_openEmergencyRecovery` navigates to device recovery.
* `lib/features/settings/master_emergency_recovery_page.dart`: checks secondary
  configuration, biometrics and `verifySecondaryPassword`, then starts a
  challenge. `_verifyAndRegister` verifies primary/secondary email codes and
  consumes a challenge to register a trusted device. “primary” / “secondary” in
  these code-channel names mean the two recovery email channels, not two password
  resets.

## Already established introduction history

The following evidence was previously retrieved by the root reviewer and saved in
Issue #273 comment `6220748446`; no duplicate history fetch was needed here.

| PR | Recorded merged change | Merge commit | Japan time |
|---|---|---|---|
| #164 | Use phone-only auth with SMS password recovery | `628474ce8aa445c1198426efa7fe67805682fdbc` | 2026-09-21 06:44:15 |
| #176 | Complete SMS password reset immediately after OTP | `ff2d8cb11b4076a3c95e629c357cb08921e35d94` | 2026-09-21 12:30:48 |
| #405 | Complete Master emergency recovery flow | `f16c90f13ad0b2d0c3175e44c23473203f7ae1a8` | 2026-09-30 20:53:32 |
| #556 | Keep Face ID available after secondary password unlock | `8a81f1db8be2b2334539c7694dc4e8c5453cf19f` | 2026-10-03 22:54:50 |
| #872 | Add secondary password reset using Face ID or primary password verification | `13266f8dbf7f2c1cc5ca47fc86a173f23bfd4feb` | 2026-10-10 09:43:11 |

#872's use of “primary password verification” describes one way to authorize
changing the secondary password. It does not say that biometrics reset the primary
Auth password. #556 concerns continued availability at secondary protection, not
logged-out account recovery. No separate older Face-enabled primary-login source
was established by this bounded review; that absence is not an assertion about
every old branch, historical IPA or user's prior device experience.

## Logout and persistence cross-check

`AuthenticatedNavigationBoundary` resets the Navigator subtree and destroys private
page state after identity loss/change. It does not clear SharedPreferences or
modify company membership/roles. Secondary biometrics use
`sko_secondary_biometric_enabled_<userId>`; Master device identity uses
`sko_master_device_key_<userId>`. The reviewed app paths read/write these values,
not remove them on logout. Losing an in-memory “unlocked” flag is expected and
differs from deleting the saved preference or trusted-device registration.

The locked `supabase_flutter` 2.17.2 archive was checked against pubspec.lock SHA256
`26eb3d3b71bcc5651551e64d6b131ba929ea261998570bbcc90356b1b42fd532`.
Its `supabase_auth.dart` signedOut handler calls `removePersistedSession`; its
`local_storage.dart` removes only its configured session key. Default storage key
is `sb-<project>-auth-token`. It does not call a global preferences clear.

The retained `lib/app.dart` is an old local prototype that starts a local HomePage,
not a recovered Face-enabled login flow. Production `main.dart` imports
`app_v2.dart`. Changing that import or reviving the prototype is not a repair.

## Verification boundaries and next evidence

This is static routing/credential/persistence evidence with pinned source and
locked SDK inspection. It does not test real Apple biometrics, actual login,
device keychain, provider recovery, installed IPA provenance or server Auth state.
No saved role/company/login setting was changed. The authorized next test is an
isolated session-driven widget comparison of cold signed-out startup and a real
signedIn→signedOut event; a separate owner is handling that test. User-visible
screenshots/build SHA and observed labels can distinguish the three recovery
targets without guessing or weakening server authentication. Do not merge #1157
as a claim that Face ID primary recovery is complete.
