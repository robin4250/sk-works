# Company seal: read-only production preflight

Observed on 2026-10-09 around 10:45–10:51 JST. Source checkpoint:
`b8879d675f2a2204dcfc4baf00859ea80d63f523` (#814 merged). #816 is
separate source work. This is a point-in-time observation, not deployment approval.
Only catalog SELECTs, aggregate counts and definition hashes were read. No company
names, person IDs, payroll amounts, document contents or credentials were returned.
No DDL, DML, financial refresh, RPC mutation, role grant or production backup ran.

## Observed state

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

## Migration identities and required order

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
3. The production payment-certificate ledger reaches
   `20261006174658_fix_payment_certificate_detail_formula_fallbacks`.
   `20261008035432_certificate_canonical_snapshot_math.sql` is not deployed.
   A matching seal patch anchor does not prove that the newer hourly/decimal-row/
   frozen-snapshot calculation fix is deployed. Review and resolve that independent
   dependency before claiming completed payment-certificate behavior.

No dependency above was applied by this preflight. #809 personal surname seals are
also separate from company seal storage and require their own deployment checks.

## Reviewable preparation sequence and side effects

This sequence describes a future reviewed deployment; it is **not an instruction
to apply migrations now**. The protected backup location has not been selected
by the operator, and no protected backup has been acquired.

| Stage | Prerequisites / stop condition | DDL and later-operation effects |
| --- | --- | --- |
| Certificate math, `20261008035432` | Existing partner settings, attendance/worker/site tables and `resolve_rate_formula(numeric,jsonb,jsonb,text)`; verify full definitions/ACLs before replacement. | Replaces calculation, automatic certificate refresh and detail-read functions. No top-level refresh, row UPDATE, trigger or cron creation. Later normal refresh may change automatic draft amounts/details/revision or delete an attendance-empty automatic draft. Manual/finalized rows are excluded from refresh. Historical detail reads without frozen rows return the recorded gross amount rather than current-rate reconstruction; this changes presentation without changing stored rows. |
| Agreement base, `20261008201215` | Accepted-share and company-connection schema, company/membership/site data model and account helper. Stop on existing new-object names or mismatched referenced columns/FKs. | Adds private rollout/proposal/confirmation/document tables, RLS and narrowly authorized RPCs. No existing financial-row writes, refresh invocation, trigger or cron installation. Gates default OFF and no rows are enabled. A later saved-document RPC can INSERT a snapshot after both confirmations; do not call it as a production installation check. |
| Agreement company snapshot, `20261008212855` | Base agreement objects, company postal/address/phone/fax/ON/OFF fields. | Replaces only the saved-document function's new-snapshot branch with v2 contact/ON/OFF fields. No top-level snapshot creation/backfill; existing saved JSON returns unchanged. |
| Style settings, `20261009011357` | Existing ON/OFF/account helper and exact-company admin model; new style column/functions must be absent. | Adds legacy-default style storage and restricted RPCs; no style-selection DML or cron installation. A later save changes only style/updated_at. Existing data and ON/OFF remain. |
| Document snapshots, `20261009012730` | Previous agreement v2 and style objects; reviewed generator anchors exactly once; certificate math must be resolved first to avoid replacing the seal-patched refresh later. | Adds three BEFORE INSERT/UPDATE snapshot triggers and patches five existing functions. No top-level financial-row UPDATE or refresh. Later new documents receive saved metadata; existing rows retain the original key or original absence. Replacing the certificate refresh with its unpatched math migration afterwards would remove the comparison-before-seal protection, so stop rather than reorder that replacement. |

The required chains are agreement base → agreement v2 → document snapshots and
style settings → document snapshots. Certificate math is independent of the
agreement/style chain but must precede the final document patch. A conservative
preparation order is certificate math → agreement base → agreement v2 → style →
document snapshots, with gates OFF throughout. Never apply an unreviewed broad
migration batch just because numeric filenames sort before these files.

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

One genuine Reisho is staged for free internal trials; the other four typefaces
and paid-distribution licensing are unfinished. CI/PGlite/PDF proofs are not
production application, backup recovery, iPhone operation or TestFlight evidence.

## Source-only recovery preparation

The source integration checkpoint is
`a086828bb46819d74ca1bf9bd245e8f94a90dbdf` (#819 includes #816). This does not
supersede the dated production observations above. It is the currently reviewed
source checkpoint containing the genuine font, coverage data and saved-seal
parser; it is not a guarantee that it can read metadata from future revisions.

`tool/pre_install_source_backup.sh` checks Darwin, Xcode 27.0 and a clean working
tree, then writes `commit.txt`, `status.txt` and `source.bundle` with `umask 077`.
The bundle contains Git objects reachable from the saved HEAD. Ignored local
credentials, generated iOS files, builds, iPhone data and production database
rows are excluded. The script already runs `git bundle verify`, but verification
alone is not an exercised checkout recovery.

An operator can inspect a saved source backup in a **new empty directory** on
the Mac. Substitute the actual backup directory printed by the script. These
commands do not change the current checkout or install an app:

```bash
sko_source_backup_dir="/absolute/path/to/the/printed/pre-install-backup"
test -f "$sko_source_backup_dir/commit.txt" && test -f "$sko_source_backup_dir/source.bundle"
sko_source_commit="$(cat "$sko_source_backup_dir/commit.txt")"
test "${#sko_source_commit}" -eq 40
git -C /Users/ryuichi/Desktop/sk-works bundle verify "$sko_source_backup_dir/source.bundle"
sko_recovery_dir="$(mktemp -d "$HOME/SKO-source-review-XXXXXX")"
git clone --no-checkout "$sko_source_backup_dir/source.bundle" "$sko_recovery_dir"
git -C "$sko_recovery_dir" checkout -b review-saved-source "$sko_source_commit"
test "$(git -C "$sko_recovery_dir" rev-parse HEAD)" = "$sko_source_commit"
test -z "$(git -C "$sko_recovery_dir" status --porcelain --untracked-files=all)"
```

Run each line only after the previous line succeeds; stop on any failure. A
successful checkout demonstrates restoration of that saved source only. A
pre-install backup may predate genuine-seal support. Before considering any
Release replacement after new seal snapshots exist, review compatibility with
the stored metadata and confirm the candidate source retains at least:

- `lib/domain/company_seal_snapshot.dart` and the shared
  `lib/features/shared/company_seal_pdf.dart`, plus all three document readers;
- `assets/fonts/company-seal/aoyagi-reisho/AoyagiReisho.ttf`, `coverage.json`,
  the bundled original usage/explanation files and their asset declarations.

File presence alone does not establish parser or glyph compatibility. Compare
the candidate to the reviewed checkpoint and validate rendering in an isolated
environment without copying real document data to CI. Do not overwrite the
current checkout, drop saved seal keys or install an old app merely because its
bundle verifies. Keep the current app and data until a compatible Release has
been reviewed. These source-only steps do not acquire the protected database
backup or validate financial-row restoration.

`docs/recovery/pre_company_seal_visibility_functions_20261008.json` contains two
old function definitions from a different checkpoint. It is not the fresh set of
all functions patched by the current migrations, nor a backup of their owners,
ACLs, triggers, company settings or document rows. Do not replay it as a complete
database rollback or substitute it for the protected backup described above.
