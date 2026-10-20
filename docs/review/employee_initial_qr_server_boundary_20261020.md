# Employee initial QR: next server boundary (review only)

Baseline source: main c8216d9a31e0d8340c9ec123307907bc148191a8.
Read-only observations on 2026-10-20. No production changes or new invitation.

## Evidence and distribution scope

Owner-only TestFlight testing and distribution to employees/friends/partners have separate gates. A honeypot is not a substitute for Auth/session, RLS, invitation and company boundaries.

- Public Auth settings: Google/email enabled; Apple/phone disabled. Email/password and phone/password UI already exist in main. The existing Google-to-Apple identity-link source exists; provider configuration and real callback/re-login remain unfinished. Preserve current Google UID, company, role and Face ID.
- Main app referral storage exists but enabled=false, public_enabled=false and distribution URL is unset. New app_distribution_snapshot(boolean) and app_distribution_prepare(text,text,text,text) are absent. Existing friend workspace/profile/request RPCs exist. Do not call the missing distribution API implemented or infer actual friend E2E success from RPC presence.
- Production collector event table is absent. Decoy lab is synthetic/offline; collector SQL remains review-only. These do not establish operational honeypot or moving-target defense.
- Existing employee QR embeds ordinary phone/password credentials. Auth password login occurs before invite state/expiry checks. The state reader cancels an expired invited row, and the existing password-change marker rejects an expired invited row. Reuse those completed guards.
- Current private.account_access_allowed() only checks authenticated UID and account-deletion restrictions. It contains no invitation/session/expiry boundary. Do not simply inject invitation checks here: onboarding/recovery callers need a separate scoped review.
- PR #1245 head 5b4d4c9c235e8f4d1e42e8acc50a51592fc37306, job 117819544837 succeeded with result BASELINE OBSERVED; NOT A FIX. Phone password grant was blocked by isolated CLI provider settings; a separate email proxy measured expired/cancelled credential issuance, repeat before password change, password-update-before-marker ordering and old JWT Data API access. The result is explicitly email_proxy_NOT_phone_QR_proof and production_equivalence=false.
- Sanitized observation: expired_login_issued_token=true; expired_marker_denied=true; cancelled_qr_login_issued_token=true; valid_qr_repeat_before_password_change=true; old_password_denied_after_change=true; replacement_login_after_marker_denial=true; old_jwt_auth_status=403; old_jwt_rpc_status=200. This does not demonstrate another employee/company data disclosure.

## Smallest coherent server change

A UI-only expiry check, deleting a refresh token, or one more unconnected helper is insufficient. The smallest coherent rollout changes the initial-credential issuance/redemption and the sensitive session boundary together, behind an explicit scoped rollout. No general phone enablement should precede this.

1. Keep normal owner Google/email/phone login and already approved employee accounts unchanged. Only fresh invitation-v2 Auth identities explicitly registered by the trusted issuer enter this protocol. A stale/cancelled invite must not enroll an existing ordinary account or revoke its established recovery routes. Never identify accounts by phone/email string equality alone.
2. New QR contains a cryptographically random one-use redemption token and invite reference, never a reusable permanent Auth password. Store only a token hash in a private table. Bind it to the exact invitation, Auth UID, company, worker and issuance generation. Reissue locks the invitation and replaces the generation; do not recover or resend an old password.
3. Trusted redemption verifies token hash, current generation, intended UID/company/worker, live invitation status and server expiry under one row lock. Identical transport retry returns only the original bounded operation receipt; it must not create a new session or reveal credentials. Different-session replay, cancellation, expiry and old generation fail. No public client role can mutate redemption state.
4. Session issuance is a trusted Auth integration, not a SQL stub accepting a caller-supplied session ID. Bind the issued auth.sessions row and actual UID to a short onboarding lease. Require a live nonexpired auth.sessions row on each protected API operation. The new credential cannot produce a business-capable JWT in the interval before its lease is recorded.
5. Initial leases permit only an explicit onboarding operation allowlist for the bound invite. They do not grant general worker/family data, payroll, invoice, payment, chat/LINE or other-company access. Existing onboarding RPCs keep their existing ownership, exact source/version, approval and photo-retention checks. Cancellation, expiry, reissue and session revocation immediately deny all old leases, including old access JWTs.
6. Completing registration requires a trusted successful permanent-credential replacement and the existing approved registration state. The current client sequence Auth update then marker is not an atomic proof. Preserve a durable cutoff for all initial session IDs; never delete the registry in a way that re-enables an old initial JWT. Ordinary login must issue a fresh permanent-credential session after the cutoff, bound to the same original UID/company/worker/role.
7. Integrate the boundary with the actual exposed table RLS and SECURITY DEFINER/Storage/Edge paths. A helper used by only the normal UI leaves direct REST/RPC bypasses. Preserve legitimate owner and approved-employee paths with before/after tests. Do not modify general account_access_allowed() until its complete caller graph and onboarding/recovery exceptions are reconciled.

## Required isolated proof before rollout

Reuse the pinned GoTrue observation from #1245, existing company-link tests, account restriction fixtures and captured deployed onboarding definitions. Add real phone-provider proof through a legitimate isolated provider arrangement; do not add fake SMS credentials or rerun the previously failed provider experiments.

The paired implementation must prove: new token single consume and transport retry; simultaneous redemption; expiration before/after issuance; cancel/reissue versus redemption races; initial-password/QR replay; mismatched session/user/company/invite; direct REST/RPC/Storage denial before approval; old JWT denial after password replacement/approval/reissue/revoke; new ordinary session success after approval; owner Google/Face ID continuation and recovery; pre-existing approved employee unchanged; rollback without deleting legitimate identities or loosening old-session denial. Server Auth configuration and backup/restore remain independent prerequisites.

This document is a concrete server integration contract, not an installed hook, Edge exchange, SQL guard or completed phone/QR fix. It intentionally does not present an unconnected default-OFF helper as usable security.
