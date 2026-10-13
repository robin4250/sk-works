# Manual daily report linker definition checkpoint

This is a backup of one function definition and its metadata, **not a database or Storage data backup**. It contains no production attendance rows, report contents, photos, credentials, or payroll data.

The definition was read without changing production on 2026-10-11. The deployment removes only the photo-path requirement from the existing attendance linker. It preserves membership, company, site, route, canonical work date, existing report assignment, owner, ACL, search path, and SECURITY DEFINER contracts. Installing the definition does not invoke the linker or update existing rows. Subsequent authorized saves can link time-only and failed-photo attendance.

`guarded_forward.sql` checks the original function metadata, replaces the definition, and checks the resulting metadata. `guarded_restore.sql` verifies the reviewed forward version before restoring the original. Each file must run in one transaction, and errors must abort that transaction. These SQL files are reviewable deployment material; the verifier runs them only in an isolated database and never connects to production.

Run the verifier with Node and the pinned `@electric-sql/pglite@0.5.8` module path:

```sh
node tool/fixtures/manual_linker_deployment_checkpoint/verify_checkpoint.mjs /path/to/node_modules/@electric-sql/pglite/dist/index.js
```

The verifier compares the checkpoint with the actual source migration, checks that only the photo predicate changes, verifies definition and ACL preservation, rejects changed preconditions and postconditions, and confirms that existing attendance, reports, and Storage objects remain unchanged. It writes no generated files. The existing `verify_daily_report_time_only_evidence.mjs` regression separately exercises actual manual recording, report linking, chronology, retries, and saved-report reads.
