# Genuine Reisho: future document snapshots

Source preparation only; new migration has not been applied to production.
Depends on #814 (genuine font/settings) and exact #809
`ea72dace6f095351121083dae6f4c29e558ddb91` (personal surname seal).
One genuine Reisho is available for free internal trials under the documented
license interpretation. Paid distribution is unresolved; the other four genuine
typefaces remain unfinished. This does not complete the five-typeface feature.

## Historical data

New invoices, monthly certificates and payroll statements receive a server-owned
`company_seal_snapshot` containing version 1, selected style and the unabridged
registered name in their existing JSON fields. On UPDATE, the original key is
retained. A legacy record without the key remains without it. There is no backfill,
UPDATE of existing records, replacement of old manual/finalized snapshots, or
extension of roles/RLS. Existing ON/OFF behavior is unchanged.

Invoice and certificate generators add the persisted key to the candidate JSON
before comparing. Repeated identical cron calculations do not modify the snapshot,
timestamp or certificate revision. Real financial changes still recalculate and
retain the original seal. The migration checks each generator source anchor exactly
once and fails on unexpected definitions; it does not guess a replacement.

The immutable mutual payment document adds this metadata only when creating a new
version 3 snapshot. Existing version 1/2 documents are returned unchanged.
Client parsers treat missing metadata as legacy and reject unknown/corrupt metadata.
All three actual PDF generators use the saved style and name. Invoice v8's adopted
overlap and coordinates are preserved; certificate separate-box layout is preserved.

## Invalid names and capability

A direct company UPDATE can bypass the settings RPC; new document snapshot creation
still validates the selected style and genuine font's frozen cmap/name-length guard.
Missing glyphs and names beyond the 16-rune trial limit explicitly fail. The PDF
renderer independently checks coverage, length and actual glyph size (minimum
4.5 pt). There is no normal-font fallback, silent downgrade, renamed company or
name abbreviation. Existing saved names remain stable after company renaming.
These technical limits do not certify readability for every permitted company name.

The settings UI claims new-document integration only after the phase 2 RPC capability
is returned. Phase 1 servers retain the preview-only message. Help explains the
future-only behavior. This avoids claiming database rollout from client deployment.

## Validation

Disposable PGlite checks passed locally for new-only JSON storage, immutable updates,
old absence, v1/v2 agreements, invalid direct company updates and helper ACLs.
Actual invoice and certificate generator tests passed for unchanged cron writes,
old draft/finalized preservation and real financial changes. Local Flutter/Dart is
unavailable. Flutter PDF production generation, embedded genuine-font checks and
short/long PNG review (three monthly reports plus mutually confirmed v3 agreements) run in CI; results must be checked before integration.
Production rollout, real iPhone operations and TestFlight remain separate work.
