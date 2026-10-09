# Company allowance source contract — isolated proposal

Status: **NOT DEPLOYABLE / NOT CONNECTED**. No production database, migration,
RLS policy, existing grant, payroll generation or UI was changed. The Supabase
CLI was unavailable; SQL is deliberately staged under proposals, not migrations.
Before adoption, generate a migration with the CLI, review database advisors,
verify actual schema privileges and compatibility, and coordinate the existing
company-settings writer. No feature gate is enabled by this change.

## Existing source and reuse

`company_rate_settings.allowance_1..3_name / amount_yen / unit` is the existing
company-wide source. `my_attendance_allowance_units()` already projects names
and units to workers. `save_company_allowance_units()` and the atomic company
rate saver already own administration. Site billing allowance rates and
individual extra pay are separate financial agreements; do not automatically
merge them merely because names match.

The proposal adds **extra items only** to the same company rate row. Legacy
slot name/amount/unit are never copied into extra JSON. Employee reads project
the original three slots plus extra items as one catalog. Company+slot IDs use
`md5(company_uuid || ':legacy-allowance:' || slot)::uuid`, derived identities,
not name matching or a historical backfill. Extra IDs are supplied UUIDs and
retained through rename/retirement. The legacy IDs are reserved even when a
slot is empty. Legacy editing continues through the existing company settings
path; the extra write RPC rejects those IDs. Amounts remain administrative.

Existing same-name legacy slots are not silently corrected or deduplicated.
Their distinct IDs remain visible; a later administrative cleanup is required.
No existing money is interpreted as quantity. Future daily reports must store
an allowance ID and explicit count/boolean, never derive quantity from yen.

## Mutation and reads

`proposal_read_company_allowance_labels(company_id)` requires membership in the
explicit company and returns only catalog version, stable ID, name, unit and
active status. It excludes retired extra items. It never returns unit prices,
amounts or an arbitrary JSON payload supplied by the caller.

`proposal_save_company_allowance_item(...)` requires the existing owner/admin
membership role condition for that company. Source comparison:
`20260922020000_add_company_rate_settings_management.sql` checks
`cm.user_id = auth.uid()` and `cm.role::text in ('owner','admin')`;
`20261003002700_add_attendance_allowance_display_units.sql` uses the same
condition. The proposal repeats that condition with an explicit company scope
instead of the legacy writers' `limit 1` company choice; it does not call or
modify an existing authorization helper. It accepts only count/boolean units,
nonnegative integer yen and nonblank bounded names. It rejects an extra item
whose trimmed case-insensitive name equals any other legacy/extra item,
including retired extras. Retirement preserves identity and audit history.

The existing company row must exist. A row lock plus expected version prevents
lost writes. A proposal trigger advances the version on **every** company rate
row UPDATE, including legacy RPCs and unrelated rate changes; conservative
conflicts require the caller to reload. The extra writer does not separately
increment the version. Each successful extra write logs actor, time, version,
and API-append-only before/after extra catalogs in an unexposed RLS-enabled schema.
Legacy edit audit remains the responsibility of the existing writer; this
proposal does not claim to add legacy audit or item-level payroll history.
Only the two new RPCs receive authenticated execution. No table access, anon
execution, existing helper privileges or membership scope is widened.

## Deployment stop conditions

The fixture deliberately grants no direct access to the existing rate table.
Its price-free read and audit tests cover these RPCs only, **not production
Data API exposure**. Existing table-wide SELECT/UPDATE privileges and policies
on `company_rate_settings` can automatically cover the added JSON columns.
A permitted raw SELECT could reveal extra prices, and a permitted raw UPDATE
could bypass this RPC's validation and audit (the version trigger alone is
insufficient). These must be inventoried against the actual deployed grants,
RLS policies and column privileges before any migration. This proposal leaves
all existing privileges unchanged and is therefore **not deployable** until
that exposure is resolved in a separately reviewed compatibility change.

The change log is append-only through these RPCs, not universally immutable:
there is no UPDATE/DELETE prevention trigger. Its owner or other sufficiently
privileged database role can alter history. Do not describe this as immutable
payroll evidence; finalized payroll requires its existing stronger boundary.

## Payroll boundary and remaining work

No calculation or finalized payroll record is touched. Adoption must capture
resolved ID, name, unit price, count, calculation conditions and result into the
existing finalized payroll snapshot; future catalog edits must never re-resolve
a finalized statement. Old records remain money/name snapshots and cannot be
backfilled into trustworthy item counts without independent evidence.

Still pending: production migration/privilege review; administrator pricing
read API and UI; quantity input persistence and validation; individual worker
references and family allowance logic; finalized payroll integration and its
regression checks. This isolated foundation is not completion of those features.

## Verification

Run `node tool/verify_company_allowance_catalog_proposal.mjs /absolute/path/to/@electric-sql/pglite/dist/index.js`.
Verified with PGlite 0.3.14: scoped membership, owner/admin mutation, denied anon
and raw audit reads, price-free labels, duplicate legacy/extra names, invalid
units/amounts, stale versions including old writer updates, failed writes preserving version/catalog/audit,
non-owner authenticated admin execution, same-company membership denial, legacy
ID write rejection and ID stability through rename, retirement preserving
identity, append-only API audit, and unchanged original legacy yen.

Official reference: https://supabase.com/docs/guides/database/functions
The changelog markdown endpoint was queried but the search transport rejected
its content type; no production API/version-dependent feature is introduced.
