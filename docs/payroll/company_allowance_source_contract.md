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

## Repository-only privilege and compatibility inventory

Reviewed source at `c6b51faa` (proposal base), not the deployed database.
Searching all committed migrations found the following relevant definitions;
no later direct table/column grant or table policy for `company_rate_settings`
was found. That is source evidence, not proof of effective production ACLs.

| Source | Surface | Repository behavior |
| --- | --- | --- |
| `20260922013000_add_admin_initial_setup_wizard.sql` | Rate table | RLS enabled; `REVOKE ALL ... FROM anon, authenticated`; no SELECT/UPDATE policy defined for this table. The statement does not itself revoke any separately granted PUBLIC privilege. |
| Same migration | `save_initial_company_rates` | SECURITY DEFINER; owner/admin membership; explicit legacy-column upsert; authenticated EXECUTE, PUBLIC/anon revoked. Does not write extra JSON. |
| `20260922020000_add_company_rate_settings_management.sql` | `company_rate_settings_state` | Admin/owner-only money-bearing fixed-field JSON read; authenticated EXECUTE, PUBLIC/anon revoked. |
| Same migration | `save_company_rate_settings` | SECURITY DEFINER; owner/admin membership; fixed legacy-column upsert; authenticated EXECUTE, PUBLIC/anon revoked. Does not overwrite unspecified extra JSON on conflict. |
| `20261003002700_add_attendance_allowance_display_units.sql` | State read replacement | Preserves admin/owner check and fixed price/name keys; adds three unit fields, not generic `to_jsonb(rate_row)`. Added columns are not automatically emitted. |
| Same migration | `my_attendance_allowance_units` | SECURITY DEFINER; signed-in membership; name-to-unit object only, no yen; authenticated EXECUTE, PUBLIC revoked. |
| Same migration | `save_company_allowance_units` | SECURITY DEFINER; owner/admin membership; only unit columns plus updater/time are written; authenticated EXECUTE, PUBLIC revoked. |
| `20261003006000_harden_device_review_rpcs.sql` | Units read/save EXECUTE | Explicit anon revocation and authenticated grants; no rate-table grant. |
| `20261008043823_atomic_company_rate_and_allowance_units_save.sql` | Combined saver | SECURITY INVOKER wrapper around the two checked savers; authenticated EXECUTE, PUBLIC/anon revoked; one transaction. |

Under the repository's explicit rate-table ACL/RLS setup, a general worker has
no intended direct table price read or JSON UPDATE route. The worker units RPC
returns no prices. The administrative state RPC intentionally returns prices
only after its role check. These are **expected source-level outcomes**; PUBLIC
ACLs, role inheritance, deployed policies/default grants, service-role use,
manual changes and exact installed function bodies remain unverified.

The current Flutter company settings repository loads the state RPC and saves
through the combined saver. `CompanyRateSettings.fromMap` recognizes only the
three explicit name/amount/unit slots. It does not deserialize the complete
rate row or directly update the table. Therefore added columns alone should
preserve that data shape and leave extras untouched, but the existing screen
will neither show nor administer extra items. The attendance-sheet repository
continues using `my_attendance_allowance_units`; it will not discover extras
until deliberately migrated to the ID-based labels contract. No runtime UI
compatibility or full database replay was tested by this documentation review.

### Minimum compatible adoption conditions

1. Keep existing rate table and its RPC-only access intention. Inspect effective
   anon/authenticated/PUBLIC and inherited privileges before deciding whether
   any separately reviewed privilege change is needed. Never grant workers table
   access merely to read labels. Keep the price-free dedicated read boundary.
2. Preserve fixed legacy state/save shapes for older clients. Add a separate,
   explicitly scoped admin catalog price read for new clients; do not append
   amounts to a worker RPC. Bind new editors to explicit company ID and version.
3. Enforce catalog name uniqueness in **both write directions**. The proposal
   rejects extra names matching existing slots, but an unchanged legacy saver
   can later rename a slot to an extra name. Version advance detects staleness,
   not that uniqueness violation. Adoption requires a separately reviewed
   shared validation boundary covering initial/rate/unit writes and direct
   privileged writes as appropriate; do not enable extras until it exists.
4. Treat combined legacy save as two row updates: the conservative trigger
   advances version twice. New callers must reload the final version after
   save, never infer that every operation increments by exactly one. A fully
   unified future saver must retain old-client transaction behavior.
5. Keep legacy company+slot IDs derived and extras' UUIDs stable. A renamed
   legacy slot keeps identity; clearing then repurposing a slot also reuses that
   slot identity. Before usage records reference those IDs, define an explicit
   replacement/retirement policy so old usage is not reinterpreted. Never bind
   historical attendance solely by its former display name.
6. Preserve independent site billing agreements and employee-specific extras.
   Introduce references only where the company common allowance is intended;
   do not silently copy prices or resolve identical strings across domains.
7. Integrate finalized payroll snapshots and quantity storage before production
   use. The isolated proposal currently proves neither payroll computation nor
   adoption of additional entries by existing screens.

### Read-only production verification needed before a migration

The following inspection is illustrative and has **not** been executed against
production. It changes no ACL, RLS or data. Effective role privileges, individual
column grants, role membership and function definitions must be evaluated
alongside configured Data API exposure and actual user-context reads/writes.

```sql
select relrowsecurity, relforcerowsecurity, relacl
from pg_catalog.pg_class
where oid = 'public.company_rate_settings'::regclass;
select role_name,
       has_table_privilege(role_name, 'public.company_rate_settings', 'SELECT') as can_select,
       has_table_privilege(role_name, 'public.company_rate_settings', 'UPDATE') as can_update
from (values ('anon'), ('authenticated')) as roles(role_name);
select grantee, privilege_type, column_name
from information_schema.column_privileges
where table_schema = 'public' and table_name = 'company_rate_settings';
select polname, polcmd, polroles,
       pg_get_expr(polqual, polrelid) as using_expression,
       pg_get_expr(polwithcheck, polrelid) as check_expression
from pg_catalog.pg_policy
where polrelid = 'public.company_rate_settings'::regclass;
select r.rolname as granted_role, m.rolname as member_role
from pg_catalog.pg_auth_members am
join pg_catalog.pg_roles r on r.oid = am.roleid
join pg_catalog.pg_roles m on m.oid = am.member;
select n.nspname, p.proname, p.prosecdef, p.proacl, p.proconfig,
       pg_get_functiondef(p.oid) as installed_definition
from pg_catalog.pg_proc p
join pg_catalog.pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname in (
 'company_rate_settings_state', 'save_initial_company_rates',
 'save_company_rate_settings', 'save_company_allowance_units',
 'my_attendance_allowance_units', 'save_company_rate_settings_with_units'
);
```
