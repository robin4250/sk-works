# SKO pre-device readiness

Status date: 2026-09-30

This file separates what has already been verified without a physical iPhone/Mac signing session from what still requires the actual device.

## Automated / server-side checks already in place

- Flutter is pinned to 3.47.5 in CI.
- Direct Flutter dependencies are pinned and `pubspec.lock` is committed.
- Flutter analyze, tests, Android debug build, and unsigned iOS debug build are CI-covered.
- iOS generation preserves an existing Xcode project instead of replacing signing settings.
- Bundle ID is checked as `com.skworks.skWorks`; alternate IDs are rejected.
- iPhone UI is portrait-only.
- Face ID, camera, photo library, and when-in-use location permission strings are CI-checked.
- GPS自動出勤を使わない通常運用では、位置情報は操作時のみ取得します。
- GPS自動出勤を有効にした場合だけ「常に許可」と Background Location を使い、指定曜日・指定時刻の前後で現場到着判定を行います。
- GPS自動出勤を無効化するとバックグラウンド位置取得サービスも停止します。
- 位置情報＋写真はGPS自動出勤と別機能で、出勤/退勤確定時にだけ現在地を1回取得します。
- Broad ATS bypasses are stripped and forbidden.
- Camera cancellation must not create attendance.
- Secondary authentication is role-specific: general users and sub-admins use it for payroll statements; admins use it for invoices and admin-only site financial data.
- Required documents and qualification certificates do not require the secondary password.
- The secondary password is configured on first access to a protected page, not during initial app onboarding.
- Protected pages re-lock when the app backgrounds.
- Employee onboarding supports temporary-password sharing and QR handoff, then forces a new primary password before profile submission.
- Employee onboarding identity documents use a dedicated private Storage bucket and one reviewer approval activates membership.
- New-company admin onboarding is guided through company/self registration, required-document setup, first-site setup, and company rate setup; existing companies are backfilled complete.
- General users, sub-admins, and admins all retain personal clock-in/clock-out controls; management attendance remains separately permissioned.
- Primary login is phone-ID only.
- Primary password recovery requires SMS for an existing user and updates the password immediately after OTP.
- Phone-number change requires SMS confirmation before the Auth login ID/profile number is updated.
- Secondary-password verification is server-side bcrypt-backed with retry locking.
- Public Supabase tables have RLS enabled.
- Anonymous public-table/RPC access is removed.
- Storage buckets are private and have upload-size limits.
- Attendance photos, worker documents, qualification certificates, payroll, invoices, customer billing data, worker contact details, and LINE binding metadata have explicit privacy boundaries.
- Membership writes are RPC-only and the owner role is protected.
- CRUD grants without a matching RLS path are removed.
- LINE webhook signature verification is HMAC-SHA256 with constant-time comparison, and deployed Edge Function source matches Git.
- `create-employee-invite` is deployed from the current Git source with JWT verification enabled; the production function was updated after invite role/approver assignment was added.
- The repeatable production DB audit is `tool/supabase_security_assertions.sql`.
- The latest production audit returns:
  `SKO pre-device database security assertions passed`
