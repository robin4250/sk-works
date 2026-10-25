# Attendance management: registered company allowances

Review-only candidate. Not deployed, not activated and not yet PG17-proven. Node syntax validation of the focused loader and generated proof passed. All production reads used to pin function definitions were read-only; no business rows are included.

The SQL is one transaction, depends on the audited attendance administrator override, and installs a separate company rollout with no enabled rows. It preserves the current force-management guards, operation audit, live-session checks and protected finalized-document checks. It source-checks the exact force, roster permit and registered-item implementations before replacement. It does not replace normal signature capture, registry normalization or financial formulas.

## Client contract

`read_management_company_allowance_options(p_worker_ids uuid[])` returns `{contract_version:1, company_id, labels, workers:[{worker_id,items:[{origin,id,generation,registration_version}]}]}`. `labels` is the exact existing names-only label snapshot. No salary, rate or private payroll setting is returned. The worker set must be unique, active and in the manager's company. Read rejects while the new rollout is OFF. Month items are names-only; selectable items are eligible day/hour registrations.

Each existing `force_manage_attendance('upsert', p_items)` item may explicitly include `company_allowance_selections` using the existing version-1 DailyReport selection contract, and `company_allowance_legacy_labels` as string/null. Both absent preserve existing raw typed identities and the original receipt for the same worker/site/day. Explicit changed choices require an explicit legacy field and pass the original normalizer/label validator. SQL NULL selections are rejected; clear with `{contract_version:1,items:[]}`. Explicit legacy-only edits preserve selected identities. Free text never becomes a registered identity or financial receipt merely by matching a registered name. OFF rejects either optional field, rather than silently ignoring it.

## Administrative authority

New registered receipts require the exact live audited manager operation and its worker/report/date/site scope. The immutable snapshot records `authority.kind=attendance_management`, actual operation ID, actor ID and session ID. It contains actual registry snapshots; the report remains draft with both handwritten signatures null. These are management registrations, not supervisor-signed reports. Old actual signature receipts retain their UUID and snapshot unchanged on unrelated edits. Explicit new choices capture a new actual registry snapshot; prior receipts remain historical.

Existing financial consumers calculate day quantities. Hour quantities remain held when verified hours are unavailable; clock spans and guessed hours are not substituted. The legacy consumer's technical source string `confirmed_checkout_receipt` is not proof of a supervisor signature and must not be presented as such. Finalized financial protections remain in the original force path.

## Focused verification

`management-registered-allowances-native.yml` runs only the new focused tests on disposable PostgreSQL 17. The loader reuses predecessor installer prefixes, then cuts before their old broad tests. It checks OFF gates, exact names/eligibility, scoped authorization, typed save, explicit administrative authority, no fake signatures, old API preservation, old real-signature receipt preservation, stale registration refusal, no free-name masquerade, hour hold and complete late-batch rollback. No production credentials or data are used.

Install this directory under `docs/review/management-registered-allowances-candidate/` and its workflow under `.github/workflows/management-registered-allowances-native.yml`. Run CI before treating this candidate as finished. No activation SQL is included. `generate_candidate.py` deterministically rebuilds the SQL from saved function definitions; `source-pins.json`, `live-contract-source.json` and `native-reader-sources.json` retain the reviewed source evidence.
