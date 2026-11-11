# Company seal: read-only production preflight

Observed on 2026-10-09 around 10:45–10:51 JST. Source checkpoint:
`b8879d675f2a2204dcfc4baf00859ea80d63f523` (#814 merged). #816 is
separate source work. This is a point-in-time observation, not deployment approval.
Only catalog SELECTs, aggregate counts and definition hashes were read. No company
names, person IDs, payroll amounts, document contents or credentials were returned.
No DDL, DML, financial refresh, RPC mutation, role grant or production backup ran.

**Correction from a fresh read-only follow-up around 13:40 JST on 2026-10-09:** the earlier
claim that certificate canonical math was not deployed was incorrect. It relied
on the repository migration number instead of reconciling the deployed ledger
and full function definitions. The deployed ledger contains
`20261008041946_certificate_canonical_snapshot_math`; its three current function
bodies match the repository `20261008035432_certificate_canonical_snapshot_math.sql`
byte for byte. Do not apply that repository migration again to align numbers.
This correction does not apply any migration or establish production operation
of the new company-seal or agreement features.

An independent repository-side comparison of the protected function-only export
also verified all three bodies. No real document rows or the exported definitions
are included here. Body SHA256 values (not whole-function presentation hashes):

| Function | Matching body SHA256 |
| --- | --- |
| `public.payment_certificate_detail_rows` | `4e389cdfd63f56b57e13d71be207d866596ffa965f6421847665fcb16154c8f2` |
| `private.certificate_calculation_rows` | `ff36d45c5600e8ede1414080941c773fce3f62e7645f03f7b283866bf26f1a66` |
| `private.refresh_automatic_payment_certificate` | `60b075423158c170c84ae8e510a2ac084f22125cc893f5943420a33378683b0e` |

## Original observed state (before the later application)

- `companies.name`: text NOT NULL; `company_seal_enabled`: boolean NOT NULL,
  default true; `updated_at`: timestamptz NOT NULL. The new
  `company_seal_style` column is absent.
- Companies: 2; blank registered names: 0; existing seal ON: 2. No names were read.
- Invoices: 2 rows; payroll statements: 2 rows; payment certificates: 0 rows.
  All three have zero `company_seal_snapshot` keys. These counts are not backups.
- New style RPCs, the Reisho coverage helper, document snapshot helper and
  `zz_company_seal_snapshot` triggers are absent. Existing ON/OFF RPCs remain.
- `companies`, `invoices`, `payment_certificates`, `payroll_statements` have RLS
  enabled, FORCE RLS false and owner postgres. Existing noninternal triggers are
  enabled (`O`); no new trigger-name collision was observed. No policies changed.
- Company invoice refresh is `AFTER UPDATE OF tax_rate`; a style-only update
  does not invoke that specific trigger. This is not a claim about every trigger.

## Original dependency review and corrected identities

The existing ON/OFF migration is deployed as
`20261008082754_company_seal_visibility`, while the repository file is
`20261008072619_company_seal_visibility.sql`. The column and RPCs already exist.
Do not reapply the older repository migration or rename migration history to make
the numbers match. Reconcile using definitions and the deployed ledger.

1. #814 `20261009011357_company_seal_aoyagi_style.sql` is not deployed. Its
   existing-style-column guard should pass in the observed state; it requires the
   existing account-access helper, company columns and company membership model.
   Defaults must remain legacy; applying it must not select a new style for users.
2. #816 `20261009012730_company_seal_document_snapshots.sql` requires step 1 and
   the saved mutual-payment document function. That function and the private
   agreement rollout/proposal/document tables are absent in production.
   #791 `20261008201215_site_payment_agreement_staged.sql`, followed by
   #797 `20261008212855_site_payment_company_snapshot.sql`, are separate undeployed
   dependencies. Their migration guards and business dependencies need their own
   deployment review. Keep rollout gates OFF; do not enable them to satisfy a seal
   migration. Applying #816 directly now would fail at the missing function.
3. Certificate canonical math is already deployed under ledger identity
   `20261008041946_certificate_canonical_snapshot_math`, corresponding to repository
   `20261008035432_certificate_canonical_snapshot_math.sql`. Fresh full-definition
   comparison found byte-identical bodies for `payment_certificate_detail_rows`,
   `certificate_calculation_rows` and `refresh_automatic_payment_certificate`.
   Signatures, arguments, return types, STABLE/VOLATILE attributes, security-definer
   flags and search paths also match. `pg_get_functiondef` presentation differences
   are formatting, the trailing semicolon and explicit default SECURITY INVOKER;
   they do not establish a different calculation. Keep the already deployed
   canonical functions and verify fresh ACLs/owners and final seal patch anchors.
   Do not reapply the math migration or rewrite history. A matching definition
   still does not prove every live financial or device case is complete.

No dependency above was applied by this preflight. #809 personal surname seals are
also separate from company seal storage and require their own deployment checks.

## Reviewable preparation sequence and side effects

This sequence describes a future reviewed deployment; it is **not an instruction
to apply migrations now**. The protected backup location has not been selected
by the operator, and no protected backup has been acquired.

| Stage | Prerequisites / stop condition | DDL and later-operation effects |
| --- | --- | --- |
| Certificate math, repository `20261008035432`, deployed ledger `20261008041946` | Already deployed and full definitions reconciled. Recheck owners/ACLs and exact refresh anchor before the final seal patch; stop if they differ. Do not repeat the migration. | No replacement or recalculation is required by this preparation. Existing normal refresh can change automatic draft amounts/details/revision or delete an attendance-empty automatic draft; manual/finalized rows are excluded. Historical detail reads without frozen rows return recorded gross amounts. Those existing behaviors are separate from applying the new seal DDL. |
| Agreement base, `20261008201215` | Accepted-share and company-connection schema, company/membership/site data model and account helper. Stop on existing new-object names or mismatched referenced columns/FKs. | Adds private rollout/proposal/confirmation/document tables, RLS and narrowly authorized RPCs. No existing financial-row writes, refresh invocation, trigger or cron installation. Gates default OFF and no rows are enabled. A later saved-document RPC can INSERT a snapshot after both confirmations; do not call it as a production installation check. |
| Agreement company snapshot, `20261008212855` | Base agreement objects, company postal/address/phone/fax/ON/OFF fields. | Replaces only the saved-document function's new-snapshot branch with v2 contact/ON/OFF fields. No top-level snapshot creation/backfill; existing saved JSON returns unchanged. |
| Style settings, `20261009011357` | Existing ON/OFF/account helper and exact-company admin model; new style column/functions must be absent. | Adds legacy-default style storage and restricted RPCs; no style-selection DML or cron installation. A later save changes only style/updated_at. Existing data and ON/OFF remain. |
| Document snapshots, `20261009012730` | Previous agreement v2 and style objects; reviewed generator anchors exactly once in the already deployed canonical math functions. | Adds three BEFORE INSERT/UPDATE snapshot triggers and patches five existing functions. No top-level financial-row UPDATE or refresh. Later new documents receive saved metadata; existing rows retain the original key or original absence. Reapplying the unpatched math migration afterwards would remove the comparison-before-seal protection, so stop instead. |

The required chains are agreement base → agreement v2 → document snapshots and
style settings → document snapshots. The independent certificate math prerequisite
is already deployed; preserve it rather than reinstalling it. Preparation is now
fresh canonical-function/ACL/anchor verification → agreement base → agreement v2
→ style → document snapshots, with agreement rollout gates OFF throughout. Never
apply an unreviewed broad migration batch just because numeric filenames sort
before these files. Style alone permits trial selection/save but its getter lacks
`document_snapshot_version`; the UI therefore keeps document integration false.
Do not present that partial deployment as completed three-document support.

Additional catalog-only checks found all 30 named dependency columns present
across the existing company/share/delivery/connection/site/financial-setting
tables. This verifies column presence, not every business constraint or live
shared-record validity. Existing rate resolver MD5:
`96f262dd4978509d5e40b43a585832f1`; certificate calculation MD5:
`705d9478aacc06a3204538357404817c`; detail reader MD5:
`933a4dc04faeeb98452c5290f9374054`.

Isolation proofs already exercised the real agreement propose/confirm/save
functions, v2 preservation, new v3 snapshots, and invoice/certificate generators
before/after the final seal patch. They verify no repeated snapshot write/revision
on identical recalculation and retention of the original seal during financial
changes. The certificate audit intentionally reproduces old defects before
applying the forward fix in the disposable database; those logs are not production
recalculations. These proofs do not cover every production constraint, scheduler
session, deletion/retention path or concurrent financial update. A protected
post-DDL comparison and separately reviewed runtime verification remain required.

## Function patch checks

Existing patch anchors each occur once, as required by #816. Whole-function
hashes below are observations for comparing a fresh preflight, not a claim that
production equals all newer repository calculations.

| Function | Observed MD5 | Anchor count |
| --- | --- | --- |
| `private.refresh_automatic_invoice(uuid,uuid,date)` | `1acf139e34e84b0b5ef6bf12623f81d8` | 1 |
| `private.refresh_automatic_payment_certificate(uuid,uuid,date)` | `fb1894de25484dc90dccc1c274c7608d` | 1 |
| `private.payroll_document_metadata(uuid)` | `7fb368dbadc629b99d23213cbf472fc4` | 1 |
| `private.saved_site_payment_document(uuid,uuid)` | absent | unavailable |
| `public.company_seal_style_settings(uuid)` | absent | unavailable |

Existing ON/OFF getter MD5: `626cf69bd490d3f56ff74cfca4a7cf89`;
setter MD5: `ed80b3c1dca43330ed173875b7fa709d`.
Existing account-access helper MD5: `313d371759a4de968cfe99db050ee65d`.
These functions are security definers with an empty search path. Record their
owner/ACL separately in a protected deployment backup; do not broaden privileges.

Stop if a required object is absent, a column type/default differs, a new function
or trigger already exists unexpectedly, any source anchor is absent/repeated, or
the fresh source/ledger differs from the reviewed state. Do not guess patches or
skip the failed statement. Apply reviewed DDL transactionally so an error cannot
leave a partially added column/trigger/function set.

## Protected backup and rollback requirements

The protected backup has **not** been obtained. Before any deployment, capture
the full old patched function definitions, owners, ACLs and search paths; table
columns/defaults/checks, grants and RLS policies; trigger OIDs/definitions/enabled
states; and the exact existing company settings and document rows in an approved
protected backup location. Do not send those values or a real-data snapshot to CI.
Record fresh row counts and full-row hashes for comparison without publishing
values. Hashes/counts alone cannot restore deleted or changed rows.

Plan scheduler/recalculation coordination and transaction/lock timeouts first.
Confirm immediately after DDL that old rows and trigger definitions remain
unchanged; do not run production recalculation merely to test installation.
New INSERTs must capture the server-owned style/name; UPDATE must preserve the
original key, including the absence of a key on old documents. Old agreements
must remain their original v1/v2 snapshots. Normal financial changes and style
selection are separate operations.

Restoring DDL/ACLs does not restore document data created after deployment. **Do
not remove JSON seal keys, drop stored snapshots, abbreviate names, backfill old
records or blindly drop the style column as a rollback.** New documents must remain
renderable with their original saved style/name. Prefer a reviewed forward fix
when stored metadata exists; preserve the font asset and document parser needed
to read it. Company ON/OFF, saved history and financial records must be retained.

## Subsequent production application report

On 2026-10-09 the production operator applied ledger migration
`20261009044454_company_seal_reisho_dependency_and_document_contract`, comprising
the reviewed agreement base `20261008201215`, agreement company snapshot
`20261008212855`, style `20261009011357` and document snapshot `20261009012730`
contracts. Already deployed certificate canonical math was **not reapplied**.
This report supersedes the earlier absence observations for those four contracts;
the original observations above remain historical evidence, not current status.
The repository source checkpoint remains
`a086828bb46819d74ca1bf9bd245e8f94a90dbdf` while this report is saved in a Draft PR.

The operator reported these post-DDL comparisons and authorization checks:

- Company hashes projected over the original columns are unchanged; both
  companies retain `legacy` style. Comparing the original projection avoids
  mistaking the added legacy-default column for a change to original data.
- Full-row hashes are unchanged for the two existing invoices, two payroll
  statements and zero payment certificates. No financial refresh or old-row
  snapshot backfill is claimed by these checks.
- Three new document snapshot triggers exist. Agreement rollout gates remain
  OFF (zero enabled). Existing ACLs, RLS and trigger definitions for the six
  monitored pre-existing tables are unchanged.
- Owner, ACL, search path and security-definer attributes of the ten monitored
  old functions are preserved. Definition hashes are unchanged except for the
  two intentionally patched refresh functions and payroll document metadata.
- The style getter/setter deny `anon` EXECUTE and allow `authenticated` EXECUTE.
  Both RPC calls with an empty JWT reject with SQLSTATE `42501`; an EXECUTE grant
  alone does not grant a company authorization.

A protected, target-limited recovery JSON was saved with SHA256
`79ffa77d37616e1ef7ee41e873ed32db31936f1e325b4262fe99cc68d1689110`.
Its contents, storage path, company identifiers and real rows are not included
here or in CI. This is **not a full-database backup or a completed restore
exercise**. The earlier statement that no backup had been acquired describes
the earlier preflight; the later limited recovery capture does not satisfy or
demonstrate every full recovery requirement above. DDL restoration still does
not reverse legitimate data saved after deployment.

Production DDL and these comparisons are now reported complete. Latest iPhone
Release installation, operation of the new style setting and end-to-end new
document rendering on the actual iPhone remain unconfirmed. No new style
selection, agreement gate activation or production document creation is claimed.
One genuine Reisho is available for the reviewed internal trial; the other four
typefaces and paid-distribution licensing remain unfinished. Source CI, this
DDL report, actual-device operation and TestFlight publication remain separate
outcomes.

One genuine Reisho is staged for free internal trials; the other four typefaces
and paid-distribution licensing are unfinished. CI/PGlite/PDF proofs are not
production application, backup recovery, iPhone operation or TestFlight evidence.
