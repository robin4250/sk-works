# Offline expense maintenance candidate

Source: `994342fc136045d8ce6769b55f606952111808e6`, reviewed converter SHA256
`725ff2533539c63759c92c0bbc45d37c131fa431c421fd76deb127bdff2604d7`.
`build_candidate.py` refuses unknown source bytes and deterministically emits
`maintenance.sql.review-only`. No real company/document/user IDs or private
amounts are embedded. The new SQL does not invoke conversion or change gates.

The separate private SECURITY INVOKER function requires the exact temporary
`cli_login_*` DB session login and effective `postgres`, absent app UID and absent
JWT request GUCs. It saves `execution_kind=maintenance`, actual DB session/effective
roles and a mandatory authorization SHA256. An exact existing owner membership
row is checked and locked as an authorization original; it is not an authenticated
app actor. There is no `actor_id` in this new receipt. Existing app converter,
its audit table and its immutable trigger are unchanged. Public/anon/authenticated/
service_role receive no new grants; the private receipt has RLS enabled.

The pinned source conversion arithmetic and guards are reused: company/scope lock,
exact JSONB+MD5 original/revision, editable automatic draft, unblocked, legacy v1,
source claims/settlement locks and equality, no previous cost consumption, actual
calculation rows and gross basis, v2 envelope, revision+1, gross-deductions=net,
immutable before/after receipt and exact replay. A changed existing original
converter body is refused before creating the new schema objects.

## Verification completed

- Pure Python: 2 tests, deterministic source and one-byte unknown-source refusal,
  separate identity boundary and no JWT-setting command.
- Existing actual expense engine fixture loaded in PGlite: 66 checks passed.
  Synthetic originals are seeded as DB-owner data, without calling an app login
  or setting JWT/test UID values. The fixture changes SQL session authorization
  to a disposable synthetic CLI-shaped DB login and then effective postgres.
- Cases: original converter source drift rejection; non-maintenance executor;
  rollout OFF; source/hash/revision/scope/reference/authority changes; manual,
  blocked, finalized and consumed originals; gross basis mismatch; valid
  1000 deduction yielding net -1000; same-command replay without double revision;
  late audit-insert failure rolls back both row and receipt; old app converter
  definition and old audit schema preserved; immutable receipt and client ACLs.

Reproduce using the explicitly supplied local fixture checkout and PGlite module:

`node verify.mjs /absolute/disposable-fixture-source /absolute/pglite/dist/index.js`

The fixture imports `tool/fixtures/expense_cost_fixture.mjs` and its existing
original migrations/foundation data; no remote DB URL is accepted or opened.
The old archive's simulated app-claims scenario is not copied or executed. Only the
pinned converter and direction-v2 source are reused.

## Not yet complete

This candidate is not a production installer or authorization bypass. Exact
private target binding, fresh full dependency/catalog before guards, backup and
restoration evidence, real CLI role binding and TLS/native concurrency, validated
build/client rollout, one-attempt durable operator marker, COMMIT-unknown fresh
read-only recovery and a source-only unused restore contract remain the parent
operator's preparation scope. This function's input parameters are not themselves
independent approval evidence. The final reviewed Mac artifact must bind their
actual values and authorization digest; do not expose a general user RPC.

No production connection, DDL/DML, actual conversion, gate activation, JWT
creation, user/role/account change, external send or existing branch modification
was performed here. PGlite success is not native PostgreSQL/TLS/real-actor proof.
