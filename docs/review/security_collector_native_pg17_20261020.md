# Collector storage: native PostgreSQL 17 verification

Stacked on #1277. The unchanged 60-check synthetic storage fixture also runs against an empty disposable PostgreSQL 17 service. The adapter rejects non-loopback URLs, other database names, non-fixture credentials and URL parameters before connecting. It then requires PostgreSQL 17 and an empty user-table catalog.

The same tests cover bridge-role reachability, permission rejection, two OFF gates, sanitized event validation, idempotent ingestion, Master/proof read restrictions and atomic audit/proof rollback. The separate URL guard test runs without opening a database connection.

Local URL guard and syntax validation pass. Native CI results are pending. This adds no production DDL, grants, roles, settings or traffic. It does not implement an isolated collector runtime, transport, signing/key rotation, proof issuer registration, retention or restore. Deployment remains unavailable.
