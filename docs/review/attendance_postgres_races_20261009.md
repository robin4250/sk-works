# Isolated PostgreSQL race checks

Base main `a2a0ad26cebfbcc39ec99fe49f8b78d4ceb6c202`. This PR adds test files only, no production migrations or application changes.

The fixture-only SQL snapshots reproduce vehicle claim/meter worktree commit `bb799d4` and group checkout worktree commit `fc007f9`. They live under `tool/fixtures`, never the migration directory. The shared schema is extracted verbatim from the existing vehicle meter verifier. These snapshots must be updated deliberately when reviewed implementation changes.

The GitHub Actions service uses a disposable PostgreSQL 16 instance. The script refuses all database hosts except loopback and all database names except `sko_race_fixture`. It resets only that isolated fixture database. It does not read production connection settings.

Three connections coordinate lock barriers through `pg_stat_activity`: both contenders must actually wait on a lock before the supervisor releases it. No timing-only sleep establishes concurrency.

1. Two workers claim the same vehicle: one succeeds, the other returns unique violation, and the losing attendance INSERT rolls back.
2. Two simultaneous identical driver meter submissions: one immutable event, one decreased-meter warning, one baseline update, and the same saved result to both callers.
3. Driver meter registration versus vehicle deletion: no deadlock; either a complete immutable event or an explicit claim-validation failure, with no partial event. The deletion contender uses the fixture supervisor role to exercise actual FK cascade locks.
4. Two actual site participants submit the same selected roster: exactly one checkout per source; both callers receive identical results. Exact request replay does not duplicate checkout or request rows. Proxy records contain no invented GPS/photo evidence.

Vehicle and group checks are isolated scenarios. Their simultaneous ON integration, other manager deletion lock cycles, arbitrary admin corrections, notification delivery, full RLS corpus and physical iPhone behavior remain outside this test. Fixture helpers do not replace all production permission functions.

Local validation: Node syntax and diff checks pass; refusal of an unconfigured/nonlocal database was checked. Actual PostgreSQL CI reproduced and rejected a vehicle FK/row-lock upgrade deadlock (`40P01`) on run `37807077837`. Reviewed snapshot `bb799d4` fixes compatible vehicle locking and meter/deletion order; rerun is pending CI because this sandbox runs capability-free root and cannot switch to a nonroot account. Official server binaries were extracted but no cluster started. Do not report race checks passed until the workflow actually succeeds.

Snapshot SHA256:
- `20261008153425_vehicle_active_driver_claims.sql`: `a5d0f8a6de9e32a5191c509b080b70a6e4b6dc816215ea07fc9061c5ed5b8334`
- `20261008154241_group_proxy_checkout_staged.sql`: `64f8262881b3f81233365a2ff4e8f36dafd505ff599f87f7ef4b5c26dd5cdde2`
- `20261008154433_vehicle_meter_snapshots.sql`: `a54b859eef8f4b09e79b50a70e2e10e6609fadc94b96ad107d4d2f3f85918696`
- `schema.sql`: `6164826ebf630295c533569ef77eceb5772e4082edd15c763a10dadd76f8e75c`
