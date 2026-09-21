# SKO pre-device readiness

Status date: 2026-09-22

This file separates what has already been verified without a physical iPhone/Mac signing session from what still requires the actual device.

## Automated / server-side checks already in place

- Flutter is pinned to 3.47.5 in CI.
- Direct Flutter dependencies are pinned and `pubspec.lock` is committed.
- Flutter analyze, tests, Android debug build, and unsigned iOS debug build are CI-covered.
- iOS generation preserves an existing Xcode project instead of replacing signing settings.
- Bundle ID is checked as `com.robin4250.sko`.
- iPhone UI is portrait-only.
- Face ID, camera, photo library, and when-in-use location permission strings are CI-checked.
- Always/background location permission is stripped and forbidden by CI.
- Broad ATS bypasses are stripped and forbidden.
- GPS is action-only; continuous tracking is contract-tested.
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
- The repeatable production DB audit is `tool/supabase_security_assertions.sql`.
- The latest production audit returns:
  `SKO pre-device database security assertions passed`
- The production audit was re-run after the latest approval-assignee and company-rate migrations on 2026-09-22 and passed.
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
12. Real location permission and GPS accuracy.
13. Real AirPrint sheet.
14. Real Files/Mail share-sheet destinations.
15. Final visual/touch review on the user's exact iPhone.

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
