# Individual allowance list — build 12 UI repair candidate

Exact source baseline: e8ca207ebd85043d1fce803d79584977d6abef5c. No database,
producer, rate, activation, company-definition or finalized-document mutation
is included. Flutter execution is reserved for remote CI.

The screenshots show a fixed three-slot day form with a separate registration
button above the additional item editor. The fixed footer saves only the lower
editor. This candidate removes that fixed form and its separate button. Existing
nonempty PC / ironwork entries are UI-only rows in the same additional editor;
the empty third slot is not rendered. Names, amounts and original slot numbers
are retained. Added rows retain the existing unit-item identities.

The UI-only `worker-allowance-slot-1..3` IDs are never sent to the unit-condition
RPC. Editing/deleting a row updates only its original worker fields; removing
slot 1 does not move slot 2 into slot 1. No worker allowance is copied into unit
storage or company definitions. New rows use the existing unit-item RPC. The
original monthly custom amounts and their existing save path remain intact.

Every submitted row is validated before the first write, including names,
numeric ranges and time quantities. The two existing storage writes are not
claimed atomic. If the second write fails after the worker fields were saved,
the UI identifies the partial result, retains the inputs and blocks resend.
The user can explicitly replace the displayed drafts with a read-only reload
of saved values; reopening does not replay the failed operation. The original
single-store standalone editor behavior is retained. Actor and company/worker
changes block the chained second write. Older server fallback keeps registered
rows editable without offering unsupported additional unit storage.

## Important remaining integration boundaries

- Current legacy slot payment uses selected attendance allowance names. Existing
  additional day-unit items use all attendance days. The UI describes those
  existing different quantity rules rather than silently changing the producer.
  The checkout-to-payroll owner must finish the selected-day contract before
  reporting that all new day allowances are paid only when selected at checkout.
- The new all-company registered-name adapter belongs to the common-name owner.
  Its ID/generation/slot references must not be treated as permission to overwrite
  an individual's existing name or rate. Current company names must not replace
  frozen historical labels.
- Current company names from the all-registered-name adapter are projected as
  read-only items in their hour/day/month, earning/deduction group, filtered by
  the worker's existing payroll type. This includes monthly common earnings and
  deductions. Names-only responses never invent a zero rate or create a payable
  individual item. Existing individual slot names/rates remain authoritative;
  the current company name is a hint in the same row. Effective common rows keep
  their saved calculation/quantity UI, and frozen/past views are not renamed by
  the current catalog. The catalog read is actor/company/generation bound.
- The source dependency is PR1353 head
  `e6534389bc7ccb231fea7009e3bd4e22ab57a445`, specifically the shared adapter
  SHA256 `dcc964b7b4f81a104f714e0d2aab04764e3a79ff73cca9c63a07a7084d53aa98`.
  It is not owned or modified by this candidate. The new reader must be deployed
  before reporting real company-name projection complete. Existing names remain
  editable if that read is unavailable; partial names are not claimed complete.
- Monthly existing custom rows and historical typed-month rows retain their
  original identities. This candidate unifies the day fixed-slot split; it does
  not migrate every older monthly storage contract into a new database model.

## Prepared verification

New unit/widget cases cover stable IDs, empty-slot hiding, old-value round trips,
add/remove without repacking or copying storage, all-validation-before-save,
partial-save input retention/no retry through either footer, actor change between
stores, rejecting another company's setting, invalid day input on monthly
registration, preserving both day and monthly edits on general registration, and
month/hour company-name projection without a write, and an unavailable unit
reader that must not erase unseen typed items. The existing monthly/legacy preservation regression
is updated to the same additional-row UI. `git diff --check` passes; Flutter
analysis and widget outcomes are pending remote CI, not assumed successful.
