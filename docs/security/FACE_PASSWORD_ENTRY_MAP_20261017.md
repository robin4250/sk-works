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


## Additional historical device-install evidence

The root reviewer newly read Issue #273 comments dated 2026-10-10. The following
records strengthen the association with an installed Release build; they do not
identify a credential that the user actually changed.

| Comment | Recorded time (UTC / Japan) | Observed record |
|---|---|---|
| 6091422670 | 2026-10-10 00:08:55Z / 09:08:55 JST | Missing secondary-password reset entry identified; work started by reusing existing device biometrics and set_secondary_password. |
| 6091493824 | 2026-10-10 00:16:29Z / 09:16:29 JST | #872 head 9f22fe2666794ac8db470059775e2d065587b3fa implemented Face ID or primary-password verification as two ways to authorize secondary reset; shared session unchanged and the real credential entered by its owner. |
| 6091899565 | 2026-10-10 00:58:22Z / 09:58:22 JST | #871/#872 all CI successful and main 13266f8d; recorded device checkout tree d097893f matched, 1123 tests passed / 28 skipped; signed Release overwritten onto the existing app and launched. |
| 6091979550 | 2026-10-10 01:06:05Z / 10:06:05 JST | Same version's display was checked; payroll save was not performed in that check. |

These records make merge commit
`13266f8dbf7f2c1cc5ca47fc86a173f23bfd4feb` a traceable candidate for a previously
installed device version, beyond merely finding unused source code. The installed
source included the secondary-reset route introduced by #872 and is consistent
with the primary SMS recovery route continuing separately. However, the records
do not establish that a reset was performed during that device session, which
password was changed, or whether the user later ran another binary. Treat the
installation record and the user's recalled credential-changing action as
separate evidence. No new authentication implementation or SMS-removal proposal
was applied to the device by this documentation update.

 
## Bounded native-layer and earliest-source cross-check

Native review baseline: `7f0c61d94b21cdd0b570819a98b0d8b9788f671d`.
This adds a narrower source check; it does not establish what the user previously
did on an iPhone.

The tracked tree contains no `ios/` or `macos/` Swift/Objective-C/plist/entitlement
implementation to inspect directly. The app's custom iOS native implementation
is generated by `tool/prepare_ios.sh`. At this baseline that script registers
only these custom channel purposes:

| Custom channel | Purpose |
|---|---|
| `sko.multi_pin_map` | Native map pins |
| `sko.notification_settings` | Notification settings |
| `sko.capture_metadata` | Capture/location metadata |
| `sko.invoice_pdf_view/<viewId>` | Native PDF view |

No `SecItem`, `LAContext`, `ASAuthorizationPassword`, Keychain credential
retrieval or Passwords-settings URL implementation was found in that generated
custom native script. Its Face ID usage description describes protection of
important app information. A usage description alone is not credential retrieval
or primary-password recovery.

The repository pins `local_auth` 2.3.0 and `local_auth_darwin` 1.6.1.
The published Darwin archive was read and checked against the lockfile SHA256:

`699873970067a40ef2f2c09b4c72eb1cfef64224ef041b3df9fdc5c4c1f91f49`.

In that exact archive, `LocalAuthPlugin.swift` lines 149–180 allocate an
authentication context, call `LAContext.evaluatePolicy`, and pass its
`success: Bool` / error through `AuthResultDetails`. The reviewed Darwin Sources
and Dart library contain no SecItem/Keychain password retrieval. The result is
device-owner authentication status, not a Supabase Auth password, account-bound
recovery proof or server password-change authorization. The app's current
pubspec and lockfile contain no `flutter_secure_storage` dependency. That absence
is bounded evidence, not proof that every possible historical dependency or
untracked implementation never stored credentials.

Additional earliest-source evidence was separately retrieved by the root reviewer
without repeating a broad history search: PR #115 commit
`82294d41e1943ca6927ddf466d03dfc4932cf5f4`. In that reviewed source, Face ID was
associated with secondary-password registration / unlocking important information.
The reviewed repository file's sole Auth `updateUser` call updated
`companySetupDeferred` metadata, not a primary password. This is a fact about
that specific file/version, not a repository-wide proof of every call site's
absence. Root also confirmed the independent review_auth finding that the old
`AuthRepository` interface/implementation offered no primary-password recovery
capability in the reviewed path. An interface/path finding does not establish
absence from every other implementation, branch, framework or installed binary.

These results leave the user's remembered successful Face ID primary-password
recovery unexplained. They do not reclassify it as a secondary reset. Apple's own
Password AutoFill / Passwords app may use Face ID to unlock a previously saved
password for ordinary login; this native source check neither proves that this
happened nor rules out the OS feature. Access to a saved existing password is
different from resetting the server's password.

Untracked native files on the user's Mac, actual generated device build,
Keychain contents and the installed IPA were not inspected. No real biometric
prompt or credential was used. Native code, application authentication, local
settings, production Auth and data are unchanged. A logged-out local_auth success
must not be substituted for server-authorized primary account recovery.


## 本人追加回答による原因の確定（2026-10-17 JST）

本人が、前回Face IDで本人確認した画面の見出しは **「第2パスワードの再設定」** だったと確認しました。これにより、前回の体験は既知の #872 の画面・対象と一致したことが確定しました。本書の過去の「前回のprimary Face経路は未特定／説明できない」という未確定記録は履歴として残しますが、この本人回答による切り分けが現在の判断として優先します。

原因は、ログイン済みセッション内の第2パスワード再設定と、明示ログアウト後の本パスワード（ログイン用）の「忘れた場合」が、別の資格情報・別経路だったことです。前者のFace ID再設定は `set_secondary_password` を呼び、ログイン用の本パスワードを変更しません。セッションが継続していた間は、後者のログイン画面を経由せずにアプリを使えていました。失われたprimary Face復旧機能を発見・復活したという意味ではありません。

この確認を受けた修正候補は、本パスワードと第2パスワードの違い、端末に保存したログイン用パスワードを確認して通常ログインに戻る案内、この画面からの本パスワード再設定・SMS復旧が利用できないことの明示に限定します。利用不可のprimary SMS復旧入口だけを対象とし、正常な第2Face再設定・Master認証・メール設定・初期登録SMS・従業員QR・電話番号変更SMSは保持します。原因特定前の削除禁止は守られ、以前の候補はHOLDのまま保存されていました。

本人の本パスワードによる再ログイン、実機での最終動作はまだ未確認です。第2パスワードを本パスワードの代わりに使う処理や、新たなFace primary認証方式・匿名パスワード変更権限は追加しません。本番のAuth設定・RLS・役割・会社情報・従業員データの変更は **0** です。候補は全CIと独立レビューまでdraftで保持し、この文書追記自体は本番反映や復旧完了を意味しません。
