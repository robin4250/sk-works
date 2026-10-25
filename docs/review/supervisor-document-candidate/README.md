# Document-only signature and recorded draft correction candidate

Exact application source baseline: `8f3d881e06847ff9fdfb81d49d78884206ec17f7` (build 17).
**REVIEW ONLY. Not applied, activated, or Native-proven yet.**

Place this directory at `docs/review/supervisor-document-candidate` in the repository and copy `document-signature-native.yml` to `.github/workflows/document-signature-native.yml`. No existing checkout files were edited to prepare this candidate.

## Scope

The site's actual supervisor can sign a reporter-signed document without per-worker hours/allowance confirmation. That signature completes the document, while `daily_reports.status` remains `draft`. Existing attendance, payroll, allowance receipts, hour confirmations, ledger, and settings stay unchanged. No values or signatures are invented.

Activation is an explicit **report allowlist**, not a company-wide default: private `document_rollout(company_id, report_id, starts_on, enabled default false)`. The candidate inserts no rows. After first use, `work_protocol.document_only=true` pins that report's interpretation; deleting a rollout row is not a data rollback. Historical financially signed reports and source-report attendance/ledger rows cannot enter this mode through the allowlist. Do not turn future company payroll off through a general company switch.

## Read/API contract

Existing shared read envelopes retain schema 1 and ordinary state/actor/company/source/date fields. For opted reports, `signature_scope` adds:

- `document_only: true`
- `document_complete: bool`: both actual signatures present and the latest supervisor event's saved snapshot still equals current document source rows.
- `document_editable: bool`: the actual reporter event actor or current authorized attendance manager may start an explicit draft revision. A normal colleague cannot edit someone else's work.
- `document_revision_supported: true`
- `financial_confirmation_required: true`: document completion does not attest that payroll is ready.
- `document_basis: {report: raw daily_reports row, workers: [raw daily_report_workers row + worker_name + vehicle_name + route_name], reporter_signature_binding: existing reporter_work_evidence receipt | null}`. Workers are ordered by worker ID. This preserves raw overtime/early/night/category/selection/label/vehicle values and actual signature binding without rate or payroll calculation. Existing `work_basis` is unchanged.
- `document_snapshot`: the `report` and `workers` parts above; persisted in the existing private signature audit events.
- `signature_scope_fingerprint`: hashes this source snapshot and existing actual reporter receipt. Changes during capture fail CAS.
- `supervisor_ready`: actual reporter consent and nonempty document work/roster, independent of financial annex/other workers' punches.
- `hours_annex: null`, `pending_members: []`, document-specific reasons only.

Mode OFF preserves the previous read payload/behavior; added fields may be absent and UI must default to ordinary mode. `state=supervisor_saved` with `report_status=draft` is valid for document-only completion. Never interpret that state as payroll finalized.

### Explicit edit start

`start_shared_report_document_edit(p_report_id uuid, p_expected_updated_at timestamptz, p_expected_signature_scope text, p_reason text) -> fresh shared context`

Requires current live actor/session/account/company and original reporting actor or existing management permission, draft document mode, no source-report attendance/financial ledger. It takes existing ordered payroll/group/report/roster locks, rechecks authorization and CAS, then issues a private permit restricted to exact actor/session/transaction/old report+roster. That permit allows only clearing the canonical and both individual signatures; it changes no work facts. Existing `signature_events` receives raw prior signature, full prior report, roster, raw confirmation records and the explicit reason. Prior events are not modified. The permit is deleted before commit; any failure rolls everything back. Both reporter-only and supervisor-complete drafts can be reset. `status=signed` still requires the old approved-edit workflow and is refused here.

### Save the revised draft

`save_shared_report_document_draft(p_report_id uuid, p_expected_updated_at timestamptz, p_expected_signature_scope text, p_work_description text, p_workers jsonb) -> fresh shared context`

`p_workers` uses the existing Dart `toRpcJson`: required worker_id/overtime_hours/early_hours/night_hours/allowance_amount/allowance_label plus optional company_allowance_selections. Exact same roster only. Explicit quantities are numeric, finite, 0–24, at most four decimals. Money, vehicle, work category, source IDs, company/date/site/route and roster membership are immutable here. In particular old NULL category is preserved, not inferred. The current edit actor/session or existing manager is required. A transaction-private exact-row permit lets `guard_roster` update only the five document quantity/selection/label fields.

