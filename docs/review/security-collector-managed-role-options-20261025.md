# Managed role boundary — proposal only, no accepted exception or production SQL

The Native managed-like PostgreSQL17 measurement succeeded: a non-superuser with
CREATEROLE creates the bridge with an automatic creator membership carrying
`ADMIN=true`, `INHERIT=false`, `SET=false`. The same operator was denied the
system-catalog locks used by the current strict role installer. These are distinct
from the superuser lifecycle case. Production read-only public flags identify
`current_user=session_user=postgres`, non-superuser with CREATEROLE. No role was
created in production, and no production credential, JWT or session row was read.

The current code intentionally remains unchanged in policy: stage-one preparation
for that actual operator returns blockers and **zero executable SQL artifacts**.
Stage two still accepts only membership zero. Root must choose a separate route;
this document neither implements nor approves either option below.

## Option A: platform provisioning keeps the original membership-zero contract

An independently authorized platform route creates precisely the NOLOGIN /
NOINHERIT / non-privileged bridge, no password, no members and no object grants.
Fresh role/credential-absence/dependency/catalog observation must match before the
current stage-two generator can proceed. The platform route and safe cleanup
permissions must be independently established; do not assume an elevated role,
borrow credentials, add an INHERIT/SET membership or infer managed permission
from the isolated superuser.

## Option B: narrowly retained creator ADMIN membership (requires root decision)

If unavoidable, the proposed exception would permit exactly one automatically
generated membership for the fixed, observed installation operator only, with
ADMIN true and both SET and INHERIT false. Its grantor/member identity and every
membership flag would be pinned from the actual managed mechanism, not guessed
from fixture OIDs or role names. No API role, producer login role or other actor
would be admitted. Any extra member, changed flag, credential, privileged role
attribute or object dependency would refuse preparation and commit. An ADMIN
membership authorizes role management and is a real exception, even without
runtime inheritance: it must not be described as membership zero or silently
normalized out of an inventory. The current scripts do **not** allow it.

Without system-catalog locks, a possible CREATE transaction would use one fixed
transaction advisory lock to serialize this tool's own operations, verify absent
role/current operator and protected before-catalogs, execute fixed CREATE ROLE
(no duplicate-name adoption), then verify exact role + one allowed membership +
credential absence + dependency absence + unchanged existing catalogs before
commit. Any mismatch rolls back CREATE. Such an advisory lock does not serialize
an unrelated privileged administrator's GRANT or ALTER, so it cannot be presented
as a global catalog concurrency guarantee. Operator-controlled maintenance and a
reviewed managed provisioning mechanism would still be needed.

## Undo is fail-closed, not a best-effort DROP

If safe drop permission and concurrency exclusion cannot be demonstrated under
the same managed principal, the generated undo must be an unconditional refusal,
not DROP followed by a late check. DROP ROLE automatically removes memberships;
therefore dependency checks immediately before DROP without an applicable lock
must not be claimed to prevent a concurrent privileged membership grant. Keep
the unused NOLOGIN, credential-free role inert and require an independently
approved platform cleanup route. No source-only script should remove creator
ADMIN and later promise that the now-unprivileged creator can restore/drop it.

If reversible same-principal role provisioning is a required acceptance condition,
the lack of that route remains a blocker and artifact generation remains zero.
Either option would require its own Native tests, fresh managed observations,
explicit root review and protected originals before any production execution.
Edge deployment, producer/key provisioning, all rollout/collector gates, existing
Master/account/session values and financial data remain unchanged/OFF.
