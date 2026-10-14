# SKO TestFlight Release Gate

## LINE release blocker (updated 2026-10-14)

- LINE talk must remain unavailable to general users in TestFlight and the free public release. This restriction is not yet implemented or verified as a complete release boundary.
- The existing attendance and invoice switches cover only those optional features. Talk and reception currently remain available; turning off both switches does not satisfy the restriction.
- Before distribution, verify all entry points (Home/Menu, shared SKO conversations, notifications and direct navigation) and server-side read/send access. Hidden buttons alone are insufficient. Current TestFlight scripts do not verify this LINE restriction.
- Preserve master-only invoice preparation and saved data. Complete and inspect actual invoices from January 2024 onward through monthly import/review, historical rates and the adopted invoice format.
- Do not temporarily seal the master workflow before invoice completion and review. Whether sealing occurs before or after TestFlight depends on that review; it does not waive the general-user restriction above.
- These are outstanding conditions, not evidence that restriction, sealing or distribution is complete. Do not use old draft PR #1000 as the release implementation.

This checklist is intentionally separate from feature development so release checks can run in parallel.

## Automated gate
- Flutter CI succeeds on the candidate commit.
- iOS CI succeeds on the candidate commit.
- Secret Scan succeeds on the candidate commit.
- No unresolved merge conflicts exist on release PRs.
- Qualification production route uses the cloud-backed registration flow.
- Qualification certificate evidence supports camera/gallery upload and signed viewing.

## Device gate
- Latest main is pulled on the Mac before building.
- Xcode signing team is valid and Bundle ID is exactly `com.skworks.skWorks`.
- iPhone is detected and trusted.
- `SKO正式アイコン.png` is supplied as the AppIcon source; placeholder icon generation is forbidden for device/TestFlight builds.\n- Clean iOS build succeeds before archive/distribution.
- Login, SMS flow, role home, attendance, daily report, payroll protection and qualification/document flows receive smoke checks.

## TestFlight gate
- Build/version number is incremented.
- Archive is uploaded only after automated and device gates pass.
- Internal testers receive the candidate first.
- Any post-TestFlight feature addition gets focused regression coverage before a new build is distributed.

## Safety
Do not bypass a failed CI/security check merely to produce a TestFlight build.
