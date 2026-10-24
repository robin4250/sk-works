# Reciprocal business-write gate — phase C preparation

Review-only candidate based on main `22ecb36d0b15bc0fb498f3c23016508507ea5a99`. No production connection, activation, proof issuance, real seal upload, external notification or Release change occurred. Own-PNG PR1335 is already merged and production-installed with unused selection OFF; do not reinstall it or replace its current snapshot source with the older checkpoint. Counterpart PR1318 is merged, but its trade SQL remains review-only.

## Reused work / remaining order

- Phase A PR1349 exact `feb7ea8549cd435126c2621db9a94b89e36680c7` has its own Native proof for the central OFF guard and locking. This new candidate requires its exact owner-only invoker guard and an existing explicit FALSE row.
- Phase B local `ab3baa4e18de79b66e41c2861c834558b5beb8ad` already prepares both SQL issuers, Edge companion validation and dedicated proof-only toggle. It must be reused and verified by its owner; this lane does not reimplement or modify Auth/proof sources. Local preparation is not Native/real-GoTrue evidence.
- The existing financial brownfield/dependency work remains separate: invoice expense consumption/snapshot, numbering, audit/notification and route trigger atomicity must be proved before production approval rollout. The base API fixture is not that complete production writer closure.

This phase addresses the previously missing **server business-write calls to the central guard**. It is not an installer/restore package for production and must not be used as one.

## Owned changes and exact source

A deterministic Python generator verifies the canonical source blobs and emits only six exact-function replacements plus one new owner-only helper. The generated manifest records original/new bodies and complete input/output hashes. Existing four candidate sources are not edited.

The six write boundaries are prepare_document, decide, confirm_local_document, confirm_monthly_review, public-API workspace and public-API confirm. Existing actor/account/company/issuer/directional-page checks remain; a nonlocking formal accepted-link precheck precedes the feature guard, and the old locked link check still runs after it. The feature's FOR SHARE is acquired before company/document/financial locks. Cancellation keeps its existing ability to revoke the issuer's consent after disconnection, but remains centrally gated. No user-facing primitive consent workflow is introduced.

The shared helper and all replacement definitions preserve their existing owner/ACL/search-path/security mode. The output refuses a changed source/permission baseline, missing or different phase-A helper, non-FALSE initial feature, and repeated installation. It changes no central row or setter.

## OFF behavior / saved snapshots

New preparation, combined invoice/monthly confirmation and new consent decisions refuse OFF/missing/NULL. For the write-capable workspace endpoint, OFF returns an authorized existing read-only resolution with `can_integrated_confirm=false` and `reciprocal_feature_disabled`; the existing workspace response fields are retained. Ordinary assigned internal invoice approval remains on the existing early branch and receives no new seal authority.

Read-only receipt, issuer/recipient render, archive and received-workspace functions are not patched. Existing approved stamps/PDFs remain the immutable evidence of their original content/revision/seal/version/actor. The recipient's separate local-page binding for an already-approved document remains available as part of the old read workflow; it does not request or grant another stamp consent. This explicit read-workflow identity exception avoids making the first received print impossible when OFF. Unapproved new evidence remains gated at preparation/decision.

No counterpart's current stamp is fetched or generated without its established issuer consent, and no saved finalized snapshot is rewritten. The adopted PDF layout, representative fields and single-document print path are untouched.

## Test preparation and actual status

Three local generator tests pass: deterministic six-only output, unknown-source rejection before output, and unchanged read/page-identity source boundaries. All 23 canonical dependency blobs match main. `node --check` and `--check-generated` pass for the private generated fixture modules. No database was executed locally: the prior PGlite dependency is absent, and the root owner directed reuse of remote locked npm dependencies rather than installing a new local runtime.

The new wrapper reuses the exact existing SQL-role/session fixture, patching only temporary module copies. It proposes ON regression coverage for existing invoice/monthly flow, then OFF/NULL/missing refusal, actor authorization before feature checks, same six-function metadata, readonly receipt and both companies' identical archive evidence, and unchanged financial/approval/consent rows. Native-only preparation observes an actual business workspace holding the feature lock while OFF waits, then checks later operations refuse. These new runtime assertions are **not yet executed or proven**.

The fixture's central table is synthetic and its phase-A helper is the exact previously reviewed body. It does not substitute for full phase-A installation proof, Phase-B real GoTrue/Edge/PostgREST proof, actual linked-company authorization or complete production financial-trigger rollback. Owner-only fixture TRUE is only for test scenarios; the suite finishes OFF. No publicly callable toggle is added.

Remote commands, after the existing lockfile-bound fixture dependency install:

```sh
python3 tool/prepare_trade_reciprocal_business_gate.py
python3 -m unittest discover -s tool/security -p test_trade_reciprocal_business_gate.py -v
node tool/verify_trade_reciprocal_business_gate.mjs --check-generated
node tool/verify_trade_reciprocal_business_gate.mjs "$PWD/tool/security/fixture_dependencies/node_modules/@electric-sql/pglite/dist/index.js"
SKO_CONSENT_FIXTURE_URL=postgresql://postgres:fixture-only@127.0.0.1:5432/sko_document_consent_fixture node tool/verify_trade_reciprocal_business_gate.mjs "$PWD/tool/security/fixture_dependencies/node_modules/pg/lib/index.js" postgres
```

The existing authenticated fixture uses synthetic claims/session rows; real issued-token proof is still a separate stage. Runtime failures must be reported as failures, not represented by the passing source-generation tests. Production checkpoint/bounded installation/unused restore, Phase-B completion, real-company reciprocal approval and iPhone PNG selection/reopen/PDF/print verification remain unfinished.
