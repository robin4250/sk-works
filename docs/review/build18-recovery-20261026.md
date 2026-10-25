# Build 18 recovery integration

Base main: 8f3d881e06847ff9fdfb81d49d78884206ec17f7. Build 17 artifacts remain untouched. This integration does not create/upload/install an IPA.

- UI PR1412/c5a81538: direct supervisor signature after real reporter signature; optional deferred facts confirmation; document-only draft correction through scoped writer; history-protected reset and real re-sign. All latest 18 CI workflows succeeded, including Flutter/Android/iOS.
- Document backend PR1413/ffc08851: product SQL last changed at 6f636982; latest observed-trigger/NULL-category Native passed run40195379092. Default OFF, per-report allowlist. Financial confirmation/projection remains separate and unsupported from document-only mode; do not enable companywide.
- Attendance admin PR1414/4819ea9d: PG17 Native96 passed run40216946448/job121240022819. Current role/feature/session/company/lock validation; full prior-source/signature audit; active-mode dependent clock deletion order; signed CRUD; last-member cancellation preserving FK parent; normal-list hiding and explicit revival; paid-leave/off and atomic rollback. Default OFF per company. This is not a server-side receipt for the UI second password; the existing screen protection remains mandatory.
- CI PR1411/98bbe19b: mandatory full Flutter gate retained; duplicate iOS analyze/tests/debug build removed, native Release checks retained. Measured candidate iOS CI11m16s versus previous40m56s; no claim of improved Apple Transporter transfer time.

Install order after fresh private backup/catalogue comparison: document module then attendance-admin module. Both installers contain atomic transactions and source pins; neither inserts an activation row. Preserve source data, actual signatures, financial snapshots and current registration-gate OFF state. Never test by deleting an actual employee record. Confirm default OFF and source/data invariance before scoped activation. Do not run the old unused-only uninstall after used activation.

Next release number is18, only after final main and its required CI succeed. Use pinned helper7c780e4c6aad567787fc0e197c32d5cbe959440b with unused-build-number guard; preserve tf-candidate-w8_quh1j/build17. Mac actions remain user-run.
