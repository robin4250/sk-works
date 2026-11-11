# Distribution OFF review capsule v1

This is an offline, non-executable preparation aid. It does not connect to a database, assemble SQL, register a URL, send an invitation, change flags, or grant production approval. Both output booleans `deployable` and `approval` are always false; `execution` and `sql` are null. A matching synthetic receipt never establishes production readiness.

The installer is reused byte-for-byte from fixed source commit `48d345ddd52f5cca0166c2d6545a07ecb08fe8d4`, path `docs/candidates/app_distribution_off_install_20261020.sql.review-only`, SHA256 `b45d269b22e58a6e9a4750d6398a6139ee854c1c820ed376d7e3c8a87ae49e95`. This tool cannot replace its settings, history, dependency, atomic before/post, or unused-only undo protections. The original installer, undo, dispatcher and existing RPC source remain unchanged.

## Inputs and refusal

Call `qualify(installer_bytes, evidence)` with an exact dictionary containing:

- `baseline` and `current`: all 13 catalog rows with the exact fields in `PROFILES`, plus `oid`, `schema_oid`, `owner_oid`. ACL entries additionally contain `grantee_oid` and `grantor_oid`. The eight existing signatures must match pinned source definition/body hashes, attributes and observed effective ACLs. Five new signatures must be absent. Current identity metadata must exactly equal the independently captured baseline. No auto-refresh occurs.
- `overloads`: the complete current signature list for the 13 names, with no unexpected, missing or duplicate overloads. The caller must obtain this enumeration, not infer it from direct signature lookup.
- `settings`: exactly four boolean predicates: `settings_singleton_exact_one`, `invitations_off`, `public_off`, `legacy_url_empty`. Every value must be the boolean true. Zero/multiple rows, NULL, false, strings or integers fail. The qualifier does not read or output URLs.
- `preservation_reference`: a private sealed before/post reference with lowercase SHA256, scope `private-before-post-settings-history-dependencies`, and `verified:false`. It is a reference only: this tool does not inspect or validate its contents. Missing references fail; supplied references remain explicitly blocked and unverified.

Never substitute fixture metadata for missing production input. Catalog completeness, project identity, freshness and the preservation reference need separate private verification. The metadata receipts contain deployment identity details and must stay private; synthetic test identities alone are committed. The fixed hashes are source-derived and contain no business rows or URLs.

## Allowed future delta, not an execution plan

The review output lists only the existing private dispatcher's body replacement, five new functions and two new private tables. Existing public wrappers, initial-registration RPCs, definitions, owners, ACLs, company-specific URLs, settings and histories must remain unchanged. Observed legacy service-role EXECUTE grants are preserved, not silently removed. Unknown role names, grants, source hashes, attributes, overloads, invalid OID types or identity drift from the captured baseline refuse qualification. Positive OIDs matching baseline/current do not prove their live namespace or non-owner role mapping: that mapping requires separate private catalog verification and remains blocked. The output is deliberately insufficient to deploy: the complete immutable installer and separately reviewed atomic guards are still required.

If an OFF/empty precondition is unmet, stop. Do not clear a saved URL, force a flag OFF, or relax the installer to satisfy it. After configuration or use, unused-only undo is not a recovery mechanism: preserve rows and histories and prepare a separately approved stop/reconciliation procedure. Result-unknown operations must not be blindly replayed.

## Verification

From a full checkout:

```sh
python3 -m unittest discover -s tool/distribution_off_capsule_v1 -p 'test_*.py' -v
```

For an isolated source snapshot, `DISTRIBUTION_TEST_SOURCE_ROOT` may point at a checkout containing the immutable installer. Tests use synthetic metadata, test mandatory OFF/empty predicates and metadata refusals, and confirm that even accepted review output cannot authorize or execute deployment. They provide no live deployment, Auth, invitation delivery, TestFlight state, or iPhone evidence.
