# Isolated PostgreSQL race checks

Base main `a2a0ad26cebfbcc39ec99fe49f8b78d4ceb6c202`. This PR adds test files only, no production migrations or application changes.

The fixture-only SQL snapshots reproduce vehicle claim/meter worktree commit `673caed` and group checkout worktree commit `fc007f9`. They live under `tool/fixtures`, never the migration directory. The shared schema is extracted verbatim from the existing vehicle meter verifier. These snapshots must be updated deliberately when reviewed implementation changes.

The GitHub Actions service uses a disposable PostgreSQL 16 instance. The script refuses all database hosts except loopback and all database names except `sko_race_fixture`. It resets only that isolated fixture database. It does not read production connection settings.

Three connections coordinate lock barriers through `pg_stat_activity`: both contenders must actually wait on a lock before the supervisor releases it. No timing-only sleep establishes concurrency.

1. Two workers claim the same vehicle: one succeeds, the other returns unique violation, and the losing attendance INSERT rolls back.
2. Two simultaneous identical driver meter submissions: one immutable event, one decreased-meter warning, one baseline update, and the same saved result to both callers.
3. Two actual site participants submit the same selected roster: exactly one checkout per source; both callers receive identical results. Exact request replay does not duplicate checkout or request rows. Proxy records contain no invented GPS/photo evidence.

Vehicle and group checks are isolated scenarios. Their simultaneous ON integration, manager deletion lock cycles, arbitrary admin corrections, notification delivery, full RLS corpus and physical iPhone behavior remain outside this test. Fixture helpers do not replace all production permission functions.

Local validation: Node syntax and diff checks pass; refusal of an unconfigured/nonlocal database was checked. Actual PostgreSQL execution is pending CI because this sandbox runs capability-free root and cannot switch to a nonroot account. Official server binaries were extracted but no cluster started. Do not report race checks passed until the workflow actually succeeds.

Snapshot SHA256:
- `20261008153425_vehicle_active_driver_claims.sql`: `751b03ea53839f6a6723686ba15a96600b8a249ec4e772336b5863c8563a01e2`
- `20261008154241_group_proxy_checkout_staged.sql`: `64f8262881b3f81233365a2ff4e8f36dafd505ff599f87f7ef4b5c26dd5cdde2`
- `20261008154433_vehicle_meter_snapshots.sql`: `850885a1819dc904436ab7eeb899ada0d94760393dc85c7576cc523285fc23ba`
- `schema.sql`: `6164826ebf630295c533569ef77eceb5772e4082edd15c763a10dadd76f8e75c`
