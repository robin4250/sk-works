# Registered company names at daily-report checkout

Base: build 12 `e8ca207ebd85043d1fce803d79584977d6abef5c`.
The real checkout screenshot has only a free-text allowance label. The current
report page/repository never reads registered company names at all.

The first candidate used the legacy-three-name endpoint. The current candidate
requires the all-registered `read_company_registered_allowance_labels(p_company_id)`
through the shared adapter
owned by the common-name workstream. It does not use the admin settings RPC or
choose the actor's first company membership. Before the label read, the selected
worker IDs are resolved through the existing RLS-protected workers table. Missing,
duplicate, mixed-company or unexpected-company rows reject discovery. Captured
actor/token and page generation reject delayed results. The shared response
company is checked again.

The report shows the current registered names as optional filter chips. Simply
opening a report, fetching choices or reopening a saved draft does not select or
replace any label. Selecting a name updates the existing allowance-label controller and explicit
company-selection metadata (origin, registered ID/version, name snapshot and unit). Its current newline protocol is retained: the existing report source
`20261003004500_complete_route_daily_report_flow.sql` splits that field into
`attendance_entries.allowance_names` with newline/trim/nonempty semantics. Previously saved custom
text remains intact and visible, while new free-input names are disabled; no monetary amount, ID, quantity, activation or rate is
invented. The existing draft/signature invalidation and normal save/sign flow
remain in use.

Choices explicitly mean **current registered names**, not historical effective
names. Backdated unsigned entry can select them intentionally, including the
planned October bulk entry. Previously saved labels remain unchanged unless the
user edits them. Signed/reporter-locked reports do not discover or enable choices.
Duplicate names belonging to different IDs and names containing CR/LF cannot be
selected by the string-only report interface; other unambiguous names remain
available. Their original identities and values are not merged or rewritten.

The current shared adapter covers old fixed slots and additional registered
company items. Checkout uses `unit=day/hour` only; monthly items remain in payroll
settings. Payroll type is not confused with allowance unit. This is not yet a
claim that the backend selection capture or actual money reflection is complete.

Owned paths: report page/repository, allowance-name widget, typed-selection model,
anchored-roster metadata preservation, two related test files and two review docs. The shared repository is a dependency
copy for inspection only; root must adopt that path from `common_names_b12`.

Prepared tests cover visible names without preselection, explicit selection and
custom-text preservation, manual text/selection sync, disabled signed controls,
ambiguous names, discovery failure, exact complete roster/company binding,
different-company response and actor/token changes during discovery. No Flutter
or Dart execution was attempted locally; remote analysis/tests remain required.
No database, main, signed document or user session was mutated.

Latest user clarification: normal checkout selects company-registered items only. The text field is now read-only; registered-name chips are the entry path. This does not convert old custom strings into company definitions or delete them. All-registered-item adapter and producer/quantity contracts remain pending.


## Current typed handoff candidate (not deployed)

- Requires `company_checkout_allowance_contract_version() == 1` before reading
  interactive choices or sending typed selections. Unsupported servers cannot
  silently accept unknown selection keys and report saving successful.
- Optional `DailyReportWorkerDraft.companyAllowanceSelections` preserves the
  difference between missing metadata (legacy state retained) and explicit empty
  items (user cleared choices). Selected items never include a price/quantity.
- The proposed `daily_report_workers.company_allowance_selections` is read only
  when capability is present, preserved through the existing anchored-roster copy,
  sent on normal draft save and independently read back before later evidence
  linking. Lost/changed metadata refuses client success. Visit JSON supports a
  structural metadata echo comparison, but new selection UI is reserved for the
  final normal checkout report, not an intermediate visit report.
- `month` units are excluded only from new choices; existing label text is
  retained. Metadata uses registered enum units and stable identities, not label
  parsing or day-to-hour conversion. Normal checkout has no new unit-price,
  arbitrary-name or quantity entry.
- The backend writer/capture/receipt implementation is owned by
  `common_checkout_calculation`. Its contract must be verified together with
  these client files before production delivery. No backend code is edited here.

Prepared client tests now include typed-selection shape/unit/identity validation,
missing versus explicit-empty semantics, roster copy preservation, monthly-unit
exclusion independently of wage type, no silent adoption of old labels, exact
server capability, metadata echo before later links and stale actor/token refusal.
Remote Flutter analysis/tests remain unexecuted; no local Flutter/Dart runner was
used.

The final widget preserves registered origin/ID/generation/registration-version,
shows day/hour (including day items for monthly-paid workers), and excludes only
monthly allowance units. A current registration version/name change never silently
adopts old saved metadata: the user explicitly chooses the new registration.
Out-of-catalog saved company selections remain visible/removable without inventing
a replacement; unrelated original free text remains read-only and intact. The
normal checkout entry has no new arbitrary names, prices or hourly quantities.

Shared dependency is now PR1353 latest head
`e6534389bc7ccb231fea7009e3bd4e22ab57a445`; its source/SQL are owned by the
all-registered-name workstream. This client branch must not add its copied shared
file independently. The backend candidate still owns schema/capture/receipt and
is a separate required integration proof before claiming payroll reflection.
