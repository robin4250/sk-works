# Current personnel boundary — distribution blocker

Base main `74d4c2f578e26ca1f7f21628f19a1da6b2fdeee9`. Review only. Production remains unchanged.

The root's fresh 2026-10-26 catalog matches the original, vulnerable P34 inputs:

| Target | Current evidence |
| --- | --- |
| Personnel profile SELECT | Original role-only policy, MD5 `1f1384d90020f684fa997e8fa582e8a2` |
| Family member SELECT | Original role-only policy, MD5 `ebbb5d4863aefdbb313b26d24cf61a6d` |
| Private legacy read | Original body `3dd173b3ba0768718bbc6f326ea1fb18` |
| Private write authorization | Original body `ead531bcf8b745788cd01371ac405014` |
| Actual public save | Dependency body `c11956bf0845ab725312928c2422a7ab`, unchanged |

These original policies/helpers permit a same-company manager by role while the people-management permission is OFF. Existing isolated PG17/PostgREST proofs demonstrated the direct/legacy read and actual initial-save/change-request paths; no real user or business row is impersonated/read/written by this audit. This remains a distribution blocker. Main integration of review files did not apply those SQL changes to the database.

## Reuse instead of reimplementation

Use the existing hash-pinned `tool/security/p34_atomic.py` and its exact three migrations (#1125, #1141 and existing write guard). Existing successful run `39009019393`, atomic PG17/PostgREST job `117327318684`, already proves its role matrix, identity/company/provider/master/data/ACL preservation, late rollback and restoration/reapply. Existing notification composition run `39015648825` proves selected resolver integration. Do not repeat these unchanged suites merely to attach a new date.

`prepare_personnel.py` adds a fresh exact-before wrapper: both whole policy inventories, table OID/owner/ACL/RLS and seven current dependency/target routine OIDs/full definitions/owner/ACL/config/security/volatility. It reuses the actual P34 SQL body without rewriting it. One short transaction locks both target tables with a 5-second lock wait, then checks whole-row hashes before/after. It adds no table, role, permission setting, account/provider edit, business migration or new authentication scheme. Existing public APIs, legitimate owner/admin/self/delegated-manager and existing separate approver authority remain the P34 contract.

`personnel.guarded.sql.review-only` is prepared from the root's current catalog. This is an **immediate permission change**, not an OFF install. Root must finish the private backup/recovery/administrator preservation and exact final impact review before any production action. The two policy changes and two private helper changes are committed atomically; do not deploy just the read policies while leaving the definer/write bypass open.

## Restoration is explicit, not a false unused claim

The original P34 policies/helpers do not log each read. A static catalog cannot prove that they were never used after installation. Therefore this candidate does not invent an automatic unused-removal guarantee.

Given the saved exact before snapshot and a verified exact post snapshot, the generator prepares **source-only manual emergency restoration**. It requires the complete post catalog/OIDs/definitions/ACLs to match, preserves row hashes and original routine OIDs, recreates original policies, and verifies the exact before contract. Restoration deliberately reopens the known original manager permission bypass. Normal client access must first be stopped/isolated externally, and the operator must retain a secure fallback/repair plan. Never run the old-policy restore automatically to recover availability or as an ordinary online rollback. No CASCADE or business-row undo is supplied.

The new wrapper Native test reuses only the established synthetic bootstrap. It targets new catalog drift checks, late/forbidden-DML rollback, actual manager-OFF denial with owner/admin saves preserved, exact source restoration/reapply and explicit old-gap reappearance. A passing isolated result is not proof of actual full DB/Auth/Storage archive recovery, actual OAuth/iPhone operation, every company role or all application surfaces.

Status: new PostgreSQL17 wrapper CI succeeded on exact implementation head `793514345cff449f31777588ecc54944466b34aa`: run `40283302654`, job `121441162822`, 46 checks. Main integration, production apply, actual administrator access/recovery and iPhone confirmation remain root-owned separate steps. Existing build 20 IPA is unchanged.
