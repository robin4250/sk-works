# Canonical publisher integration: snapshot/preview unit

Review-only preparation unit. No publish, activation, calculation, UI, help, role or product source is changed. **This unit is not a deployable legacy-inclusion fix:** placing `unit=day` legacy items into the unchanged resolver would wrongly pay every working date, so both calculation/publish readiness explicitly remain false.

## Reuse the existing product route

The existing canonical `company_common_allowance_private.publish_payroll` already supplies writer/source/timeline checks, immutable publication and request receipt, explicit start month and payroll type, current plus existing later draft recalculation, future-start boundary, manual/finalized preservation and latest effective publication inheritance. The missing company legacy slots enter at `snapshot := active_items(cid,typ)`. Do not install the separate future-policy prototype as a permanent second production route.

The new private `snapshot_plan` combines the real `active_items` with named positive legacy refs under their original ID, generation, amount and display unit. Each legacy identity requires an exact explicit `attendance_selected_distinct_dates` contract and current-name selection alias; arbitrary count 1/2 and historical alias mappings remain unsupported. A name/identity collision blocks preparation. Fresh company version/source must match. Individual amounts are not copied or overwritten.

`publication_preview` builds the canonical existing target/exclusion shape and next effective boundary. It exposes target/new-draft versus manual/finalized exclusions, identifies whether first activation is needed, and prepares a separately typed durable **publish** request contract. It never enables activation. Existing settings-save requests and publish requests must remain different types/IDs. The request JSON includes proposed legacy contract metadata and is not accepted by the unchanged public endpoint; it is a design contract for the versioned implementation, not an API ready to invoke.

## Minimum remaining implementation order

1. Extend the canonical resolver with an explicit origin/basis branch: legacy selected distinct dates; existing month/day/hour items retain their existing quantities. Derive narrowly scoped legacy-slot overlays from fresh worker settings; preserve individual priority/conflict interpretation and source classification. Never require attendance actors to have salary-view/edit authority.
2. Keep calculated rows `origin=company_common` for the existing frozen common-state reader; add `source_origin=company_legacy`, ID/generation, quantity basis and display unit. Otherwise the frozen reader currently filters out a new top-level origin.
3. Extend the normal publisher and its receipt payload with the approved snapshot/quantity contract, source dependency/version guards and all-scope preview/readback. On first use, combine **explicit administrator-approved activation** and first publication atomically. The current public UI has no first-activation entry; do not turn it on implicitly.
4. Reuse `CompanyCommonPayrollPublicationRepository`, the current type/start-month/confirmation panel, and individual common-card `read_conditions.company_common`. Add clear included/excluded/unresolved counts and reasons. Keep registration/save and applying to unfinished salary visibly distinct. Complete durable pending request reconciliation after unknown commit.
5. Retire the alternative review prototypes from the proposed deployment set, complete native concurrency/real-token/public-attendance tests and screen/PDF/iPhone checks. Only one canonical product publication path may calculate these amounts.

## Evidence / boundaries

The new fixture verifies legacy snapshot inclusion under original IDs/generations/rates/units, missing/duplicate/unsupported quantity decisions rejected, source conflict rejected, first activation shown as approval-pending, and complete financial/settings/activation/publication state unchanged by preparation. Synthetic public inputs and separate private-rate inputs use synthetic IDs. No real production scope is published.

The scope preview is preparation-only and has no final bound/source-closure/concurrency guarantee yet. Interpretation receipts, arbitrary 1/2 quantity persistence and first activation approval UI remain unfinished. Do not call this the user's completed “all unfinished salaries from the start month” requirement.
