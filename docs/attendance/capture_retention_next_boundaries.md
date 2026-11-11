# GPS original evidence: additional isolated boundaries

This follow-up reuses PR829's completed management-retention fixture rather than
repeating it. The harness pins its reviewed Git objects (`46f7099482f5fa203613873b8dbd2469a3f612a0` and
`0ba3d120199e5fd43caad9967e20f958fe7d17e0`); those commits must be present in the checkout (a shallow clone must
fetch PR829 history first). Runtime: `@electric-sql/pglite@0.3.14`.

Run from the repository root:

```sh
node tool/verify_capture_retention_boundaries.mjs /absolute/path/to/node_modules/@electric-sql/pglite/dist/index.js
```

The new assertions first reproduce the existing gap: a fixed capture UUID can be
inserted again after management deleted its live row, despite the experimental
archive retaining it. An isolated INSERT trigger then rejects that archived UUID
with SQLSTATE 23505 for both identical and altered retry payloads. This tests direct INSERT, not the complete production capture
RPC, concurrent retries, or user-visible retry handling.

A synthetic route child reproduces the production
`route_journey_captures.source_clock_in_id ON DELETE CASCADE` direction. A parent
BEFORE DELETE snapshot saves the intermediate photo path/payload before cascade.
The original child's `daily_report_id` is also preserved. Its `created_by` remains the capturer; `changed_by` is the actual
management `auth.uid()` actor, separately recorded. This tests database row
retention, not retention/existence of the Storage photo object.

No production migrations, auth/RLS, rollout setting, expiry period or live
Supabase data are changed. The synthetic fixture's pre-existing capture gate is
local only. Turning on production capture is outside this proof. Full PostgreSQL
concurrency, production RPC UUID rejection, worker/company/account deletion,
archive access authorization, report child/signature completeness, Storage
lifecycle and retention policy must be resolved before a production design.

The dedicated workflow fetches and verifies both pinned Git commit objects before
running these assertions; no unreviewed PR head is used as fixture input.

## Repository path audit after the isolated Storage candidate

Read-only source audit used the `6e9e1b25` product baseline of this worktree.
Root checked current main `c6b51faa`: attendance source, functions, migrations,
workflows and tool files have no changes from that baseline. Subsequent product
main changes require a fresh check before implementation.

| Path | Actual repository behavior | Remaining boundary |
| --- | --- | --- |
| `lib/features/attendance/attendance_verification_page.dart` → `attendance_verification_repository.dart::uploadCapturedPhoto` | Controller uploads bytes with `upsert:false` to `attendance-evidence`; path is company/attendance/site-or-route/worker/timestamp.jpg. | Archive stores a path reference, not a copy or proof of bytes. |
| `lib/features/attendance/attendance_verification_repository.dart::createVerification`, `submitCaptureDraft` | Contract captures persist a fixed UUID draft and exact-row recovery. The `capture == null` legacy branch uploads separately and calls Storage `remove([storagePath])` after an insert failure; contract captures skip that cleanup. | Legacy unknown-response cleanup can meet the old DELETE policy. Storage API response-loss behavior is not covered by SQL fixtures. |
| `lib/features/attendance/route_journey_capture_page.dart` → `route_journey_capture_repository.dart::upload`, `submit` | Intermediate photos upload to `attendance-route-evidence`, company/attendance/route/worker/source-clock-in/timestamp.jpg. Submission uses `route_journey_capture_exact` / `save_route_journey_capture`; upload explicitly never deletes on an unknown insert response. | Pending photo orphan lifecycle and photo bytes are unverified. |
| `supabase/migrations/20261008204012_route_journey_capture_staged.sql` | `private.route_journey_captures` holds photo path in `payload`, original `created_by`, parent clock-in FK with DELETE CASCADE and report FK with DELETE SET NULL. Separate bucket has INSERT/SELECT policies and no UPDATE/DELETE policy introduced here. | Synthetic child fixture proves the FK direction and snapshot ordering, not complete production route rows or all deployed policies. |
| `lib/features/attendance/attendance_management_repository.dart` → `public.force_manage_attendance` in `supabase/migrations/20261008124940_gps_shift_work_date_evidence.sql` | Manager upsert/delete/off/paid-leave operations delete original verification rows. RPC checks authenticated actor, owner/admin/manager role and `can_manage_attendance`. Parent deletion can cascade intermediate records. | Existing archive fixture covers representative management changes; full production authorization and every dependency are not covered. |
| `lib/features/attendance/attendance_correction_repository.dart` → `submit_attendance_correction_request` | Ordinary correction route creates a request/items then submits for approval; failure cleanup deletes the draft request, not attendance photo bytes or verification evidence. | No ordinary-user evidence-delete RPC was identified in this repository audit. This is not proof of deployed endpoint absence. |
| `lib/features/attendance/attendance_cloud_repository.dart::delete` | Directly deletes an `attendance_entries` row; this is not an evidence/photo deletion RPC. | Its complete trigger/FK graph is outside the current original-capture proof. |
| `supabase/migrations/20260920211200_allow_orphan_attendance_evidence_cleanup.sql` | Authenticated owner orphan cleanup checks public verification references; manager OR bypasses that check. Neither branch checks a private archive. | `tool/verify_capture_storage_retention.mjs` demonstrates baseline and fixture-only candidate with live/archive checks outside actor OR; production policy unchanged. |

Searches across `supabase/functions`, `.github/workflows`, `tool/*.sh` and migration
SQL identified no attendance-bucket service-role Storage removal worker, no
`storage/v1` deletion endpoint implementation, and no attendance photo lifecycle
or scheduled cleanup configuration. Service-role usages exist in
`supabase/functions/create-employee-invite/index.ts`,
`supabase/functions/line-webhook/index.ts`,
`supabase/functions/send-master-recovery-codes/index.ts` and the shared account
inspection helper, but the inspected code does not remove attendance photos.
Scheduled migration jobs concern payroll and leave reminders, not attendance
photo expiry. No conclusion is made about deployed dashboard settings, external
workers, backup/object-store lifecycle rules or manually executed privileged SQL.
Those must be inspected independently before claiming retention of bytes.

No new test is added for absence of an external cleanup route: a source-text
absence assertion would not validate the deployed lifecycle. Existing SQL
fixtures establish object-row retention and local cascade snapshots only. The
next actionable review is deployed Storage/lifecycle inventory and a full
PostgreSQL concurrency test for reference creation versus object removal, after
the archive authorization and retention policy are decided. Neither has been
implemented or enabled by this audit.
