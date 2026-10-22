# Common allowance legacy publication candidate

Review only. This isolated prototype is not deployed, granted, integrated, or ready for production activation. It changes no existing publisher, domain/UI, source payroll row, company amount, or identity. Historical PR #1315 is outside this scope.

## Connection being restored

The existing settings page preserves legacy company allowance identities and rates. The publication builder reads only new active items, so legacy slots are absent from its effective snapshot. Separately, individual legacy slots depend on attendance name selections. Publishing company daily amounts without reconciling these old individual slots could add both amounts.

The candidate proposes legacy positive slots using the existing identity and generation. A per-worker plan requires an explicit identity/generation/individual-slot binding and source hash. A confirmed same-rate inherited individual slot becomes zero only in the effective calculation JSON; its stored value is preserved. Unmatched company items can be explicitly inherited with a null individual slot. Names are ambiguity detectors, not permission to overwrite stored values.

Different individual rates, duplicate names, overlap with individual unit/custom earnings, and legacy payment on a nonworking date remain blocked. Manual/finalized statements remain blocked. Changed company/worker source invalidates the supplied plan.

## Validation completed

The disposable PGlite fixture uses existing saver, identity lifecycle, payroll refresh, attendance insert/edit triggers, common resolver, and finalization SQL. Public defaults contain synthetic names and rates only. External private fixture data are not saved in this repository; the fresh observed two company rates were also exercised with synthetic company/worker IDs and synthetic attendance in a separate run.

Both synthetic and fresh-rate runs passed:

- Two legacy snapshot items and explicit binding requirement.
- Effective inherited slot removal without original settings mutation.
- Positive work date daily common amount, checkout-equivalent insertion, and edit-trigger recalculation.
- Legacy selected versus unselected attendance has equal gross: no inherited-slot double addition.
- Repeated refresh retains equal gross; gross minus deductions equals net.
- Duplicate individual names, differing individual rate, custom earning overlap, and stale worker hash rejected.
- Actual finalization preserved across later refresh and plan rejected finalized scope.

These are actual-rate/synthetic-attendance results, not a clone of production attendance or proof of production PDF rendering. The fixture's local baseline schema omits some current source settings fields, which are deliberately not injected as unsupported columns.

## Explicit fixture adapter limitation

To exercise the missing connection without editing product code, the fixture alone stores the approved effective JSON in a disposable schema, inserts a disposable publication, and wraps the existing augmenter. This demonstrates the calculation contract. It does not supply production persistence, authorization, publication UI, or an atomic activation workflow.

## Remaining completion work

1. Persist identity-bound per-worker inheritance/override decisions with version/CAS and a preview of every affected unfinished scope. Resolve differing individual settings explicitly.
2. Integrate the reviewed snapshot and calculation overlay into the single owned publisher/resolver, with activation plus first publication in one transaction and request reconciliation after unknown COMMIT.
3. Keep automatic legacy identity generation changes, scope/permissions, locks, excluded/manual/finalized scopes, and individual settings changes fail-closed. Review source dependency closure.
4. Native PostgreSQL concurrency/RLS/JWT integration and UI/help validation. Do not assume PGlite proves these.
5. Apply the selected current month, read back actual statement components, then validate screen/PDF and Release on the administrator iPhone.

No production query, schema operation, remote call, or write was performed by this fixture. No GitHub push was performed. Existing past-month bulk candidate was not altered.

## Repository-relative reproduction

All source dependencies use paths inside the same checkout. The existing main helper `tool/payroll_scope_fixture_setup.mjs` is reused unchanged. `common-legacy-dependencies.json` records the 37 dependency blob IDs independently verified against main `dcfadfb89282de97aabfbbb9e38fb91fec621941`; no helper needs copying into product main.

Run from a checkout containing those main files plus this candidate:

```sh
node tool/verify_company_common_legacy_publication.mjs "$PWD/tool/security/fixture_dependencies/node_modules/@electric-sql/pglite/dist/index.js"
```

The dedicated workflow exercises synthetic defaults on PGlite and a fresh loopback-only PostgreSQL 17 database. Its database password is for the disposable service, and it uses no Supabase credentials or private snapshot. Native execution is proposed in CI and has not yet been run locally. This fixture does not claim two-connection concurrency or actual-JWT coverage.
