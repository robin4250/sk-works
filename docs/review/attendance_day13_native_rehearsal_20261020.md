# October 13 attendance: isolated real-archive rehearsal

This is a test helper, not a production repair or a migration. It never connects
to hosted Supabase. No personal ID, name, password or actual financial amount is
embedded in the reviewed helper or SQL bundle.

The user confirmed that October 13 represents one man-day. The existing private
replay already demonstrated the normal management RPC, payroll, invoice,
communication and notification chain in a combined fixture. This next helper
tests that chain against a copy of the actual restored archive, retaining its
real constraints, grants, triggers and policies.

## Operation

1. Require the existing verified, stopped `database-restore-01qyi5py` container,
   its offline-restore label, the pinned Supabase PostgreSQL image and local
   Docker UNIX context. Refuse a running source or Docker environment overrides.
2. Commit that stopped container to a private local image and start a separate
   clone with no IP network, no ports, no host mount, an empty listen address
   and cron execution disabled. The source container is never started or stopped.
3. Match only the clone's database owner/ACL to the previously observed source
   properties, reusing the already verified expense-rehearsal procedure.
4. Record a count and ordered row digest for every non-system ordinary or
   partitioned table. Store only private local metadata/hash files.
5. In one transaction, create the existing read-only source-fingerprint helper,
   require the protected original payroll MD5, all fifteen source entries and
   original management-RPC body MD5. Derive company/worker/month from that row,
   and derive the exact original punch timestamps from the archive. Refuse any
   ambiguous or changed scope, existing day-13 entry/report/leave, partner-payment
   branch or unexpected invoice baseline.
6. Set explicitly simulated claims for the unique existing company owner only
   inside this offline transaction. Execute the existing management RPC as the
   authenticated database role. These claims do not prove a real login or JWT.
7. Require three attendance dates, one man-day on the repaired date, three days
   in payroll and invoice, preserved timestamp precision and saved deductions,
   consistent payroll totals and the unchanged invoice expense component. Require
   old reports, report workers, route quantity/approval/audit history, other payroll,
   other invoices and communication-group membership to remain unchanged. Require
   exactly one normal management notification and receipt.
8. ROLLBACK, re-inventory every table and require exact counts/digests. Require the
   temporary fingerprint helper to be absent. Stop only the clone in `finally`.
   A failed/timed-out clone stop changes the final result to failure, clears
   `verified` and records phase `clone_stop`; it cannot retain a success summary.
   The safe summary is automatically copied with `pbcopy` on Mac.

## Limits

- Success does not apply a production repair. Original raw punch IDs are replaced
  by the normal RPC inside the test transaction; only timestamp precision and
  the tested source/report behavior are preserved. Rollback restores the old rows.
- The table digest verifies row rollback, not PostgreSQL sequence values, planner
  statistics or every database property. Sequence increments are not transactional.
- This does not certify committed recovery, actual HTTP/JWT authentication,
  notification delivery, insurance registration, a new app build or device behavior.
- No code/feature flag is changed to make the test pass. The source-fingerprint
  helper is transaction-local preparation and is rolled back. A baseline mismatch
  must be reviewed, never bypassed by replacing expected hashes blindly.
- Local Docker images and stopped rehearsal clones contain private data and must
  not be published or pushed to a registry.

## Validation performed here

- Python compilation and seven lifecycle tests pass: isolation flags, normal
  rollback/clone cleanup, management failure, row drift, running-source refusal,
  nonzero clone stop and clone-stop timeout.
- The generic scenario and table inventory pass in the existing private combined
  PGlite replay using captured source/management/invoice/side-effect definitions.
  The original source, calculator and rollback assertions also continue to pass.
- Actual Mac execution against the restored native database remains pending.

Files for the protected support branch: `owner_attendance_day13_rehearsal.py`,
`attendance_clone_bundle.json`, `test_owner_attendance_day13_rehearsal.py`, and
this review. `scenario.sql` and `source_fingerprint.sql` are readable duplicates
of bundle entries. The local `smoke_replay.mjs` is a private-evidence adapter and
must not be published as a portable repository test.
