# SKO pre-device readiness

Status date: 2026-09-21

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
- Sensitive routes are protected by the secondary password / Face ID gate.
- Sensitive pages re-lock when the app backgrounds.
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
- Tracked production-secret scanning runs in CI.
- Mac/iPhone diagnostics distinguish USB visibility, Xcode visibility, Flutter visibility, signing state, and Xcode first-launch state.
- Supabase migration-history drift is documented and a non-destructive Mac-day reproducibility preflight is available.

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

If it stops, capture the diagnostic report:

```bash
bash tool/collect_ios_diagnostics.sh
```

For non-destructive Supabase reproducibility review:

```bash
bash tool/supabase_repro_preflight.sh
```

Never run `supabase db reset --linked` against the production SKO project.
