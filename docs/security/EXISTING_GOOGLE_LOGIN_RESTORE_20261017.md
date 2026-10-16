# Existing Google login client restoration candidate

Base main: 0a7276347a7dcaaa3a70b09c5bbae69fcaf2f7cb. Separate branch; PR1157 remains saved and unmerged. No database, role, account, provider, redirect configuration or production data changes.

## Evidence and scope

The owner confirmed the earlier Face ID heading was **第2パスワードの再設定**, matching existing #872 signed-in secondary reset; that operation never changed the primary login password. Root's read-only aggregate found the existing master linked to Google, with no phone/password credential and an intact company owner membership. No personal identifiers were copied here.

Root viewed owner-provided screenshots: Google ENABLED; Site URL `http://localhost:3000`; one existing redirect URL, exactly `com.skworks.sko://login-callback/`. This is screenshot evidence, not a successful root browser login. Existing Google provider identity is the mechanism for returning to the same UID. The client neither links identities nor creates a company or grants a role.

This native candidate adds the existing Google provider entry to the current SecureAuthPage. It uses the pinned SDK's existing PKCE/session/deep-link handling. Browser launch success does not call the application's authenticated callback. The action-scoped signedIn listener requires a real current session, checks an existing company_members row with a captured bearer, then rechecks actor/token, active route, lifecycle and generation. A background result waits for foreground. Cancellation/disposal ignore stale UI results; phone/SMS registration, employee QR, normal phone login, secondary Face and Master remain unchanged. Existing primary SMS recovery is unchanged in this branch; the separate SMS-only candidate is not merged.

prepare_ios appends `com.skworks.sko` to CFBundleURLTypes only when absent, preserving existing dictionaries/schemes. Malformed URLTypes fail before plist write. Bundle ID remains `com.skworks.skWorks`; signature/team/entitlements untouched. Native web callback is not supported by this candidate; no web provider settings are added.

## Limits requiring review / device verification

OAuth may create an Auth user if a different, previously unregistered Google account is chosen and server signups permit it. `prompt=select_account` is only a selection aid, not a UID restriction. The existing-company read refuses application completion for unknown membership, but does not undo server user creation. UI cancellation stops the page action, not the external provider or SDK's global callback/session persistence; close the external authentication page too. Never claim signup prevention or server cancellation from these UI checks. Real server authentication tests are isolated; the owner must use the existing Google account for device verification. No real Google login has been performed by this implementation.

Tests: synthetic client fixtures only, fixed `.invalid` host and public_fixture key. Widget event adapter exercises pending/cancel/background/late actor/unknown membership; an actual pinned SDK client checks membership URL/user filter/captured bearer/no signup or update writes. Python executes the exact prepare_ios callback block on synthetic plists, checks existing entries, repeat idempotency and malformed refusal. These are not native biometric, iPhone OS-return or signed Release/TestFlight success. Full Flutter/iOS CI and independent review must succeed before integration; generated Runner and final signed Release.app callback registration require native verification.
