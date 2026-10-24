# Compact annual resident-tax deployment review

This is an alternative transport representation for the existing bounded
installation. It does not change the annual SQL unit, authorizations, financial
operations, original deployment generator, or existing production operators.

The original unit remains SHA256
`bf6e11a2bdfb91b6a5623d1f9ca116f1e9849196a4de0ad5debc500bda8b4da1`.
The compact candidate retains the original observer, deterministic locks,
timeouts, local UTC/ISO formatting normalization, new-object source/attributes/ACL checks, and exact inventories.

Instead of embedding the full original catalog twice, both guards compare a
SHA256 fingerprint of PostgreSQL's canonical `jsonb::text`. The fingerprint
must be acquired independently using the exact observer inside a read-only
snapshot. Python JSON encoding must never stand in for server canonicalization.
After installation the four new tables, fourteen new routines, and new namespace
are removed from the observation before hashing the remaining originals.
The explicit new-object inventories and ACL/source guards still run separately.

For the observed catalog shape this reduces the SQL from 248,851 to 60,570 bytes
(188,281 bytes saved). This is payload size evidence only; a prior connector
request-state error does not establish its cause or establish that a smaller
payload will succeed. This candidate is not an authorization workaround.

Three Python checks validate source/guard retention, invalid digest rejection,
and incomplete-original rejection. The separate PostgreSQL 17 fixture compares
original and compact installation/removal, rejects stale rows/catalog/routines,
checks late-failure rollback, non-UTC/non-ISO session normalization, NULL
authorization boundaries, normal owner/viewer
access, durable retry, and used-installation removal refusal. Native execution
must succeed in CI before production preparation. No actual financial input or
production installation is performed by this review.
