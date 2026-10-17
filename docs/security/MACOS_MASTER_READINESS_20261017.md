# MacBook candidate (2026-10-17)
Baseline c75d1099ab085c828edbc21a666df168de1228ef. Existing iPhone/root worktree remains untouched.
Mac native project was absent, and Google entry was iOS-only. Existing SDK PKCE, callback, captured session/membership and actor guards are reused. Mac entrance is compile-gated SKO_MACOS_GOOGLE_V1=false by default. Master dedicated mode stays OFF. No identity linking, account creation implementation, role reassignment, provider config or DB changes.

Preparation: separate clean Git worktree only, no existing macos. SKO_ISOLATED_MAC_PREPARE=1 bash tool/prepare_macos.sh creates a temporary Flutter template and moves only its new macos directory. It never runs flutter create in user source, overwrites iOS, or modifies pubspec/lockfiles. Review generated signing before a signed local Release build. No Debug distribution.

Official requirements reviewed:
- https://github.com/llfbandit/app_links/blob/main/doc/README_macos.md : custom scheme CFBundleURLTypes. Reuse existing com.skworks.sko://login-callback/; no new server allowlist.
- https://docs.flutter.dev/platform-integration/macos/building : Release sandbox needs com.apple.security.network.client; user-selected file entitlement added for existing file picker.
- https://pub.dev/packages/local_auth_darwin/versions/1.6.1 : existing local_auth supports macOS; reuse Touch ID availability checks, do not bypass if unavailable.

CI unsigned build is not same-user login proof, signed distribution approval, Touch ID proof or trusted-device enrollment. Real Google chooser must use the same existing account and compare existing company/role/data without logging IDs/tokens. OAuth wrong/unregistered selection can create an Auth user when server signup permits it: do not claim client membership denial undoes it.
Apple entry, SMS, phone linking and secondary credential changes are out of scope.
Existing backend device_type accepts mac; current repository exposes only bootstrap-first-device, no normal additional device enrollment API. Existing iPhone must remain registered. Do not route routine Mac registration through emergency dual-email recovery. Email contacts saved does not prove delivery/dual-code recovery.
Mobile-only OCR plugin has no macOS implementation; macOS feature invocation behavior requires review before claiming all functions ready.
