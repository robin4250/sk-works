# SKO TestFlight Release Gate

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
- Xcode signing team and bundle identifier are valid.
- iPhone is detected and trusted.
- Clean iOS build succeeds before archive/distribution.
- Login, SMS flow, role home, attendance, daily report, payroll protection and qualification/document flows receive smoke checks.

## TestFlight gate
- Build/version number is incremented.
- Archive is uploaded only after automated and device gates pass.
- Internal testers receive the candidate first.
- Any post-TestFlight feature addition gets focused regression coverage before a new build is distributed.

## Safety
Do not bypass a failed CI/security check merely to produce a TestFlight build.
