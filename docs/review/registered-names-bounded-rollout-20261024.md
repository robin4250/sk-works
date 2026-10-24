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

Python compilation and Node syntax passed locally. Native execution is pending.
The new workflow reuses the immutable 37-case PG17/real-local-PostgREST reader test, adds guarded install/postflight/restore/reinstall, rejects stale install and changed-data restore, and retains all original member/cross-company/session/privacy cases.
Auth surroundings remain synthetic; real GoTrue and production RLS are outside this proof.
Read-only production observation and offline preparation succeeded; no production deployment has been performed by this task.

The intended authenticated EXECUTE on the private SECDEF reader may add one entry to an existing security-advisor group. Compare the scoped change rather than asserting that all advisor entries must be identical.
