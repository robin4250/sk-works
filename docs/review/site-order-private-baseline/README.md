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

`verify_composition.mjs --full` composes the twelve site modules in one outer transaction. The actor-only API namespace contains one function and no financial API endpoints. `catalog_normalized.sql` captures functions, namespace ACLs, relations, columns/defaults, indexes, constraints, triggers and RLS policies. Six injected catalog faults must reject and roll back all five new namespaces. Local PGlite currently passes **81 checks**, plus **8 Python tests** and **9 offline/scanner tests**. Native 71-check evidence belongs to the preceding 754494 revision; new exact-head Native CI is required for the additional normalization and guard work.

Canonical foreign keys necessarily add internal reference triggers to existing `public.companies` and `public.trade_companies`. These are recorded separately: exactly nine known foreign keys and two reference triggers per key, with exact parent/child columns, constraint/index relation binding, internal dependency, NO ACTION behavior, enabled state and validation/deferral properties. Existing user triggers and all other captured existing metadata must remain unchanged. An additional unknown foreign key and an injected user trigger are explicit negative cases. This is not an assertion that existing catalog rows are byte-identical after installation.

The public fixture still uses synthetic Auth rows and a synthetic company-seal helper. It does not prove real GoTrue, production application, or full-stack execution of the separately captured eight actual helper bodies. A separate private PGlite run now executes all eight captured bodies with the twelve modules, including seal-path calls and SQL guard acceptance/rejection; it passes 93 checks. This still uses synthetic Auth/company rows and PNG bytes and is not Native or live GoTrue evidence. The review-only STOP remains until Native private exact-body composition, independent review, deployment preflight and explicit production authorization are complete.


## Blocked atomic review preparation

`full-source-contract.json` pins all thirteen verbatim SQL inputs (one consent core plus twelve site modules). The actor statement has its separate pinned hash. The SQL scanner preserves all function-body text and rejects inner transaction commands. `prepare_atomic_review.mjs` is offline and never contacts a database. It rejects missing production READ ONLY before evidence, synthetic seal evidence, a non-Native exact-eight-body rehearsal, any source hash difference, a different before receipt, missing complete after catalogs, or a pre-existing new namespace. It emits only a review bundle with a deliberate STOP exception under the current HOLD; it does not emit an approved installer. No qualifying production-before/Native-eight-body-after pair is currently available, so no deployable candidate is claimed.

The guarded SQL compares a bounded existing catalog (eight prerequisites, the three formal C private functions and two legacy response functions, fifteen relations, named default ACLs and auth/private/public namespace ACLs), checks all five new namespaces are absent, then checks the exact expected existing-after and new-after catalogs before COMMIT. The expected existing-after receipt includes the narrowly allowed internal FK additions; it must not pretend the parent tables are unchanged. The before contract assumes formal C has already been prepared/applied in the separately reviewed scope; this package does not install or alter C.

Catalog normalization preserves ACL role/grantor identities and grant options, constraint/index/table binding, trigger attributes, qualification and functions. It removes raw role OIDs and MVCC/physical statistics and replaces generated internal trigger OID names with stable constraint identities. This supports review across disposable databases without allowing semantic drift. Exact RI event-to-function matching, empty trigger args/column filters, absent qualifications/transition tables and non-cloned state are verified before excluding the canonical reference additions from the unchanged-prerequisite comparison.

The full harness executes the generated SQL equality guards as well as JavaScript comparisons: exact catalogs are accepted, changed function cost is denied with SQLSTATE 55000 and rolled back. This verifies guard execution in a disposable database, not production approval or app connectivity.

