# Master server step-up coverage inventory — 2026-10-16

This is a **read-only source/catalog review**, not a runtime permission test or a production change. Audit repository `robin4250/sk-works`, fixed source `04d90559c8929c71b0b91f743066795b28007067`; production catalog project `ztktgquxvcxcjxtluspu`. Document branch base is `f68d46de96d7fb8c8d27585649cbf7d1b03c7569`. Only function definitions/ACLs and source files were read. No actual administrator identity, role, membership, recovery contact, challenge, device key, setting value, audit row or secret was read, invoked or logged.

Reference staged reauthentication PR [#1132](https://github.com/robin4250/sk-works/pull/1132), reviewed snapshot `c464ec8e1b9f44d9053cfea61771e11378d04bdd`. It is default OFF and not deployed. This inventory does not grant production approval.

## Conclusion

A valid logged-in enabled-master identity is checked by many existing server functions, but that is **not fresh server operation reauthentication**. Main `MasterProtectedPage` verifies Face ID/Touch ID and a secondary password before locally opening its child for up to 15 minutes, then locks on lifecycle transitions. The resulting `_unlocked`, biometric result, trusted-device boolean and local timestamp are not a nonce bound to each RPC. Calling the underlying RPC directly does not depend on that widget having opened.

At the reviewed #1132 snapshot, only secondary-password replacement and Master feature changes have implemented proof consumers. `master.security_incidents.read` is reserved for the separate monitoring lane; reservation alone does not enforce it. All other Master APIs below remain outside that staged proof boundary. **Do not report “all Master authentication complete” from the one feature setter.**

## Public API inventory

Paths below are under `lib/features/` except the explicitly named Edge function. Main direct RPC callsites were checked in the listed repositories and their Master UI entry paths; dynamically constructed names and future code require ongoing review. “No” means no operation proof in the inspected live definition or reviewed1132 consumer set, not anonymous access.

| Public API | Existing server checks | Mandatory fresh proof after reviewed1132 | Main callsite | Required handling |
|---|---|---|---|---|
| `app_referral_master_snapshot` | account + enabled-master branch in private.app_referral_dispatch | No | referrals/app_referral_repository.dart load(master:true) | Sensitive invitation-wide snapshot; fresh read operation needed |
| `bootstrap_first_master_device` | enabled master; validates key/name/type; requires no active device | No | settings/master_device_repository.dart bootstrapFirstDevice; MasterProtectedPage | Enrollment exception: add validated enrollment proof without requiring a pre-existing trusted device |
| `consume_master_recovery_challenge` | enabled master; own challenge; expiry/locked/used; both codes verified; transaction consumes | Independent recovery challenge, not1132 proof | settings/master_recovery_repository.dart consumeRecoveryChallenge | Preserve legitimate dual-channel recovery; do not require unavailable old device |
| `current_master_admin_status` | enabled-master boolean only | No; routing capability | settings/master_device_repository.dart isMasterAdmin; dashboard loader | Do not require step-up merely to discover whether enrollment/challenge UI is needed |
| `current_master_device_status` | enabled master; supplied device key; returns trust/bootstrap status and updates last-used | No | settings/master_device_repository.dart currentDeviceStatus | Bootstrap/recovery discovery exception; device key is bearer knowledge, not Face ID attestation |
| `current_master_feature_flags` | authenticated actor; returns feature availability booleans | No; ordinary feature capability | settings/master_feature_controls_repository.dart read/cache | Used by ordinary feature availability; blanket Master proof would break existing app |
| `current_master_recovery_contacts` | enabled master; own configured/masked email metadata | No | settings/master_recovery_repository.dart load | Permit minimal recovery discovery; separate sensitive management reads from discovery |
| `current_weather_provider` | authenticated; provider identifier only | No; ordinary provider metadata | home/weather_provider_settings_panel.dart repository.load | Do not blanket lock ordinary weather provider capability |
| `get_master_activity_snapshot` | enabled-master role | No | settings/master_operations_dashboard_repository.dart load | Sensitive Master dashboard read |
| `get_master_feature_usage_status` | enabled-master role | No | settings/master_operations_dashboard_repository.dart load | Sensitive Master dashboard read |
| `get_master_growth_snapshot` | enabled-master role | No | settings/master_operations_dashboard_repository.dart load | Sensitive Master dashboard read |
| `get_master_operations_snapshot` | enabled-master role | No | settings/master_operations_dashboard_repository.dart load | Sensitive Master dashboard read |
| `get_master_storage_company_summary` | enabled-master role | No | settings/master_operations_dashboard_repository.dart load | Sensitive aggregate platform storage read |
| `get_master_storage_snapshot` | enabled-master role | No | settings/master_operations_dashboard_repository.dart load | Sensitive platform storage read |
| `get_master_usage_snapshot` | enabled-master role; bounded day selector | No | settings/master_operations_dashboard_repository.dart load(1/7/30/90) | Sensitive Master dashboard read; multiple calls need coherent UX/operation design |
| `is_current_user_master_admin` | live enabled-master row check for auth.uid | No; entitlement helper | server helper; client uses current_master_admin_status | Entitlement is not fresh authentication; preserve routing/bootstrap callers |
| `master_device_rows` | enabled master; only own devices; no device secret returned | No | settings/master_device_repository.dart listDevices | Device inventory must be covered by sensitive-read proof plan |
| `master_security_incidents` | private.read_security_incident_records → security_incident_actor_company: account + master + exactly one company | Reserved scope only in1132; no consumer there | security/security_incident_repository.dart load | Monitoring lane integration is separate; do not count1132 as protection |
| `master_self_auth_audit` | private.security_incident_actor_company; own actor audit and cutoff bound | No | security/master_self_audit_repository.dart load | Sensitive own audit read; redaction is not step-up |
| `master_self_operation_audit` | private.security_incident_actor_company; own actor/target audit and cutoff bound | No | security/master_self_audit_repository.dart load | Sensitive own audit read |
| `revoke_master_device` | enabled master; own device; marks revoked/locked | No | settings/master_device_repository.dart revoke | Priority: proof bound to exact device ID and revoke operation |
| `save_master_security_incident` | private.security_incident_actor_company; validated synthetic incident fields/version | No | No call in inspected incident repository; legacy/import RPC exists | Sensitive write; preserve provenance separation from real service-ingested logs |
| `service_create_master_recovery_challenge` | service_role-only; enabled-master target; contact configuration; rate-limit trigger | Service trust, not user proof | supabase/functions/send-master-recovery-codes/index.ts serviceRpc | Keep service-only; do not expose codes/contacts to client or add client boolean bypass |
| `set_line_general_release_enabled` | account + enabled master in private setter | No | No setter call found in inspected main Dart repositories; SQL RPC remains exposed | Priority: proof-bound exact enabled value; saved setting preservation alone is not strong auth |
| `set_line_import_feature` | account + enabled master in private setter | No | chat/line_import_repository.dart setEnabled | Proof-bind exact target attendance/invoice and enabled value; no LINE feature work here |
| `set_master_device_locked` | enabled master; own nonrevoked device | No | settings/master_device_repository.dart setLocked | Priority: proof-bound device ID and lock/unlock value |
| `set_master_feature_enabled` | enabled-master role | Only this Master setter gains ON rejection + new with_proof consumer | settings/master_feature_controls_repository.dart setEnabled | 1132 Master client wiring unfinished; keep master_feature OFF |
| `set_master_recovery_contacts` | enabled master + current_master_device_status(supplied key).trusted | No short-lived operation proof | settings/master_recovery_repository.dart save | Priority: protect address replacement with fresh proof and exact normalized target; do not log actual contacts |
| `set_weather_provider` | private.write_weather_provider_setting: enabled master | No | home/weather_provider_settings_panel.dart repository.save | Proof-bind provider choice; preserve existing provider and secrets |
| `verify_master_recovery_code` | enabled master; own challenge; expiry/used/lock; code hash comparison; attempt count | Independent server recovery verification | settings/master_recovery_repository.dart verifyRecoveryCode | Preserve two distinct channels and limits; actual mail delivery not tested here |
| `app_referral_save_settings` | private.app_referral_dispatch settings branch: account + enabled master | No | referrals/app_referral_repository.dart saveSettings | Proof-bind settings/normalized URL; neither invite grants nor data should be reset |

## Private and indirect surfaces

The public weather, LINE setting, referral and incident/self-audit APIs delegate to private functions. Security-definer delegation does not magically add reauthentication: the inspected private setters/readers check the same identity/role/account/group scope described above. `private.security_incident_actor_company()` requires an allowed account, enabled master and exactly one company; it does not consume an operation proof. `private.app_referral_dispatch` checks master status separately for its `master` snapshot and `settings` action; ordinary invitation preparation and own snapshot remain distinct.

Master-only LINE history/reading/invoice branches are inventoried separately in [#1127](https://github.com/robin4250/sk-works/pull/1127), including `create_line_history_analysis`, `line_history_destinations`, historical quote/invoice consumers and reading-rule management. They have existing master/group/feature checks and the proposed distribution gate, but do not thereby acquire a fresh Master operation proof. This review does not modify their business functions.

Main now calls `app_distribution_snapshot`/`app_distribution_save_links` through the referral repository, but those names were absent from this live catalog search; the snapshot has legacy fallback and the staged distribution APIs require separate rollout review. Do not infer deployed protection from a newer client method or an unmerged staged SQL file.

Source search for non-LINE-named definitions using `is_current_user_master_admin` also covered the referral dispatcher and security actor helper, not just functions named `master`. This remains a source/reference inventory, not proof against all dynamic SQL or future indirect APIs.

## Bootstrap and recovery must remain legitimate

- Do not proof-gate `is_current_user_master_admin`, `current_master_admin_status` or ordinary feature/provider flags as though they were sensitive management operations. The app needs these capabilities to decide which login/enrollment/recovery UI to offer.
- First trusted-device enrollment has no existing trusted device. It needs an explicit server-verified enrollment path; requiring prior trusted-device possession would permanently exclude a legitimate first administrator. Current bootstrap only checks master identity, input shape and absence of another active device; the client Face ID/secondary check is not attested by the RPC.
- Emergency recovery already verifies two distinct emailed codes server-side and consumes an own, unexpired, unlocked, unused challenge after both channels are verified. Preserve that alternate route; do not require the lost device or unconditionally require a primary password that an Apple/Google-only user never established. Code delivery/provider configuration was not tested or changed.
- The device key in SharedPreferences is random bearer knowledge, not hardware or Face ID attestation. Do not label possession of it a fresh biometric proof.
- Apple/Google sign-in, existing user/admin IDs, company membership/roles, configured settings and saved history must remain unchanged. Global enforcement stays OFF until every affected legitimate authentication method has a verified path.

## Recommended integration priority — auth lane owns code

1. Close device lock/unlock/revoke, trusted-device bootstrap, and recovery-contact replacement with operation/target-bound server verification plus initial/recovery alternatives. Add exact role/account/session/target/expiry/replay/race tests, and prove legitimate administrators still recover. Do not modify identities to make tests pass.
2. Cover sensitive Master reads: dashboard snapshots, device inventory, self-audits, incident records and global invitation history. Decide a coherent server operation for dashboard reads; do not reuse a single-use proof across seven unrelated RPC calls or prompt for a password on every chart independently.
3. Wire remaining Master settings: LINE general/import switches, weather provider and invitation distribution configuration. Bind the proof to the exact normalized operation target. Avoid storing plaintext passwords, codes, actual recovery contacts or URLs containing secrets in audit logs.
4. Complete separate Auth-project tests for password and OAuth-only methods and temporary-session cleanup; run normal administrator UI comparison, capture confidential production-safe backups and rehearse restoration in isolation. Report impact and obtain explicit approval before any production permission/auth/config/deploy/enforcement change.

## Evidence limits

This review ran **no real administrator RPC**, attempted no login/recovery, sent no email/SMS and changed no source authentication or permission implementation. Existing policy/catalog definitions were inspected only. #1132's isolated proof tests and #1127's LINE gate tests are separate evidence, not a production-wide Master bypass test. Monitoring-lane additions must be checked at their own exact heads; this document does not treat another PR's reserved integration point as completed.

Known verified source files: `lib/features/settings/master_protected_page.dart`, `lib/features/settings/master_step_up_policy.dart`, `lib/features/settings/master_device_repository.dart`, `lib/features/settings/master_recovery_repository.dart`, `lib/features/settings/master_operations_dashboard_repository.dart`, `lib/features/settings/master_feature_controls_repository.dart`, `lib/features/settings/master_feature_controls_page.dart`, `lib/features/settings/settings_page.dart`, `lib/features/settings/master_emergency_recovery_page.dart`, `lib/features/security/master_self_audit_repository.dart`, `lib/features/security/security_incident_repository.dart`, `lib/features/security/master_self_audit_page.dart`, `lib/features/security/security_incident_page.dart`, `lib/features/referrals/app_referral_repository.dart`, `lib/features/referrals/app_referral_master_entry.dart`, `lib/features/home/weather_provider_settings_panel.dart`, `lib/features/chat/line_import_repository.dart`, `lib/features/chat/line_release_access.dart`; `supabase/functions/send-master-recovery-codes/index.ts`.
