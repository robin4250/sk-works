# GPS photo capture audit — 2026-10-09 JST

Reviewed latest main a2a0ad26 read-only. No production or shared attendance code edits.

- Attendance UI gets GPS before opening camera. GPS failure aborts photography and attendance; cancelled camera also aborts. Failures use SnackBar, not a confirmation/retake popup.
- Repository uploads photo before insertion. Upload failure aborts attendance, while cleanup failure can mask the insertion error.
- Legacy CHECK requires location for location_photo and a photo path. Missing evidence cannot merely be written without a narrow reviewed schema change.
- Daily report evidence query excludes null photo paths. Evidence view uses confirmation time, coordinates/map link only; capture time/address snapshots and missing/failure rendering are absent.

Safe connection contract: preserve source clock-in ID, server work date, company/site/route and requested method. Separate attendance validity from camera/GPS/upload status. Record capture timestamp and actual GPS sample timestamp/address provenance. Never assign current location to a historical photo. Preserve nullable evidence drafts and show immediate Confirm/Retake decisions. Upload acceptance is not attendance DB success; offline drafts remain unsaved. Future persistence must idempotently connect the same evidence to the same shift and use narrowly scoped CHECK/RLS changes, not pretend missing GPS is manual attendance. Interim photos are only offered in the explicitly selected multi-site journey path. PDF and screen must render the same missing/failure/address metadata once connected.
