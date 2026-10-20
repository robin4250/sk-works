# Prepared expense native COMMIT/unused-undo rehearsal candidate

Root review required. Native execution has not occurred. This helper has no production endpoint, credentials or database client connection to production. It never applies the production prepared SQL. Existing `expense-prepare-only-8co2mzki` is user-confirmed preparation evidence only; default-OFF installation and -1000 conversion remain incomplete.

## Preserving actual evidence and explicit clone comparison

The helper accepts only the latest successful owner-private `expense-prepare-only-*`. It verifies recorded hashes for both prepared SQL files and the copied fresh checkpoint, expected read-only/target/v2/conversion scope, pins runtime inputs, and runs the unchanged reviewed plan generator in an offline local Node image to confirm both production SQL files are exact outputs of that fresh record. Original files are copied into a separate 0700 stage and never modified. An existing local node:22.21.0 image is required and resolved to immutable local ID; no pull occurs.

The verified stopped `database-restore-01qyi5py` container is committed into a separate local image and cloned with network=none, no port bindings/listening address, cron jobs disabled and autovacuum off. Original source remains stopped. The pinned PostgreSQL image and existing source label must match. No owner changes or original ACL baseline rewriting occurs.

The clone's five financial-table digest must equal the fresh production digest; otherwise `clone_financial_hash_differs` stops before install. Function identity is complete signature, trigger identity is table/name, event-trigger identity is name. Both catalogs must have exactly matching scopes and unique identities/OIDs. Every field except the object's OID must match exactly, including full definitions, source hashes, owner, ACL, settings, attributes and trigger function definitions. The helper saves an explicit private one-to-one production→clone OID mapping. Unknown metadata, owner, ACL or business drift refuses execution; it does not silently replace a baseline.

A separately named `private-clone-local-before.json` carries `clone_local_fixture=true` and the immutable production record hash. Only its OIDs differ according to the explicit map. The same unchanged `buildExpensePlan` generates separate `private-clone-*` SQL files. The production prepared SQL is preserved and **not executed**. This proves the same driver logic with a clearly labeled local OID contract, not the exact production OIDs.

## Native COMMIT and recovery sequence

1. Capture the original clone catalog (all non-system schema functions/owners/ACLs, relation metadata, roles/membership, policies/triggers/events), default ACLs, all non-system table digests and sequence values.
2. Verify existing clone DB owner is supabase_admin with SUPERUSER+LOGIN, PG17, postgres has public USAGE but no CREATE. Fail on any different bootstrap contract.
3. Run the generated clone install as the bootstrap role. Before the unchanged expense pre-COMMIT guards/locks/DDL, grant public CREATE only to postgres. `SET LOCAL ROLE postgres` then establishes installer identity. After all original postflight assertions, RESET ROLE returns to bootstrap and REVOKE CREATE restores the original postgres U-only ACL **before the same COMMIT**. No production grant is proposed; no ALTER DATABASE/role attributes occurs.
4. Read actual installed clone catalog in a new READ ONLY transaction using the unchanged plan's read SQL. Generate unused undo from that actual after and the explicit clone-local before with the same `prepareUnusedUndo`; no inferred after OIDs or older native after catalog is reused.
5. Execute unused undo as postgres and COMMIT. Its full actual-after guard, exact eight source/ACL/metadata checks, no-v2/no-conversion/no-rollout guard and original code restoration are reused.
6. Compare original complete catalog/default ACLs/table set+digests/sequence set+values. Verify original source remains stopped and original copied production evidence hashes unchanged. Stop the dedicated clone even on failure.

The helper saves private psql errors and safe SQLSTATE when available. If an install COMMIT occurs but a later verification fails, the clone is stopped and records retained; no production state is affected and success is not reported. Private evidence must not be pasted into chat/Git/CI. Only the safe final pbcopy result is intended for sharing.

## Verification and limits

- Python contract suite: 5 tests pass: explicit OID mapping, non-OID drift refusal, duplicate identities/OIDs refusal, transaction grant/revoke ordering with no owner change, pinned source hashes and unchanged reviewed plan/source reuse.
- PGlite PostgreSQL17 mapped-role fixture passes: original public owner and explicit USAGE-only ACL survive grant→create→RESET ROLE→revoke→COMMIT; created function owner is the mapped installer; separate owner undo COMMIT restores original state. This is explicit mapped-role fixture proof, not native proof.
- Existing reviewed expense plan's full PGlite install/actual-after/unused-undo fixture is reused; original source files and plan bytes remain unchanged.
- Native Mac helper, clone-local COMMIT sequence and production compatibility are not yet proven. Financial or non-OID drift may correctly stop before DDL. No Auth JWT is manufactured and no amount conversion occurs.

Tests from workspace root:

```bash
python3 -m unittest discover -s expense-prepared-native-rehearsal-20261020 -p test_native_contract.py
node expense-prepared-native-rehearsal-20261020/verify_public_fixture_transaction.mjs /workspace/scratch/736d0b1e377d/payroll-preservation/tool/security/fixture_dependencies/node_modules/@electric-sql/pglite/dist/index.js
```

The runtime manifest pins reused modules and inputs. The outer delivery manifest also includes the new helper, tests and this review. Publishing an immutable helper and native command is a root review step; this candidate has not been published or run.
