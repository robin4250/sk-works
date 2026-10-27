# Native Apple credential channel — OFF integration candidate

The real iOS preparation script now registers `com.skworks.sko/apple_credential` and appends versioned native source/state into the generated AppDelegate. Existing Google/OAuth callback handling, map/PDF/capture/reminder registration, Bundle ID, signing/team/profile, entitlements and all existing app capabilities remain unchanged. `SKOAppleCredentialPreparationEnabled` is explicitly false in generated Info.plist. Dart's existing compile-time gate also defaults false. No settings/login UI is enabled.

Native acquisition reuses the already-reviewed AuthenticationServices/CryptoKit/SecRandom source. Apple receives SHA256(raw nonce), a separate random state, and no requested profile scope. The native result contains only ID token and raw nonce, never a new SKO/Supabase session. This channel never calls Auth or a broker and cannot change an existing Google UID/company/session.

Each request has a fresh 32-hex correlation ID and exactly-once completion. Busy requests cannot be replaced. Wrong-ID cancellation and late callbacks cannot resolve a later request. Background entry, explicit cancellation, disposal and three-minute deadline invalidate outstanding delivery. iOS16+ uses the documented ASAuthorizationController.cancel(); on iOS15.5 delegates/nonce/state are cleared so a later result cannot escape, while the system sheet may require the user to dismiss it. Transient inactive/Face ID state is intentionally not treated as background.

Dart verifies the original exact Google actor/bearer with Auth getUser before calling native, tracks historical actor/token changes (including A→B→A), and rejects credentials after background/disposal/timeout. Cancellation messages contain only their correlation ID; failed cancellation cannot authorize a result. No signIn/linkIdentity/session adoption or password persistence is introduced.

## Evidence and limits

New state engine executable checks and real iPhoneOS SDK typechecking are supplied in CI; Flutter tests add background/dispose/timeout/busy coverage. The actual generated AppDelegate is compiled by the existing iOS Release CI. Local Flutter/Dart was not run. Until those exact-head checks succeed, this is an unverified code candidate.

Still required: reviewed hosted/provider/hook/global-protection/password-session gates; pinned install/restoration and subject recovery/retention; actual Apple capability/distribution provisioning; broker deployment and bounded Apple-key resolver/ingress controls; app endpoint command submission and outcome UI; owner iPhone Apple/Google/Face ID original-refresh checks. Neither compiling nor acquiring an Apple credential proves successful account enrollment. Do not activate either gate before those requirements.

Apple documentation reviewed: ASAuthorizationController.cancel() is available from iOS16, and invokes its delegate cancellation callback; iOS15.5 support uses local invalidation. Native signing/Apple account configuration was not operated.
