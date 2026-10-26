# Authenticated native-enrollment composition — OFF candidate

This addition connects the existing enrollment core, SQL ledger port and temporary-primary-password port. It does not deploy an endpoint, register a MethodChannel, enable Apple, change Auth settings, modify a real identity, or replace the existing owner-policy/global-Google guards.

`native_apple_auth_port.mjs` uses only the pinned project Auth origin. An exact bearer is first verified with Auth `GET /user`; only then are issuer/audience/UID/SID/expiry claims selected from that same token. The existing SQL port rechecks its live SID, account/Google/profile/company context. The original bearer is bound once per request, never selected from body fields. Native link uses `POST /token?grant_type=id_token` with `link_identity:true`, Apple ID token and raw nonce under that original bearer. No email-based lookup, sign-up or plain Apple sign-in fallback is added.

Issued native credentials are independently verified for the original UID and a distinct SID before they become locally revocable. Original/foreign/unverified credentials cannot be passed to cleanup. The endpoint returns only `{linked:true,user_id}`; access/refresh tokens, passwords, SQL context and credential fingerprints are never returned. Ambiguous exchange or acknowledgement remains the core's durable HOLD path; no identity is deleted to manufacture rollback. Network calls reject redirects, limit bytes and enforce a hard deadline even if fetch ignores abort.

`native_apple_enrollment_handler.mjs` accepts only POST JSON containing `id_token`, `nonce`, `password`, and a bearer header. Input size/read time is bounded. Each request constructs new Auth/SQL/password ports to avoid shared original/SID or cleanup state. All four independent server-controlled gates must be true: enabled, native-only-reviewed, password-session-isolation-reviewed, global-Google-protection-reviewed. Defaults are OFF. Apple signing keys are resolved through an injected trusted server resolver and the existing RSA/issuer/audience/nonce verifier; app JSON cannot supply keys or gates. The existing registered-login handler is unchanged.

## Evidence

Local Node: 43 tests pass, including 10 new transport/composition cases. The composed positive test uses a real generated RSA Apple credential and actual existing core/password/SQL HTTP ports with isolated synthetic HTTP responses. It verifies reservation/completion and two distinct temporary-session local logouts. No remote Auth or production write occurs. CI is not yet executed for this addition.

Previous PR1420 head803f3990 remains all11 CI success: actual GoTrue12, Native15 and PGlite14 for global Google guard; its soft/hard-delete and refresh proofs are preserved. This new mocked-network composition does **not** replace actual current-GoTrue-plus-ledger integration or hosted configuration/iPhone evidence.

## Remaining before enablement

- Current managed Auth catalogue/trigger permissions, dependency-pinned install and unused-only restoration; deleted-subject recovery/false-positive release and retention policy.
- Execute the new composed lifecycle against the reviewed current GoTrue and exact SQL ledger, then hosted configuration checks including original refresh/session preservation, single-session/CAPTCHA policy, provider/hook/global-guard gates.
- Supply a bounded pinned Apple-key resolver at the real deployment boundary, expose a deployment entrypoint only after reviews, connect native MethodChannel and isolated app-state handling, and test the owner's real Google/Face ID and Apple flows on iPhone.
- Apple-only new-account whitelist remains outside the existing minimal Google-UID protection design; do not claim universal signup lockdown.

No production/provider/identity/company/main/IPA change is part of this candidate.
