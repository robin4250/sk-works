# Draft: completed personnel notification and three PII guards

Baseline: `de0470d616b480d98ee84ec47fb67ee4b5ea036e`. Test-only preparation; no deployment, UI connection, production change, or merge authorization.

The standalone #1122 fixture replaces account/feature authorization with synthetic stubs. The new `notification_integration_verify.mjs` reuses the existing write fixture's synthetic setup and exact captured authorization functions, applies all three reviewed personnel guards, then loads the existing staged resolver unchanged. Exact setup and source-location boundary assertions fail closed if the reused fixture changes.

Four same-database direct/legacy read comparisons additionally verify manager-OFF denial, owner management read, and self/viewer direct scope; self/viewer company-wide legacy RPC denial is intentional. The 16 resolver cases cover owner/admin/enabled manager/viewer/self, disabled manager/employee/foreign-company/blocked-account denial, feature revocation, membership deletion, account restriction, inactive worker, self access with management OFF, and two actual save → approval → emitted completion notification → target resolution paths (self and enabled manager). Successful resolution must return exactly company/request/worker/status; no proposed personnel payload. Every case rolls back and compares all synthetic business/identity/provider/master rows, policies, table/column ACLs, and existing function definitions. Installing the staged resolver may add only its two functions.

Local command (PGlite 0.3.14 from the existing committed lock):

```sh
npm ci --ignore-scripts --prefix tool/security/fixture_dependencies
node tool/security/personnel_write/notification_integration_verify.mjs "$PWD/tool/security/fixture_dependencies/node_modules/@electric-sql/pglite/dist/index.js"
```

Observed result: PASS, 16 cases. `node --check` passed. No production credentials or project connection are used. Local PostgreSQL binaries are unavailable, so PostgreSQL 17 has not been run locally. The same fixture supports the existing loopback-only `personnel_rls/pg_adapter.mjs`; a dedicated CI job can provide PG17 evidence.

This complements existing guards/resolver tests; it does not replace their broader malformed-target, table ACL, read/write restoration, REST, client, or device checks. No real GoTrue/JWT, network delivery, device navigation, production restore, or TestFlight approval is claimed. Production and main freeze remain in force.