- Supabase Security Advisor informational warnings for RLS-without-policy tables are intentional on RPC-only tables; authenticated SECURITY DEFINER RPC warnings are reviewed under the explicit-role-check/search-path/anon-deny contract.
- The production audit was re-run after the latest approval-assignee, company-rate, and employee-invite role/approver migrations on 2026-09-22 and passed.
- Supabase Performance Advisor currently reports 3 `auth_rls_initplan` WARN items, 19 `multiple_permissive_policies` WARN items, 92 `unindexed_foreign_keys` INFO items, and 42 `unused_index` INFO items. These are pre-existing tuning items and were not blanket-rewritten during the TestFlight stabilization pass.
- Performance tuning remains query-driven rather than blanket-indexing; the TestFlight candidate prioritizes stable behavior and verified access boundaries.
- Post-optimization production checks confirm: all public tables keep RLS enabled; anon has no direct public-table grants; SECURITY DEFINER functions are not executable by anon/PUBLIC and use explicit `search_path`; company membership, employee invites, and approval-assignee tables remain RPC-only for writes/direct access.
- Approval routing/1-to-3 approver guards, invite-time sub-admin/approver assignment, secondary-password five-attempt locking, sole-requester approval boundaries, and the seven required private Storage buckets were re-verified after the performance migrations.
- The current authenticated SECURITY DEFINER Advisor warning set is reviewed rather than auto-rewritten: the 40 currently callable functions reference `auth.uid()`, while anon/PUBLIC execution remains denied and explicit `search_path` is enforced.
- Production migration history can contain repeated deployment entries with the same descriptive migration name after safe non-destructive replay. Schema state and the reproducibility preflight are authoritative; no `migration repair` has been performed.
- Deployed `create-employee-invite` and `line-webhook` Edge Function sources were re-compared with `main` and match exactly; employee invite JWT verification remains enabled.
- Tracked production-secret scanning runs on every push and pull request, including docs-only changes.
- Mac/iPhone diagnostics distinguish USB visibility, Xcode visibility, Flutter visibility, signing state, and Xcode first-launch state.
- Supabase migration-history drift is documented and a non-destructive Mac-day reproducibility preflight is available.
- The Supabase reproducibility preflight records migration history plus SHA-256 checksums for generated baseline artifacts.
- Role-specific in-app manuals are available from Help/Profile: general 10 pages, sub-admin 15 pages, admin 20 pages, plus a 20-page SKO beta pamphlet.
- Manual/pamphlet PDFs support A4 preview, printing and sharing, with highlighted "ここを押す" guidance and support timing.
- Manual/pamphlet versioning is tied to the app version and CI rejects a mismatch.
- Sub-admins are management users but not full admins: they keep personal payroll access with secondary authentication while invoices/admin financial site data remain denied by default.
- Daily-report edit approval UI follows the configured 1-3 approval assignees; being an owner/admin alone does not bypass that selection.
- Company tax/welfare/overtime/early/night/holiday and three allowance settings can be edited by admins after initial onboarding through RPC-only company-rate settings.
- Full admins can assign sub-admin status and approval-assignee intent during employee invite; if three approvers already exist, one of the current three must be selected for replacement, and the final approval re-validates the assignment server-side.
- Site registration now creates exactly one site chat; first attendance auto-joins the worker, site closure archives the chat, and archived chats are read-only.
- Vehicle/route persistence, delegated management permissions, friendly UI, and home navigation are merged. Operational records use soft-disable to preserve history.
- Master administration now requires Master role + trusted device + biometric authentication + secondary password. The step-up session is 15 minutes and clears on app background/exit.
- Master analytics expose aggregate counts only. `get_master_growth_snapshot()` and `get_master_operations_snapshot()` deny anonymous execution; authenticated callers still pass an internal Master-role check.
- Master vehicle/route feature controls are reversible and keep existing history/data when paused.
- Master emergency recovery stores two distinct private recovery emails, exposes only masked addresses to the app, and records contact changes in the Master audit log.
- Dual-code recovery uses service-only challenge issuance, bcrypt-backed code hashes, expiry/lock/one-time consumption, and requires both codes before a new trusted device is registered.
- The `send-master-recovery-codes` Edge Function is fail-closed until `RESEND_API_KEY` and `MASTER_RECOVERY_FROM_EMAIL` are configured in Supabase Edge Function secrets. No recovery code or raw recovery email is returned to the Flutter app or written to logs.
- Recovery challenge issuance is limited to three attempts per Master user per ten minutes at the database boundary.
- Japan Country Pack is the single source of truth for current JP settings, and Japanese +81 / 070/080/090 phone normalization/validation has been moved into the JP country module without changing the existing onboarding API.
- Company discovery keys are fixed as company name, address, corporate number, and SKO company ID. Discovery remains an addressing/search contract and does not grant data access.
- The latest iPhone acceptance checklist includes sections M (site-chat lifecycle), N (vehicle/routes), and O (Master administration).
- Production migration history includes the Master admin/device/analytics/feature-control/strict-device/dashboard migrations plus the Master growth-snapshot RPC restriction. Known safe duplicate descriptive entries remain non-destructively preserved.
- Final 2026-09-30 production security audit detected broad default grants on the new `vehicles` and `route_assignments` tables. A non-destructive hardening migration removed all anon table access and limited authenticated clients to RLS-covered SELECT/INSERT/UPDATE only.
- After that hardening and whitespace-tolerant audit updates, the full production assertion suite returns `SKO pre-device database security assertions passed`.

## Still requires the real Mac / iPhone

These cannot be proven by repository or cloud CI alone:

1. Apple Account sign-in inside Xcode.
2. Personal Team / Apple Developer Team selection.
3. Creation/availability of the Apple Development signing certificate.
4. iPhone USB trust prompt.
5. iPhone Developer Mode.
6. Xcode seeing the exact physical iPhone as an install target.
7. Final codesigned build/install onto that iPhone.
8. First launch on the physical device.
9. Real SMS delivery for registration, phone change, and primary-password recovery.
10. Real Face ID success/cancel/failure behavior.
11. Real camera/photo-picker behavior.
12. Real location permission and GPS accuracy, including GPS自動出勤の「常に許可」、背景取得、指定時刻±5分の現場内/現場外判定。
13. Real AirPrint sheet.
14. Real Files/Mail share-sheet destinations.
15. Final visual/touch review on the user's exact iPhone.
16. 社員個人ページ10項目、国内0始まり電話表示、社員一覧/個別送信、A4横一覧印刷。
17. 車両登録（表示名・車両番号・走行距離・車検証・自賠責・任意保険）と複数地点ルート登録。
18. 本日の勤務報告で車両/ルート選択・解除、出勤/退勤→日報引継ぎ。
19. 退勤時の日報でメーター撮影OCR→本人確認→再撮影/手入力→走行距離更新。
20. 出勤方法/現場選択を保存してTOPへ戻ること、出勤画面の並びとTOP反映。
21. GPS自動出勤の曜日/時刻設定、±5分背景判定、現場外時の未登録通知。
22. 位置情報＋写真の証拠画像が日報と紐付き、日報横・写真一覧・ピンチ拡大で確認できること.

## Mac arrival entry point

From the repository root:

```bash
bash tool/device_day.sh
```

The device-day preflight now also fails closed unless the checkout is exactly on `main` and aligned with `origin/main`, and it re-verifies the generated iOS permission/orientation/bundle-ID contract before the unsigned build.

This one command now runs, in order:

1. Mac first-run preparation
2. the Mac/iPhone-independent release gate
3. physical-device preflight
4. the iPhone launch command

To run only the non-device gate:

```bash
bash tool/pre_device_release_gate.sh
```

If it stops, capture the diagnostic report:

```bash
bash tool/collect_ios_diagnostics.sh
```

For non-destructive Supabase reproducibility review:

```bash
bash tool/supabase_repro_preflight.sh
```

Never run `supabase db reset --linked` against the production SKO project.
