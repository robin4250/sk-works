# Insurance single monthly income input — 2026-10-25

Base: selected insurance UI source 2ac33cc (documentation 4a95a59), exact-main
`a23d5d94e88d3d089def0a72c7239ea123cb32b7` checked through GitHub ref.
Existing saved conditions/RPC value contract remain unchanged. No production SQL.

## Behavior

Entering the average monthly income once, or explicitly selecting an available
history average, fills separate health/pension standard-remuneration fields via
2026 general employee grade lookup. Company-provided premium rates remain used by
the existing calculator. The two derived values are shown; notice-based manual
correction is folded. Opening/reloading an existing profile never rebases it.
Manual base edits remain authoritative until the user explicitly changes income
again. Save still requires existing authorization, initial confirmation and final
confirmation; fixed/manual-premium modes never derive bases.

A positive income is required for conversion; unknown years refuse conversion.
For another year the existing notice-based manual fields remain available.
Empty reference input preserves previously saved reference and bases, consistent
with the existing RPC metadata contract. No zero income minimum-base assumption.

## Official sources checked 2026-10-25 JST

- Japan Pension Service, 2026 edition effective September 2020 pension grades:
  https://www.nenkin.go.jp/service/kounen/hokenryo/ryogaku/ryogakuhyo/20200825.files/R08ryougaku.pdf
- Kyokai Kenpo Tokyo 2026 health/pension combined grade table (rates March 2026,
  support levy April 2026; **no Tokyo rates copied into this implementation**):
  https://www.kyoukaikenpo.or.jp/assets/R8_13tokyo.pdf
- Determination by the competent pension institution, initial/regular/revision:
  https://www.nenkin.go.jp/section/faq/kounen/hyoujunhoushu/20140602-02.html

Lookup: health 50 grades 58,000–1,390,000; pension 32 grades 88,000–650,000,
using distinct pension floor (<93,000 income) and cap (>=635,000 income).
The lookup is scoped to the 2026 application month; it does not select a prefecture
or insurer, replace company rates, cover national health insurance/voluntary
continuation/day-worker exceptions, determine enrollment, decide statutory
revision dates, or file a statutory notification. Those distinct conditions are
not inferred from an average.

Payroll-period gross history still lacks statutory payment-basis-day checks,
excluded payment types and legal assessment-month determination. Its explicit
selection is a user-confirmed input, not an automatic legal determination.
The earlier request for unattended rolling average auto-revision remains outside
this change; no existing saved basis changes just because new payroll appears.

## Validation

Local Flutter/Dart execution not performed (prior auto-review restriction).
Remote CI required before integration. Tests added/updated: all 49 nonzero grade
boundaries ±1, independent floors/caps, bad amounts/year/month, one-input save /
reload, existing different bases preserved on open/save, manual override.
Existing reference validation/auth failure tests retained.

## Follow-up: visible entry in every deduction unit view

Root cause: the entire fixed-deduction component, including its settings link,
was hidden inside the monthly-only body. The individual page now mounts that
component in a persistent section header. Its setting button/status stay visible
when day/hour/month is selected; amount editors/resident tax remain monthly-only
via a mounted Offstage body. No duplicated repository/widget read or new route.

The button reads `保険料を設定`; status distinguishes loaded applicable condition,
no applicable condition and failure/unknown. A loaded condition is not a claim
that computed payroll amounts have been verified. Existing dirty/uncertain/
resident-editing gates still block navigation to protect drafts. Existing deep
links and formula dialogs remain. Formula help now describes the one-input path.
Three state tests cover the persistent entry and unit view toggling without
reload, and the exact month passed to the existing callback.

## Review fixes: preserve deliberate bases and show unapplied input

- Reference-period edits now update metadata only. Only an explicit amount edit
  or history selection triggers conversion, so changing a period cannot replace
  a notice-based manual override.
- Income edited in fixed/manual mode is marked unapplied. Returning to rates
  requires the visible `平均月収を計算に使う` action (or an explicit manual base edit)
  before saving. Save refuses an unapplied reference; it does not silently keep
  an old base paired with a changed income.
- Missing positive bases show an actionable error next to the save button;
  the user is directed to the income field or notice override, rather than
  receiving invisible errors inside a collapsed form. Existing first-setup
  tests now use the single income field and assert visible refusal / no writes.
- New regressions cover period change after a health override and rates → fixed
  → income edit → rates → refused save → explicit apply → correct distinct bases.


## Appearance-only follow-up

User clarified this request is appearance, not a new calculation or workflow.

1. One long undivided form is now grouped into rounded SKO-primary-color bordered
   cards: effective month, income, income tax, insurance/enrollment, supplemental
   deductions. Existing fields, order, initial expansion and validators remain.
2. The one income input has a larger amount and a subtle primary-color fill;
   other form content retains the existing scale. The title is `保険料の設定`.
3. A final read-only summary makes the effective month, insurance method and
   calculation bases easy to review above the existing confirmation/save action.
   The effective-month line listens to the existing controller (no new save).

Help updated. No calculation, scope, enrollment, save/confirmation or default
changes in this visual follow-up. Existing operation tests remain the checks;
no style-mirroring test added. The existing initial-setup test now ensures its
confirmation checkbox is on-screen before tapping (no warning suppression).


## Genre-based details follow-up

The user requested normally used settings to remain directly accessible and
infrequent details to be collapsed by genre. This is presentation only.

- Average income is the first always-visible control in its card. Its existing
  reference period/history selection is inside `対象期間・実績から選ぶ`.
- Income-tax details, enrollment exception checkboxes and supplemental deduction
  conditions have separate detail panels. Insurance method/enrollment selector,
  saved basis summary, effective month and save controls remain visible. Nursing
  birth date stays visible when nursing is selected; otherwise it is Offstage.
- Every detail form remains mounted (`maintainState: true`); validation does not
  disappear when collapsed. Invalid detail input produces a footer instruction
  identifying the relevant panels/birth field. Existing missing-base refusal
  remains visible. No calculation, RPC or confirmation changes.

Material fix: card surfaces now use a real Material with a rounded shape, rather
than a painted Container between Material and ListTile. This preserves ink and
ListTile assertions; no assertion was suppressed. Existing operation tests now
explicitly open a detail before operating it. Existing one-input page tests also
assert a collapsed period field is still mounted before save/reload tests.


## Review: optional birth date remains correctable

A nonempty birth date now remains visible even after nursing is unchecked.
Nonempty dates always validate their exact Gregorian calendar date (including
invalid day/month and year zero), because the existing backend stores/parses
that field regardless of nursing selection. Empty optional date is unchanged;
no saved draft value is silently cleared. Regression tests: nursing ON, enter
`abc` or February 30, OFF, field visible/value retained/save write count zero;
normal valid nursing date saves and reloads unchanged.

Existing test fixture adjustments: dropdown initial-state inspection includes
mounted collapsed controls; permission-error screens have no ListView and the
fixture no longer attempts to drag one. These do not alter production behavior.
