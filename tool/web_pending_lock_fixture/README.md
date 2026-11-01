# Local two-tab personal-save fixture

Build with the repository-pinned Flutter SDK:

```sh
flutter build web --no-pub --target tool/web_pending_lock_fixture/two_tab.dart
```

Serve build/web on one localhost origin, then open two tabs at that exact origin. Do not supply backend definitions or use a real account. The fixture uses synthetic identities, mock HTTP and the real browser preferences/Locks API. main.dart supplies the shared synthetic helpers; its standalone automatic entrypoint is not the target qualified here.

Use Hold in tab A, Contend in tab B, then release A and acquire from B. Seed an unknown result in A and confirm B refuses a save. Seed a foreign-session pending operation and confirm B keeps it. The unavailable-manager control is fault injection only and restores the manager after checking that no body entered. Remove the exact synthetic key with the fixture cleanup control after releasing locks.

The recorded qualification covers four bounded browser groups and four native regressions. Tab close/crash, metadata mismatch after a response, a genuinely unsupported browser, non-cooperating old clients and cross-device/server enforcement remain separate checks. No production connection, account, invitation or financial record is used.
