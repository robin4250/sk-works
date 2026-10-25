# Source prerequisites

Install order: current main backend → document-only candidate (Native 91 success at 6f636982) → admin candidate.

- `public.force_manage_attendance(text,jsonb)`: `7de4106cf653bb7b39ab0103ec462853`
- `shared_daily_report_private.guard_report()`: `32a4aabea93879115b0a4f6995fee2fe`
- `shared_daily_report_private.guard_roster()`: `0371e52bc0de112f5172a59aa54dd56f`
- `private.clear_daily_report_signatures_on_draft()`: `8ff75a54758f5a40fdb57e94b95b3207`
- `private.clear_daily_report_signatures_on_workers()`: `16e44fa84d4855055a24cbc50c94afbe`
- `private.report_refresh_payroll()`: `de4b65bfde87a71776ebbd9c5fb538f4`
- `private.report_refresh_invoice()`: `1e11279c7cddff816d34399ad155f9d7`
- `private.reject_direct_attendance_delete()`: `0a43ed5f8484b6a1b01ae9b317a1b765`
- `company_checkout_allowance_private.guard_report_metadata()`: `9a9026ce08cdb5f6feed37456cc49605`

Force source comes from the fresh read-only snapshot, not the October 4 migration. Its original role/feature/payload checks, lock_management_batch prefix, original row changes and int result remain; only scoped begin/finish, empty-parent cancellation and authorized revival hooks are added.
