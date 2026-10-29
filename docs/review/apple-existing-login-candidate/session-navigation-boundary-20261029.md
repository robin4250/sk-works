# Session navigation boundary

The existing app Navigator previously watched only the SDK user ID. A same-user successor session therefore retained pushed private routes and their old state. The production navigation boundary now watches actual SDK AuthState session UID and JWT session_id, destroys the Navigator for a changed session, and retains routes for token refresh within the same session. Checkout gate subtree uses the same key.

This decodes a UI lifetime identifier only; it does not verify JWT signatures or grant authorization. Missing/malformed session binding or subject mismatch blocks UI rather than accepting a UID-only fallback. Auth stream error/completion retains the existing fail-closed behavior. The first valid signedIn from signed-out preserves the existing pending OTP/password/onboarding callback; initialSession restoration and subsequent changes do not receive that exception.

The Apple owned SDK coordinator remains OFF and unconnected to global session adoption. This change does not serialize SDK writes, prove persistence, enable Apple enrollment/ACK endpoints, activate individual document exemptions, deploy, or establish iPhone device validation.

Validation pending dedicated Flutter CI: actual AuthState fixtures cover different UID, logout, same UID/different SID, same SID token refresh, rapid SID return, malformed session, stream error, and onboarding/restoration behavior. No live credentials or provider interactions are used.
