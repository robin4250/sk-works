# Isolated PostgreSQL race checks

Base main `a2a0ad26cebfbcc39ec99fe49f8b78d4ceb6c202`. This PR adds test files only, no production migrations or application changes.

The fixture-only SQL snapshots reproduce the exact migration bytes from reviewed worktree commit `53b24fc` (vehicle claim/meter implementation `7aca6aa`, group checkout lock order `600dc74`). They live under `tool/fixtures`, never the migration directory. The shared schema is extracted verbatim from the existing vehicle meter verifier. These snapshots must be updated deliberately when reviewed implementation changes.

The GitHub Actions service uses a disposable PostgreSQL 16 instance. The script refuses all database hosts except loopback and all database names except `sko_race_fixture`. It resets only that isolated fixture database. It does not read production connection settings.

Three connections coordinate lock barriers through `pg_stat_activity`: both contenders must actually wait on a lock before the supervisor releases it. No timing-only sleep establishes concurrency.

1. Two workers claim the same vehicle: one succeeds, the other returns unique violation, and the losing attendance INSERT rolls back.
2. Two simultaneous identical driver meter submissions: one immutable event, one decreased-meter warning, one baseline update, and the same saved result to both callers.
3. Driver meter registration versus vehicle deletion: no deadlock; either a complete immutable event or an explicit claim-validation failure, with no partial event. The deletion contender uses the fixture supervisor role to exercise actual FK cascade locks.
4. Two actual site participants submit the same selected roster: exactly one checkout per source; both callers receive identical results. Exact request replay does not duplicate checkout or request rows. Proxy records contain no invented GPS/photo evidence.

The combined ON scenario additionally races personal driver checkout with another actual member’s proxy checkout and verifies driver-only meter registration. Other manager deletion lock cycles, arbitrary admin corrections, notification delivery, full RLS corpus and physical iPhone behavior remain outside this test. Fixture helpers do not replace all production permission functions.

Local validation: Node syntax and diff checks pass; refusal of an unconfigured/nonlocal database was checked. Actual PostgreSQL CI reproduced and rejected a vehicle FK/row-lock upgrade deadlock (`40P01`) on run `37807077837`. Snapshot `bb799d4` fixed compatible vehicle locking and meter/deletion order, and all four scenarios passed on actual PostgreSQL run `37807799111`. Current snapshot `7aca6aa` adds activation serialization; those new checks are pending CI because this sandbox runs capability-free root and cannot switch to a nonroot account. Official server binaries were extracted but no cluster started. Do not report the new activation/toggle checks passed until their workflows actually succeed.

Both workflows check the committed `SHA256SUMS` before loading SQL. Changes to fixtures or prerequisite migrations trigger the applicable workflow. Snapshot SHA256:
- `20261008153425_vehicle_active_driver_claims.sql`: `27f300260f77fe27fd4babfc7c050e3c4c2017aac56626c61da8e76e37dbe90b`
- `20261008154241_group_proxy_checkout_staged.sql`: `b229cfd9711257a3f8178d8d8c5c50a2e1e6b1ff35c4c7e083aa9ea26ede66dc`
- `20261008154433_vehicle_meter_snapshots.sql`: `68774fa7a412ad0de068197f9afe70ac895efde5621bb44fc850cff35eddd2f1`
- `schema.sql`: `6164826ebf630295c533569ef77eceb5772e4082edd15c763a10dadd76f8e75c`

## Activation serialization guard: fix verification

The former unsafe OFF-start/activation interleaving is now checked using strict safe expectations in `reproduce_vehicle_rollout_activation_race.mjs` and the separate **Vehicle Activation Guard** workflow. The deliberately red reproduction was prepared but not published; the production prohibition remains until these corrected SQL snapshots and UI integration are validated.

For both an absent gate and an existing OFF gate, the test verifies two independent connections:

1. OFF start finishes its trigger but stays uncommitted. Activation must actually wait on the company lock. After start commits, activation must reject the now-visible unresolved start (`P0001`), leaving OFF with one start and zero claims.
2. Activation obtains the company lock first. The start must actually wait. After activation commits, the start must observe ON and create exactly one claim.
3. REPEATABLE READ starts and activation are explicitly rejected, preventing a stale transaction snapshot from evading the recheck.

The primary race verifier additionally checks rollout disabling versus fresh meter registration. The toggle must complete; the meter either commits its complete event or clearly rejects the disabled feature. No deadlock or partial meter/current-value update is accepted. Existing strict unique-violation and atomicity expectations remain unchanged.

Snapshot `7aca6aa` acquires a company advisory lock before attendance vehicle/source FK checks, uses the same lock for rollout changes and meter writes, removes rollout-row share locks, and retains vehicle NO KEY UPDATE then claim locking. Actual PostgreSQL runs for this new protocol remain pending CI. The earlier four scenarios passed on run `37807799111` with snapshot `bb799d4`; that evidence must not be confused with completion of the new activation protocol.

A further combined ON fixture races a normal driver checkout against a same-site passenger's group proxy checkout, requires one driver release and two total checkout records, rejects passenger meter registration, and permits the claimed driver's final meter update. This test uses the updated group company-before-source lock order from `600dc74`; actual CI results are pending. Existing daily-report writer/attachment integration remains outside this fixture and is still a separate blocker. No production rollout has been enabled.
