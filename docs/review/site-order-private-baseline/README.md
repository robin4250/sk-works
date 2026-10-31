# Minimal private site baseline — review preparation

This is an offline review package, **not an install-ready baseline**. Production HOLD, new order feature OFF, and individual exemptions OFF remain unchanged. No deployed helper, company row, seal, original, session or grant was modified.

The site stack needs the canonical standalone private consent core and one current-account actor. It does not need the financial confirmation API's public RPCs, invoice/monthly adapters, parent-link tables or permissive fixture replacements. `build_review.py` pins both canonical source files by SHA256, copies the entire original consent source without editing its bodies, and extracts exactly one `actor()` statement with a matching body MD5. It emits separate review fragments plus a STOP file, never an atomic production installer.

The original `parent_binding` still raises `0A000`; `linked_view_allowed` still returns false. Manager-purpose adaptation belongs to the existing reviewed site module. Do not weaken those denials to satisfy a fixture. Existing formal C source and its reviewed private capsule are untouched. In particular, C's standalone helper requires authenticated EXECUTE through its invoker wrapper; no private default-ACL leak is inferred from public-schema defaults.

## Actual evidence and limits

Two catalog-only, READ ONLY queries captured eight current helper bodies and relation column/constraint metadata on 2026-10-31. `manifest.json` records body MD5 and selected properties, without publishing full private captures. These are existing-helper fingerprints, not a complete production compatibility proof. The seal snapshot closure includes an invoker helper; treating every prerequisite as SECURITY DEFINER would be wrong. `actor()` only checks session existence; callers still require the real C reauthentication/purpose guards. Do not claim this actor alone verifies session expiry or full site authorization.

`capture-contract.sql` is the next bounded catalog-only review query, covering function properties/ACL, relation defaults/constraints/indexes/triggers/policies and default ACLs. It was executed once as READ ONLY: eight helpers, nine relations, 27 default-ACL entries, and both new namespaces absent. No business rows were selected. Its output contains no business row selection; private captures must remain private. OID-dependent catalog values require normalization for comparisons, not blind cross-server equality.

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

The source tests verify extraction and drift rejection; separate catalog tests reject body, ACL, RLS, trigger, policy and default-ACL drift. They are not database composition, live Auth, delivery, iPhone installation or real-user evidence.

## Composition evidence layers

The public `verify_composition.mjs` extracts seven catalog-matching generic helpers, using four existing tracked sources and three source-only generic Auth/barrier definitions. It preserves the formal C source byte hash, installs canonical standalone consent plus actor only, then the actual site artifact and manager modules. Local PGlite: **18 checks passed**. These include seven body checks, unchanged C catalog, one actor/no financial RPCs, unchanged deny-adapters, feature OFF denial, manager live-SID success and expired SID/banned/anonymous/account-restricted denials. Its company-seal snapshot function stays the **synthetic formal C fixture**, and its Auth identities/rows/tables are synthetic. The published minimal 18-check version passed both Native PostgreSQL and PGlite CI; that result does not cover the new full composition.

Separately, a private experiment used all eight current catalog-captured bodies unchanged. The first pass had **31 checks = existing 23 ACL-composition checks + eight MD5 comparisons**; this proved loading/body equality, not eight runtime paths. A follow-up private experiment had **30 checks**: seven generic source checks, eight full captured-body checks, five structural composition checks, six SID/account/OFF behavior checks and four seal-path checks. All eight bodies were called: Auth uid/jwt through C, account/restriction/barrier/reauth through valid and invalid SID cases, uploaded snapshot/document snapshot through disposable PNG bytes, and font predicate directly. The seal paths checked uploaded snapshot success, matching frozen name, supported-font predicate and changed-name `40001` rejection. Stored PNG bytes and company names were disposable synthetic values; image decoding, unsupported font paths, every procedural branch, real GoTrue identity and production business rows were not tested. Private source capture containing a fixed production identifier is not published. This evidence remains separate from the seven-body public CI.

The offline existing-catalog comparator was self-compared against the single captured receipt to validate parsing, not against a real post-deployment capture. It compares all captured properties, including relation indexes/defaults/triggers/policies and helper ownership/ACL. A drift report stops review rather than printing private definitions. Native catalog physical metadata may change naturally and requires review. New baseline objects still need their own full post-catalog receipt; this existing-prerequisite guard explicitly does not prove their correctness.


## Full atomic composition (additional review)

`verify_composition.mjs --full` composes the twelve site modules in one outer transaction. The actor-only API namespace contains one function and no financial API endpoints. `catalog_normalized.sql` captures functions, namespace ACLs, relations, columns/defaults, indexes, constraints, triggers and RLS policies. Six injected catalog faults must reject and roll back all five new namespaces. Local PGlite currently passes **71 checks**, plus **8 Python tests** and **5 transaction-scanner tests**. New Native CI evidence is required for this exact revision.

Canonical foreign keys necessarily add internal reference triggers to existing `public.companies` and `public.trade_companies`. These are recorded separately: exactly five known foreign keys and two reference triggers per key, with exact parent/child columns, constraint/index relation binding, internal dependency, NO ACTION behavior, enabled state and validation/deferral properties. Existing user triggers and all other captured existing metadata must remain unchanged. An additional unknown foreign key and an injected user trigger are explicit negative cases. This is not an assertion that existing catalog rows are byte-identical after installation.

The public fixture still uses synthetic Auth rows and a synthetic company-seal helper. It does not prove real GoTrue, production application, or full-stack execution of the separately captured eight actual helper bodies. The review-only STOP remains until private exact-body full composition, independent review, deployment preflight and explicit production authorization are complete.
