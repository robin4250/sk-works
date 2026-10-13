# Staged attendance SQL union

This candidate starts from main `0d72c60fdb3f2312d29ee24acfc3f48c94675ab1`.
Source heads and exact migration SHA256 values are recorded in
`tool/fixtures/staged_attendance_union_manifest.json`.

Deployable migrations are included once, in timestamp order: active driver claims,
group proxy checkout, meter snapshots, scoped capability discovery, saved report
source attachment, vehicle report snapshot attachment, then source notifications.
The existing main capture failure contract follows them. PR #764 already contains
#761; #768 contains only immutable concurrency fixtures, not deployable migrations.
The three real PostgreSQL fixture SQL files must exactly equal their deployable
counterparts. Existing main Flutter/iOS CI and `prepare_ios.sh` are preserved.

All new rollout tables remain empty/default OFF. No production migration, data
backfill, account/RLS change, activation, physical iPhone installation or external
email delivery was performed. Notification recipient suspension/deleting-account
handling is still incomplete; source notifications must not be enabled. Vehicle
assignee initial administrator UI, final report publication call, external delivery,
middle-site photography and complete device flows remain unfinished.

The combined PGlite verifier uses the actual candidate migrations in one database,
including capture and deferred notification triggers, and executes the actual
claim/proxy/meter/report RPC suite. It checks default notification/capture OFF,
no notification output while OFF, migration hashes and realPG fixture identity.
Separate upstream fixture suites remain available. This is a synthetic application
baseline, not a full clean installation of every historical migration or production
data audit. CI and physical-device validation are separate requirements.

Original #771 iOS CI failed; its historical general CI/helper changes were excluded.
The candidate must pass fresh CI using the current main workflows before merging.
The older independent SQL workflows retain immutable dependency checkouts for
historical reproducibility; `Staged attendance SQL union` verifies the candidate's
actual on-branch dependency SQL instead.

Ref: Issue #273. Source PRs: #761, #764, #765, #768, #771, #773, #776, #779.
