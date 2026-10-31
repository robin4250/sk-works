# Minimal private site baseline — review preparation

This is an offline review package, **not an install-ready baseline**. Production HOLD, new order feature OFF, and individual exemptions OFF remain unchanged. No deployed helper, company row, seal, original, session or grant was modified.

The site stack needs the canonical standalone private consent core and one current-account actor. It does not need the financial confirmation API's public RPCs, invoice/monthly adapters, parent-link tables or permissive fixture replacements. `build_review.py` pins both canonical source files by SHA256, copies the entire original consent source without editing its bodies, and extracts exactly one `actor()` statement with a matching body MD5. It emits separate review fragments plus a STOP file, never an atomic production installer.

The original `parent_binding` still raises `0A000`; `linked_view_allowed` still returns false. Manager-purpose adaptation belongs to the existing reviewed site module. Do not weaken those denials to satisfy a fixture. Existing formal C source and its reviewed private capsule are untouched. In particular, C's standalone helper requires authenticated EXECUTE through its invoker wrapper; no private default-ACL leak is inferred from public-schema defaults.

## Actual evidence and limits

Two catalog-only, READ ONLY queries captured eight current helper bodies and relation column/constraint metadata on 2026-10-31. `manifest.json` records body MD5 and selected properties, without publishing full private captures. These are existing-helper fingerprints, not a complete production compatibility proof. The seal snapshot closure includes an invoker helper; treating every prerequisite as SECURITY DEFINER would be wrong. `actor()` only checks session existence; callers still require the real C reauthentication/purpose guards. Do not claim this actor alone verifies session expiry or full site authorization.

`capture-contract.sql` is the next bounded catalog-only review query, covering function properties/ACL, relation defaults/constraints/indexes/triggers/policies and default ACLs. It is **not yet executed by this package**. Its output contains no business row selection; private captures must remain private. OID-dependent catalog values require normalization for comparisons, not blind cross-server equality.

Open gates before an installation candidate:

1. Capture and independently review the complete current relation/helper/default-ACL contract.
2. Locate the committed source for each actual helper and prove exact body equality. Disposable Auth/user/company tables remain synthetic even when function bodies match.
3. Compose formal C plus this minimal core with the real site modules using actual helper bodies; no permissive parent or linked-view substitutions. Validate native PostgreSQL as well as the isolated fixture.
4. Review source/hash/owner/ACL/RLS/immutability, transaction boundaries, before/after receipts and recovery conditions. Do not strip transaction keywords by regex to create an atomic installer.
5. Obtain explicit scoped production approval. Code or fixture success does not lift HOLD.

Run offline source checks:

```
python -m unittest discover -s docs/review/site-order-private-baseline -p 'test_*.py' -v
python docs/review/site-order-private-baseline/build_review.py --output /tmp/sko-baseline-new-review-directory
```

These four tests verify source extraction and drift rejection only. They are not database composition, live Auth, delivery, iPhone installation or real-user evidence.
