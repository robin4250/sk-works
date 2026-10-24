# Minimal self-company PNG registration: bounded deployment candidate

The actual catalog-only production observation found the self-company PNG tables and APIs absent. The existing snapshot source matches the original uploaded-PNG candidate's required `md5(prosrc)=5e29407c55cfe7fa33eb7933a38d2af7`. This is a concrete missing backend; a source-connected uploader alone cannot save without it.

## Scope

Reuse `company_seal_uploaded_png_20261020.sql.review-only`: two new private relations, eight new functions, and a future-only patch of the existing snapshot function. The only candidate source correction changes four account checks from `NOT account_access_allowed()` to `account_access_allowed() IS NOT TRUE`, rejecting NULL as well as false. Existing Auth predicates, company membership, roles and financial APIs are not rewritten.

This minimum supports a raw PNG file → preview → explicit selection save → settings readback → current/saved snapshot. It does not install camera/editor/history APIs, the image-tools Master feature extension, surname approval rollout or reciprocal document approval. The existing UI shows raw PNG selection when the image-tools key is absent, so those independent features do not block this step.

Company selection defaults disabled and installation inserts no selection/version rows. This is per-company default-OFF, not a central product gate. Owner/admin explicitly saves and enables their own company PNG. Newly saved snapshots then freeze its bytes, hash, company and version; old snapshots remain unchanged. Updated clients must already support version-2 PNG snapshots before any company enables one.

## Existing mechanism reused

The preparer reuses the established canonical install/unused-restore mechanism: exact unit SHA pinning; private exclusive artifact writes; deterministic original-table locks; same-transaction catalog/row-digest observation; exact before-state guard; bounded expected additions; postflight rollback; unused restore with empty-new-table and complete original equality checks. The two artifact helper implementations are reused verbatim, without bringing the unmerged payroll-specific installer onto main.

Protected original tables are companies, company members, invoices, monthly payment certificates and payroll statements. The two new tables alone may be created. Existing snapshot/account-access/font helper definitions/attributes are captured; only the reviewed snapshot body may change. No application-row value or registered stamp bytes are output by the observer, only full-row digests and counts. These original hashes have not yet been acquired from production.

`prepare_company_png_deployment_review.py` cannot generate install from the earlier catalog-only observation. It requires a full private checkpoint. Native tests generate artifacts only from disposable synthetic originals. No production install or restore artifact has been generated or executed here.

## Verification

- Python preparation-boundary tests: passed four cases, including incomplete checkpoint refusal, original financial-row drift, changed snapshot source/owner, used-install restore refusal, single transaction and no CASCADE.
- JS syntax/Python compilation/diff checks: passed.
- Native PG17 workflow candidate: prepared, not yet executed at this checkpoint. Separate fresh services run the unchanged backend fixture and bounded install/restore fixture through the existing strict loopback/empty-database adapter.
- New native fixture covers stale-before install refusal; injected late-error full rollback; install→unused restore catalog/data equality; empty default selection; NULL account refusal; authenticated settings/OFF selection; used-install restore refusal; unchanged synthetic financial originals.
- Existing PNG/PDF/image tests remain separate codec/rendering evidence. Stubbed fixture Auth is not real JWT/PostgREST or iPhone proof.

## Before production

The integration owner must verify native CI, close any concrete failures, acquire the bounded private original checkpoint, and review the actual dependency definitions/ACL and generated install/unused-restore artifacts. Apply through the existing controlled production path, retain before/install/after/unused-restore receipts, and verify actual owner iPhone raw-PNG save→reopen→new-document PDF/print/share. Do not mark reciprocal approval, image tools, other-company access or existing finalized documents modified by this step.
