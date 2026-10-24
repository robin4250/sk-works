# Payroll settings entry unification

Baseline: main `1e8ceb4f8bdb745dd0be86526b63a9340e14035a`. Existing unfinished changes in this directory were preserved and completed without editing insurance display/PDF files.

## Routes and saved values

The payroll list already opens the canonical `CompanyCommonAllowanceEntryPage` behind the existing secondary protection. Company Data no longer exposes another common-allowance editor. Registered-item management is retained inside the selected, editable company scope of that canonical payroll entry. Its own server authorization remains authoritative.

The old related-rate page retains consumption tax, welfare and the four legacy rates. Its three allowance editors are removed. Simply omitting hidden fields from `save_company_rate_settings_with_units` would clear the legacy allowance slots, so this page instead uses a narrow `read_company_rate_defaults` / `save_company_rate_defaults` contract. Six expected values are compared under the existing company→rate lock order; only those six values and writer timestamps change. Existing allowance names, amounts, units and other columns remain untouched. Exact retry is idempotent, stale inputs are rejected, and neither missing RPC nor failure falls back to the old full-overwrite save. Legacy RPCs remain unchanged for other existing consumers.

The new SQL is review-only, not a migration and not production-applied. It reuses `company_common_allowance_private.authorize` and existing storage, with private security-definer implementation and public invoker wrappers. Execute privileges are revoked from PUBLIC/anon/service_role and granted only to authenticated callers; the existing authorization checks each company and editing role again. No new table is introduced. Do not merge/deploy this UI as an operational rate editor without the reviewed backend contract being available.

## Resident tax

The annual resident-tax editor already lives under payroll list → tax-rate settings. The small annual button is replaced with a clear `住民税一括入力` card near the start of the same page. The selected company, initial fiscal year, existing annual editor, individual editor and reminder panel remain unchanged. No second resident-tax storage or save path is created. Previous parent observation reported annual read/save/undo RPCs absent in production; this patch does not claim to deploy them.

## Verification

Prepared Flutter repository tests exercise the actual SDK HTTP transport, pinned actor/token, six-field payload/CAS, scope and saved-value checks, provider absence without legacy fallback, and actor change. Card tests cover normal and busy navigation. Existing rate ownership, language, settings and common-entry tests are updated to the new routes, including owner/viewer item-management visibility.

The dedicated PostgreSQL 17 fixture runs the actual candidate SQL and checks original allowance preservation, exact retry, stale/unknown-field/invalid-rate rejection, other-company and employee denial, execute grants, a real authenticated-role wrapper call, concurrent legacy-allowance retention and missing actor denial. The fixture authorization function is synthetic, so passing does not prove production roles/RLS.

Local Flutter/native PostgreSQL execution was not performed. `git diff --check` and YAML parsing were run. The dedicated CI must run Flutter analysis, related tests and native SQL before integration; production installation and iPhone checks remain incomplete.

Shared English map additions for root: `消費税・福利厚生費・旧単価` → `Consumption Tax, Welfare and Legacy Rates`. Additional display strings: `住民税一括入力`; `消費税・福利厚生費・旧単価を保存しました`; the rate-page help explains that common allowances are edited from the payroll list and not modified by this save. Shared maps are intentionally not edited here.
