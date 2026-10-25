# Shared worker factual confirmation candidate

This is a separate owner-only normalization/materialization module and a typed
client. It does not activate v2, sign a report, create attendance, adopt manual
attendance, calculate payroll or expose a table. The v2 coordinator owns live
session/worker authority, immutable confirmations, all-roster scope locks,
supervisor CAS and a transaction/actor/report/worker/facts-bound private permit.

The first common work signature does not attest another worker's future facts.
Every numeric input is explicit; an absent value never becomes zero. Existing
unconfirmed row values are proposals only. Client proposals remain unconfirmed
until the user presses confirmation. An unknown company-choice state is not
converted to an empty selection.

Canonical facts have exactly twelve keys: schema=1, overtime_hours, early_hours,
night_hours, work_category, allowance_amount, allowance_label,
company_allowance_selections, company_allowance_legacy_labels, vehicle_id,
route_assignment_id, odometer_km. Legacy labels come from the trusted stored row,
not the client. Company choices use the exact observed normalize_choices and
validate_labels source and server-owned registration identity, never client
prices. Manual cash allowance amount must equal the saved trusted value for
both personal and manager confirmations; attendance authority does not confer
salary-adjustment authority.

The materializer accepts only an exact private permit and canonical facts.
Every unrelated row field, identity and prior signature is retained. If vehicle
fields change, the observed legacy vehicle writer must validate the same
transaction and update its odometer; failures roll back the row. An enabled
strong committed-meter workflow cannot be reconstructed from these three
fields: use its existing validated attachment and reload. Unchanged meter
snapshot fields remain intact.

The focused PG17 fixture executes exact observed normalizer/label/legacy-vehicle
definitions but uses synthetic registration lookup and private permit/guard
surroundings. It proves numeric/key/identity validation, protected cash,
restricted materialization and rollback; it does not substitute for the full
v2 real-signature/attendance/payroll chain. Its connection is restricted to the
named loopback fixture database. The client tests exercise strict DTOs, CAS
payloads, absent-input handling, UID/SID changes and queued A-B-A events while
allowing access-token refresh in the same session.

Node syntax and source checks only have been run locally. New Native/Flutter
tests await remote CI. No production changes or real user operations occurred.