References: [PostgreSQL 17 pg_trigger](https://www.postgresql.org/docs/17/catalog-pg-trigger.html), [pg_constraint](https://www.postgresql.org/docs/17/catalog-pg-constraint.html).


## Fixed reply-recovery composition

The CI harness additionally checks out PR1657 source at immutable commit `de4d4bb018e8c8ca56b0c85bde09fadebca312a4`. Its `reply-recovery.sql.review-only` is read unchanged, accepted only at SHA256 `991281df5f789e1e6a3d469dd854609a065d2a6d56db33b85a08d3cf57fd9979`, and appended inside the same outer transaction after the twelve existing site modules. No B-owned source file is copied or edited in this PR. Set `SKO_SITE_REPLY_RECOVERY_SOURCE_ROOT` to that fixed checkout to exercise thirteen site modules; omission retains the twelve-module baseline. The blocked-review builder accepts the same optional fifth positional source root and adds its exact hash to the required rehearsal receipt.

Local thirteen-module results: public PGlite **82 checks**, private actual-eight-body PGlite **94 checks**, Python **8 tests**, Node offline/scanner **10 tests**. The private thirteen-module log and catalog receipt are separate files, preserving the earlier twelve-module evidence. The run proves DDL/ACL/catalog/atomic guard composition and calls the existing eight helper paths; it does not re-prove all recovery business paths, concurrency barriers or a real-session reply delivery. PR1657's own exact-head behavior/race evidence remains a separate layer. New exact-head Native CI is required for this extension.


## Expanded existing-dependency guard (current scope)

The original nine relations covered only the eight-helper prerequisite closure. They did not cover the full site's existing `sites`, notifications, three delivery/inbox tables and master settings. `full-existing-contract.json` now extends the guard to **13 existing functions and 15 existing relations**. This is broader evidence than the earlier 81/82-check scoped runs, which remain historical results rather than proof of the expanded scope.

Exactly **nine** canonical foreign keys add **18** internal reference triggers across companies, trade companies, sites and the delivery-item table. All other existing table metadata remains checked. The one intended existing function-body change is `private.respond_site_share`: before MD5 `adf5eb7363546e9c05d34c8e780a4ce2`, after `c61612a94b05a42facfdf6b5a4c396f7`. Its complete normalized attributes remain unchanged. The public wrapper body stays `40d48b399537a5d95cead6dcc61dc264`. This closes the earlier omission where the bounded catalog did not include the intentionally changed legacy helper.

The blocked builder now captures the legacy raw attributes into the required temporary table **inside the same transaction**. The full harness uses that exact capture function on every fault-injected installation, so the generated legacy preparation SQL is exercised rather than left as an unexecuted string.

`capture_full_preflight.mjs ROOT` emits a bounded READ ONLY metadata query for this expanded contract and all five namespace-presence flags. It never connects or selects business rows. Fresh production and rehearsal receipts must use the same Native PostgreSQL 17 version; the builder rejects a missing or different version. No such qualifying actual-before/Native-eight-body-after pair has yet been produced.

Expanded local results with the fixed recovery module: public PGlite **86 checks**, private exact-eight-body PGlite **98 checks**, Python **8 tests**, Node offline/scanner **11 tests**. These retain synthetic Auth/company/PNG rows and are not production authorization or Native actual-eight-body evidence.


## Latest actual READ ONLY observation

On 2026-10-31 at 01:49:26 UTC (10:49 JST), root reviewed the complete generated 8,193-byte query (SHA256 `e948ed3036d856fbfc8ca3ffcebe0e79bd29e719e85d6dcc4c4c97327b1b6bec`) and executed it READ ONLY. The result has Native PostgreSQL **17.6**, **10 existing functions**, **all 15 existing relations**, and **all five new namespaces absent**. All eight original helper body/owner/security/config/ACL contracts still match the earlier manifest; both legacy response body hashes match their expected before values. No business rows were selected and production writes were zero. The detailed metadata stays private.

The three missing functions are formal C's `require_trade_documents_master_feature`, `require_standalone_trade_document_access` and `standalone_trade_document_registration_context`. Their source is not invalidated or rewritten: the separate formal-C scope has not been applied. The expanded atomic-review builder correctly rejects this 10-function snapshot because its baseline prerequisite is 13 functions. No projected post-C rehearsal is labeled as the actual production-before state, and no deployment approval is inferred from the READ ONLY query.


## Fixed site-history composition

PR1666's immutable source `f4c6da47e8c6bd894c920ab1d85399a4dc5da7bb` adds the owner-only `site_history_entries` read function without new tables or public grants. The harness reads that SQL unchanged from `SKO_SITE_HISTORY_SOURCE_ROOT`, requires blob `ad74648b330d6e786402a773461812c73f173e83` / SHA256 `0f9cc2f094e8146089a8cdf89f10fb0244ce5d80da239497b76d5c602285e577`, and appends it after the fixed reply-recovery source inside the same transaction. The blocked builder accepts an optional sixth positional history source root and adds the corresponding hash to its rehearsal contract.

The fourteen-module combination locally passes public PGlite **87 checks**, private actual-eight-body PGlite **99 checks**, Python **8 tests**, and Node offline/scanner **13 tests**. It retains the expanded 13-function/15-relation prerequisites, exact 9-FK/18-reference-trigger additions, sole intended legacy source transition, and all six atomic catalog fault cases. Exact-head Native CI and independent review remain separate requirements; PR1666's own successful checks are not re-labeled as this new composition evidence.

## Local Native PostgreSQL 17.6 feasibility

The official PostgreSQL 17.6 tar archive was downloaded and verified against the official SHA256 `e0630a3600aea27511715563259ec2111cd5f4353a4b040e0be827f94cd7a8b0`. Its unmodified source built and installed into an isolated task prefix; `postgres --version` and `initdb --version` both report 17.6. Missing bison/flex/m4 were obtained as individually official-hash-verified Ubuntu packages and extracted only under that task toolchain, without system package installation.

The current execution namespace maps only UID/GID 0. `initdb` correctly refuses root; non-root ownership, `runuser`, and a legitimate nested user-namespace mapping are unavailable. No PostgreSQL root guard or OS identity function was altered. No cluster was initialized or server started, and **private actual-eight-body Native execution did not occur**. A legitimate non-root isolated runner is still required. The private receipt records archive/package/binary/log hashes and the exact failures; private helper definitions were not sent to public CI.


The public Native composition service is now version-pinned to `postgres:17.6`, with an explicit runtime `server_version_num = 170006` assertion. This changes the disposable fixture engine, not production. Its extra engine-version check makes the expected Native total **88**, compared with public PGlite **87**; the public seal helper remains synthetic.
