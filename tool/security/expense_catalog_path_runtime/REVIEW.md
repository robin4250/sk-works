# Expense native rehearsal: explicit catalog display path

Root review required. Native not executed. Original failed helper and evidence remain unchanged. This is a separate helper version, not an instruction to retry the old one.

## Exact cause and narrow correction

User read-only diagnostic found six differences only in `event_triggers.function`: production renders extensions-qualified names, clone renders the same names without qualification. Full function definitions, source hashes and remaining metadata match. PostgreSQL regprocedure text depends on visibility in search_path. Root separately read production physical references: all six functions reside in extensions, accept zero arguments, and match the six fixed MD5s recorded in the helper. This is not sufficient proof of clone physical identity; the new helper explicitly verifies that before proceeding.

Every new local psql connection sets `search_path=public` **before** any transaction, for baseline capture, prepared driver verification, install/COMMIT, actual-after read, unused undo/COMMIT and final restoration comparison. This is connection-local display normalization; no persistent role/database settings or function search_path are changed. Existing production before JSON and production prepared SQL remain immutable and are not executed. The three original reviewed source modules and `expense_default_off_plan.mjs` are byte-identical to the previous version.

The raw catalog equality function is unchanged. It still requires all non-OID fields to match exactly. No prefix is removed, no function field is omitted, and no unknown metadata or source drift is accepted.

## Physical reference preflight

The helper joins pg_event_trigger→pg_proc→pg_namespace and saves private evidence. For each of the six production event names it requires:

- production fresh function reference and source hash match the fixed root-verified extensions signature and MD5;
- the same clone event name points physically to schema extensions, the exact function name/signature, zero arguments and the same source MD5;
- all six signatures are present exactly once and event identities are unique.

A shadow function in another schema is refused even when the basename and body are identical. Unknown event/function metadata is still caught by full raw catalog equality. The fixed signatures are set_graphql_placeholder, grant_pg_cron_access, grant_pg_graphql_access, grant_pg_net_access, pgrst_ddl_watch and pgrst_drop_watch, all in extensions with no arguments.

All other clone safety, explicit one-to-one OID mapping, strict five-financial-table hash match, transaction-limited public CREATE grant/revoke, install COMMIT→actual-after→unused undo COMMIT, complete catalog/defaultACL/table/sequence comparison and cleanup follow the previous reviewed helper; see the unchanged `PREVIOUS_REVIEW.md`. Failure remains fail-closed and never changes the original restored source, backup or production. Native PostgreSQL execution and a successful COMMIT rehearsal remain unproven.

## Validation

Eight Python tests pass, including physical namespace/signature/argument/source refusal, full non-OID metadata refusal and unchanged source reuse. PostgreSQL17 PGlite test reproduces bare regprocedure rendering with visible extensions and qualified rendering under public-only search_path, confirms unchanged identity/source/ACL, proves same-body same-name shadow in another schema remains physically distinct, and distinguishes later source/ACL drift. PGlite is not native proof.

```bash
python3 -m unittest discover -s expense-catalog-path-native-20261020 -p test_native_contract.py
node expense-catalog-path-native-20261020/verify_catalog_search_path.mjs /workspace/scratch/736d0b1e377d/payroll-preservation/tool/security/fixture_dependencies/node_modules/@electric-sql/pglite/dist/index.js
```

No production endpoint, installation retry, amount conversion or Auth/JWT change is part of the helper.

Primary reference: https://www.postgresql.org/docs/17/datatype-oid.html — OID alias types display schema-qualified names only when needed by the current search_path. This explains the display difference; the helper separately checks physical identity and never treats display alone as authentication.
