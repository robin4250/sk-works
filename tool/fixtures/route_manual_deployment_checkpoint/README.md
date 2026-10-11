# Manual-route function definition checkpoint

This contains code and privilege metadata observed before updating the four
manual-route functions on 2026-10-11. It contains no attendance records, worker
records, photographs, or Storage bytes. It is not a database or Storage backup.

`guarded_forward.sql` refuses any prerequisite drift before replacing exactly
the four existing functions from the reviewed manual-route migration.
`guarded_restore.sql` is an emergency code recovery checkpoint and refuses any
unexpected current definition before restoring those four original definitions.
Neither script changes existing data, Storage objects, row policies, or grants.
Execute a deployment script only as one transaction after rechecking the target.

The regression harness creates a disposable PostgreSQL fixture, checks guards,
ACL retention, row/Storage retention, rollback, and original-definition recovery.
It has no production connection and does not execute the recovery on production.
