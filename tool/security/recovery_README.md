# Recovery rehearsal tools

These tools preserve source and test restoration only in a newly created local directory. They do not connect to, back up, restore or alter any production database, Auth provider, Storage, Edge service, role or membership.

- `recovery_source.py snapshot`: private, non-overwriting source/dirty-state snapshot outside Git.
- `recovery_source.py rehearse`: fresh disposable source restoration with byte/index/status comparison.
- `recovery_source.py database-target-shape`: rejects remote/production/credential-bearing/non-fixture URLs. Even an acceptable shape remains BLOCKED, exit 2: database freshness and authorization are unverified.
- `recovery_compare.py`: compares supplied private critical-state exports. Unknown/missing values block; equality never authorizes a production change.

Run `python3 tool/security/recovery_source_test.py` and `python3 tool/security/recovery_compare_test.py` for synthetic local tests. Read the [backup, isolation and explicit approval runbook](../../docs/security/RECOVERY_REHEARSAL_AND_APPROVAL_20261016.md) before using source snapshots. Real database/Auth/Storage/provider backup and restore are unfinished separate tasks.
