# Production login/security closure conditions — 2026-10-25

Read-only follow-up after combined candidate 1aec465440e614b5ac37e86b2a88a0fe0ad62a70 passed all 14 existing focused workflows. This receipt changes no production configuration or product source. Build15 remains main 045169174188262f05b17c38495359e1059ea03b. Transporter screenshot supplied by the operator shows 0.2.0 (15) delivered at 14:20 JST; Apple processing and iPhone installation must not be treated as complete.

## Confirmed production observations

Supabase Security Advisor observation timestamp: 2026-10-25T05:29:47.005Z.
- Leaked password protection is disabled (WARN). It is not inferred from a frontend provider flag.
- 175 authenticated SECURITY DEFINER RPC findings are review inventory, not 175 proven vulnerabilities. Intentional guarded RPCs must not be indiscriminately revoked or changed to INVOKER.
- 169 RLS-enabled/no-policy findings are INFO; private deny-by-default tables must not receive permissive policies simply to silence this inventory.
- Read-only pg_proc inspection of set_secondary_password, verify_secondary_password, set_master_device_locked, set_master_feature_enabled and bootstrap_first_master_device confirms anon EXECUTE false and explicit search_path for all five. No password/hash/session/business rows were selected.
- Current set_secondary_password requires auth.uid and minimum length, but its ON CONFLICT branch resets an existing credential without a separate fresh-auth proof. This is a remaining authorization-strength gap, not evidence of an observed compromise. The reviewed proof replacement must guard the old RPC as well; merely adding a new proof RPC leaves a bypass.
- Current Master setters retain Master/own-device checks. Their existing production definitions do not establish the staged operation-specific reauthentication contract.

## Required order

1. Keep the tested next-release phone enrollment default OFF/preparing until actual SMS delivery, verification, rate limiting and account binding have been proven. Existing verified-phone eligibility, confirmed email/password and Google/Face ID remain preserved. Build15 does not contain PR1402.
2. Review/deploy the exact proof subsystem and Edge issuer with default gates OFF, protected before/after snapshots and tested rollback. Preserve initial credential setup while requiring proof for replacement, including the legacy setter path. Bind actor + original live session + operation + exact target + TTL + one-use consume. No fabricated sessions, actual user passwords or synthetic production signatures.
3. Prove issuer cleanup of the distinct temporary password session, original-session survival, incorrect actor/session/target/expired/replayed proof refusal and failure/OFF behavior using isolated disposable actors. Existing isolated successes are reusable but do not certify production deployment.
4. Enable only the intended operation after backend and matching client readiness. Do not switch a production gate simply because the Flutter candidate passed.
5. Enable leaked-password protection through a supported Auth configuration route, first preserving current settings and evaluating plan availability. This connector exposes no Auth configuration read/update capability; SQL is not a substitute for GoTrue settings. Never edit auth user rows or obtain privileged credentials to bypass this limitation. Existing passwords must not be collected for testing.
6. Collector role provisioning remains independently blocked by the managed non-superuser creator-membership and catalog-lock contract. Keep executable role artifacts absent and collector gates OFF; do not weaken that boundary to enable the proof subsystem.
7. Full cross-company/API/Storage and actual iPhone security checks remain open. Catalog inspection is not actor-based RLS proof.

No production Auth/provider/role/Edge/gate changes were made by this review.
