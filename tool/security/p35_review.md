# P35 — synthetic function ACL representation round-trip

Test-only candidate. Two fixed synthetic functions, five fixed disposable NOLOGIN roles, one synthetic schema. No existing function, production connection, application source, RLS, Auth, payroll or collector is changed. This does not reconstruct P34's general metadata assertions; it targets ACL representation subtleties needed by later real-backup restoration.

The direct PostgreSQL adapter refuses non-loopback hosts, any database except p35_fixture, wrong server major, existing user tables/schema/fixture roles and absent explicit synthetic flag. PGlite is in memory. All identifiers and sources are fixture-owned.

## Questions tested

- A NULL pg_proc.proacl means the default ACL. It must be retained as NULL separately from the effective PUBLIC/owner EXECUTE entries from acldefault/aclexplode.
- An explicit ACL semantically equivalent to the default is still a different stored representation.
- An explicit owner's EXECUTE, plain EXECUTE, WITH GRANT OPTION and a second-level grant made by that delegate must round-trip including the original grantor, grantee, option and ACL entry order.
- Two different original owners are retained by CREATE OR REPLACE, as are existing OIDs/config/ACLs when the signature remains unchanged; changing body is not changing ownership.
- Recreating a dropped function under its original owner, restoring explicit grants in recorded dependency order, and leaving NULL ACL untouched restores the selected definition/owner/config/ACL semantics. OIDs change after DROP: this is explicitly not OID-preserving recovery and cannot be used blindly with dependencies.
- CREATE OR REPLACE under a wrong owner does not correct ownership. Changed default privileges during recreate cause NULL-ACL verification to fail. A transaction rolls the selected attempt back, preserving prior OIDs and ACLs rather than silently broadening or normalizing grants.
- Revoking only the delegate's grant option cascades to downstream grants; both grant option and grantor must be saved for correct recovery.

## Evidence and limits

CI is pending until exact head results are recorded. This fixture does not read or restore an actual production archive, prove pg_dump/pg_restore flags, preserve arbitrary dependency OIDs or restore complete schema/table/column/default ACL state. Five fixed role identities are synthetic; no existing administrator IDs or membership are involved. The synthetic default-privilege drift test demonstrates a stop condition, not a generalized default-privilege recovery mechanism. It supplies no production restoration command or approval.

The source P34 and production backup-time/administrator-preservation requirements remain unchanged. Real backup restoration and current data recovery remain unverified until the separate protected native rehearsal supplies evidence.
