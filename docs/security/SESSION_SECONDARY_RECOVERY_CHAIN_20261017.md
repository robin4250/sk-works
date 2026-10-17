# Existing session / secondary Face reset synthetic integration

Scope: three new files only (test, dedicated workflow, this document), based on main 02cab526df266cfede7c991fd9ba162b9b335c7f. No product code, AuthGate/Main logic, SMS path, authentication settings, database, roles, contacts or production data are modified. PR1157 remains a separate held deletion comparison candidate, not this branch's base.

The test uses the repository lockfile and Flutter3.47.5, actual `Supabase.initialize` and the SDK's standard SharedPreferencesLocalStorage, actual `SupabaseAuthGate`, SecureAuthPage, SecondaryProtectedPage and DeviceSecondaryPasswordResetAccess. Only HTTP and the native local_auth platform responses are synthetic. It does not substitute a fake reset access or implement a new auth scheme.

The already-initialized SDK branch is present in the pinned supabase_flutter2.17.2 source (`lib/src/supabase.dart`): initialize returns the existing instance before changing configuration. The test first initializes the synthetic HTTP client, then calls the existing SupabaseBackend.initializeIfConfigured with exact compile-time synthetic URL/key, asserting the client identity remains unchanged. No private flags are edited or reflected. Workflow and test both fix/check `https://session-fixture.invalid` and `public_fixture`; no secret or real Supabase project is used. Every HTTP request must target that synthetic host, and unknown endpoints fail.

| Sequence | Assertions |
| --- | --- |
| Initial password login | Actual SDK receives a synthetic password response; the standard storage key receives its session. |
| SDK disposal/recreation | Stored session and per-user biometric preference survive. An unexpired session restores with the same user/token and no extra password/OTP request. This simulates SDK restart; it is not OS process-kill or iPhone evidence. |
| Existing authenticated gate | The actual gate displays the synthetic home without showing the unauthenticated forgotten-password action. |
| Explicit logout through gate | Actual logout endpoint once, in-memory session absent, persisted session key removed, biometric preference still true. Existing login/forgotten-password entry appears; SMS recovery is not exercised or removed. |
| Logged-out reset access | Actual access cannot load authenticated requirements or send a secondary password mutation. |
| Ordinary login again | The existing login screen uses password grant, not OTP. |
| Existing protected reset entry | SecondaryProtectedPage's existing reset button opens SecondaryPasswordResetPage. The capability fixture explicitly represents the default-OFF existing secondary reset contract. |
| Native Face result | Only platform response is mocked. Existing Device access performs authentication and writes exactly `set_secondary_password` with the new synthetic secondary password and authenticated bearer. |
| Correct password target | No primary `/auth/v1/user` update, `/auth/v1/otp`, or Master recovery call is allowed; the primary password is used only in the two ordinary password-login requests. |
| Cancelled Face result | No replacement fields appear and the write count cannot increase. |

This does not identify which password the user reset in their prior installed build. It demonstrates an existing source sequence compatible with retained-session behavior while distinguishing the known secondary reset target. Real device Face ID, OS persistence/disk durability, secure hardware, production RLS and account recovery remain unverified. No fabricated local biometric-to-anonymous primary reset is added.

Validation: dedicated workflow result and exact tested SHA must be recorded separately after execution; source existence alone is not success. The default-OFF capability is a synthetic test input, not a claim that production flags were changed.

The integration case is enabled by `SKO_SESSION_CHAIN_FIXTURE=true` only in the dedicated workflow. Generic app CI skips that explicitly named case because it does not supply this synthetic configuration; the dedicated enabled path asserts both URL/key before SDK initialization. Dedicated success is required independently of generic CI.

## Actual enabled test result

Test/source/workflow head **a3b6feddf36281e6a96134f71f08fa3e26146932**: dedicated run **38939134942**, job **117102050080**, completed **success**. Analyze reported **No issues**. The enabled integration case `SDK persisted restart then explicit logout and login reaches existing secondary Face reset only` passed; it was not the generic-CI skipped case. All sequence/target/cancel/logged-out assertions above executed against the real pinned SDK and existing widgets/access class, with synthetic transport/platform responses.

The initial 2ef7815 dedicated attempt passed SDK storage/recreation, authenticated home and logout session removal assertions but asserted the login frame before the real SDK's pending callback completed. The test now briefly drains bounded real-clock SDK/storage callbacks and pumps the following frame before retaining the same UI expectations. No product callback or authentication logic was changed. The first failed test is not represented as a successful run or as proof of a user-facing application bug.

At verification time, Secret Scan and Route checks also succeeded; full Flutter and iOS workflows remained in progress. The subsequent commit that records this result is documentation only, with test/workflow source unchanged from a3b6fedd. Real iPhone/OS shutdown behavior and which password the user previously changed remain outside this synthetic result. PR1157 remains held and unmerged.
