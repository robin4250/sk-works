# Registered company allowance names: bounded rollout candidate

The original API candidate is unchanged, SHA256 `8af1ecca42cb16ae9223206f347cd1ed778da58f1d208ac79762e9e9350f583d`.
This adds an offline installer generator and a separate Native lifecycle proof.
It neither registers allowances nor publishes/activates payroll prices.

## Exact-state boundary

- Two absent new routine identities, three existing auth/session helper sources and attributes.
- Seven protected relations: five registered-definition sources, companies and company members.
- Table owner/ACL/RLS/column/default/OID metadata and opaque full-row count/SHA256 fingerprints.
- Existing schema usage only; no schema/table grants or auth configuration changes.
- Seven relations locked in observed OID order using SHARE, 5-second lock and 30-second statement timeouts.
- Before and predicted after inventory compared in the same install transaction; expected new body MD5, owner, ACL, search path, volatility, security and effective role execution are checked.
- An independently generated read-only postflight performs the same after comparison.

## Restore limitation

Names reads do not write a use counter. This candidate does **not** prove that a reader has never been called.
The generated restore requires the operator to withdraw client use first, and then enforces the exact installed state and unchanged protected source data. Changed registration data, helper/source/ACL/catalog changes refuse restoration. It drops only the public wrapper followed by its private implementation and checks the original inventory; no CASCADE or row mutation is generated.

## Verification

Python compilation and Node syntax passed locally. Native job `120828627322` on PR1362 exact head `262c4978644f775bd3dbd3f36dd0f3c9583c4adc` passed **44 checks** (2026-10-24 08:42 UTC). The original 37-case reader proof is retained, with seven lifecycle/guard checks added.
The new workflow reuses the immutable 37-case PG17/real-local-PostgREST reader test, adds guarded install/postflight/restore/reinstall, rejects stale install and changed-data restore, and retains all original member/cross-company/session/privacy cases.
Auth surroundings remain synthetic; real GoTrue and production RLS are outside this proof.
Read-only production observation and offline preparation succeeded. Fresh root before observation equals the task observation; installer SHA256 remains `ea0a17931138c910ae1847c15a75a278182926178e151d42164b3cea00463ac8`. The exact-seven-relation generator hardening changes no output for this valid observation. Three offline negative cases (already-present API, missing schema usage, replaced protected relation) also refused generation. No production deployment has been performed by this task.

The intended authenticated EXECUTE on the private SECDEF reader may add one entry to an existing security-advisor group. Compare the scoped change rather than asserting that all advisor entries must be identical.


## Refused production attempt: catalog rendering context

The first root install attempt of `ea0a1793…` was refused by its after guard and rolled back. Root independently confirmed both new routines absent and the full original inventory/data unchanged. A read-only empty-search-path observation identified exactly two differing catalog strings on production's `public.company_members.role`: `app_role` became `public.app_role`, and its default gained the same qualification. The API's `SET LOCAL search_path=''` changed `format_type`/`pg_get_expr` rendering context; routine source, ACL and application data were unchanged. The initial Native fixture had a text role and did not cover this custom-enum case.

The fix does not remove or relax these comparisons. `prepare.py --observation-sql` now emits `BEGIN READ ONLY; SET LOCAL search_path=''; SELECT inventory; ROLLBACK`, the inventory records that context, and the generator rejects snapshots outside it. Install, postflight and restore also explicitly use the same transaction-local empty context. The original API SQL remains unchanged. The Native lifecycle adds production's custom enum/default, verifies the fully qualified snapshot and rejects the old context. Revalidation is pending.

Normalized fresh preparation: installer SHA256 `6696d1402debb0b19866dca1f3bc55fa82723aa979e219f61ebe3491dcc0e9c0`; original API SHA remains `8af1ecca42cb16ae9223206f347cd1ed778da58f1d208ac79762e9e9350f583d`. No retry or production deployment was performed by this task.
