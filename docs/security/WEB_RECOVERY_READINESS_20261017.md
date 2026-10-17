# Web recovery readiness (2026-10-17)
Read-only baseline c75d1099ab085c828edbc21a666df168de1228ef; branch starts after documentation-only c9fe3dd8b328966686a980d009315b52a7d65761.

No tracked web scaffold or dedicated web preparation existed in the inspected baseline tree. A bounded commit-message search for web returned no results; this does not prove there was never an earlier web implementation.
The candidate generates only a new web directory in a separate clean worktree, with existing web preserved by refusal. Original source, iOS native signing and uncommitted files are untouched. CI compiles standard Flutter main without Supabase defines; no backend connection, secret, deploy, hosting, redirect allowlist or migration is provided.

## Observed blockers
- ExistingGoogleLogin rejects kIsWeb and supported Google entry is iOS-only in baseline (Mac opt-in candidate is separate PR #1178).
- No Apple button in SecureAuthPage; Apple linking/auth work has a different owner. No blind provider shortcut.
- SupabaseBackend initializes the SDK with URL/publishable key, no verified browser origin redirect setup.
- MasterProtectedPage calls local_auth and requires Face ID/Touch ID availability. Browser WebAuthn is not implemented by calling native local_auth; never weaken the gate or treat a JS boolean as server MFA.
- Master device key is per-user shared preferences. Browser storage is resettable and is not hardware identity or biometric attestation.
- Backend repository only supports bootstrap-first-device; normal additional trusted device enrollment is unfinished. Keep existing iPhone registered.
- app_v2 and multiple features import dart:io/native plugins. Compile success alone does not establish runtime compatibility.
- Saved dual-email addresses do not prove delivery or completed dual-code verification.
- Main auth gate can route an unknown account to company setup. Existing owner must return through the original Google identity; do not create another company or reassign identities.

## Completion distinctions
This PR: isolated web compile evidence and preserved source only.
Not completed: browser Google/Apple login, same-user/company/role/data equivalence, session restart/logout/relogin, operation-bound server proof, safe extra-device approval, browser recovery, full business features.
Initial two-step onboarding is a separate staged requirement; do not make every existing login require a new gate or lock out the current iPhone/Master.
No public deployment or production Auth changes are authorized by this readiness candidate.