Unchanged saved selection and label are retained without `registered_item`, even when the employee now has monthly pay and the old saved item is daily. A changed selection invokes the unchanged `normalize_choices` and `validate_labels`; it is never converted into money or a free label. Clearing uses explicit `{contract_version:1,items:[]}`. A substantive label-only change without selection change is refused. NULL/empty/trimmed-empty labels are compared semantically because Dart displays SQL NULL as an empty string; when selections are unchanged, the exact original SQL label value is retained rather than normalized or repriced. Existing legacy/manual cash is preserved but cannot be edited. No financial tables are written.

After save, use existing `submit_shared_daily_report` with fresh CAS and the already-saved payload for actual reporter re-signing, then existing normal/manager supervisor collectors. The exact baseline `submit_report` already checks preview text/roster and attaches the real own pair without calling the delete/reinsert writer. New signatures create new events and work epoch binding; old confirmation receipts cannot silently bind to the changed epoch. Do not copy prior strokes into a new signature.

## Source and compatibility changes

The SQL pins eleven exact baseline bodies, owner, definer/search path, and private ACL metadata before any DDL. Private signer ACL is preserved by CREATE OR REPLACE (the baseline source fixture does not claim its deployed ACL). See `source-pins.md`. Changed original functions are only shared scope/enrollment/collectors, signature guard/audit, existing private signer auto-finalization dispatch, and approved-edit collection/copy/close hooks. Payroll formulas, `public.sign_daily_report`, `registered_item`, normalization, hour confirmation/materialization/ledger code, and finance consumers are unchanged.

The private signer skips its automatic call to financial `sign_daily_report` only in opted mode. `guard_report` refuses old direct draft→financial-signed attempts in opted mode; existing signed reports remain on their original approved-edit path. Existing `guard_roster` stays immutable after document signature; only an explicitly unsigned revision plus exact new-writer permit can change the permitted fields.

Raw historical signatures and source snapshots are additional nullable columns in existing `signature_events`. No parallel document store, financial shadow rows or fake approval request is introduced. New helper/permit tables are private, RLS-enabled and revoked from PUBLIC/anon/authenticated/service_role. Only the two authenticated RPCs are newly exposed and authorize every call.

## Focused Native proof

`verify_document_signatures.mjs` extracts only the installation/setup sections from existing source-bound fixture harnesses, then installs the actual v1/v2/approved-edit modules and this candidate into an empty disposable PostgreSQL 17 database. It does not repeat the unchanged 331-case suite. The URL/password/database/host/CI guards are inherited unchanged; real GoTrue is not claimed.

The focused cases cover OFF preservation, real monthly-vs-daily registration failure, direct actual document signatures while a peer remains clocked in and no personal confirmations exist, source review snapshot, non-reporting actor/cross-company/CAS denial, no duplicate event on exact retry, old financial entry point rejection, unchanged entries/payroll/ledgers/settings, full signature history and one-use reset permit, raw document save with stale selection preserved, changed selection revalidated, quantity/money bounds, and save→old submit actual reporter re-sign→actual supervisor re-sign.

Local checks so far: offline exact-source generation and both loader/generated-JS syntax pass. **Native PostgreSQL execution is pending CI.** The proof must pass before this is called complete or installed. Extend its focused cases for actual session replacement, finalized-report rejection, manager without personal clock, and failed-save rollback before activation. Live exact source/catalog/default ACL readback and a private backup remain separate deployment prerequisites. No app data or production source was queried by this candidate builder.

## Known boundaries

Financial confirmation after document-only signing remains a separate workflow and is not automatically enabled. Existing `read_input.editable` may stay false once the reporter signs; this candidate deliberately offers the explicit record/reset/save/re-sign path, not fabricated financial confirmation. Target a reviewed report allowlist only until a separately reviewed financial workflow is ready. The monthly/daily registration incompatibility is preserved as a financial error and no longer blocks the document signature calculation.

Attendance-management physical deletion remains blocked for signed/enrolled work. `force_manage_attendance` deletes worker rows and then an empty report; `guard_roster` correctly rejects that, and `work_protocol.report_id` also has a non-cascading FK. A document revision reset is **not permission or a guarantee to delete attendance/report history**. Cancellation/tombstones and financial/finalized guards require a separate history-preserving design; this candidate does not change that writer or those FK rules.
