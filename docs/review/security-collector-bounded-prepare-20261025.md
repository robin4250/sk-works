# Collector staged bounded preparation — NO production deployment

This is a new add-only subset, not a reconstruction of the three unrecovered
historical collector proof files. Existing PR 1345/1346 real GoTrue success is
reused for the issuer/consumer boundary; it is not proof of this new install /
restore transaction or of production RLS. New lifecycle CI remains pending.

## Current read-only observation and staged boundaries

Production catalog observation found all eight proof/collector routines and five
tables absent. `sko_security_collector_ingest` is absent. The deployed Edge lookup
for `reauthenticate-operation` returned Function not found. Existing Master,
device, account-deletion helper routines/tables remain present. No account,
session, JWT, password/hash, secret, collector event or financial row is returned.
Opaque whole-row financial hashes and public catalog definitions are kept in a
private checkpoint outside this branch, not committed here. The password catalog
is tested only for credential absence; no credential value is selected.

1. **Bridge role PREPARE ONLY.** Separate role inventory and generator require
   NOLOGIN / NOINHERIT / NOSUPERUSER / NOCREATEROLE / NOCREATEDB /
   NOREPLICATION / NOBYPASSRLS, no credential, membership or object dependencies.
   An absent role can be prepared; an existing exactly matching unused role is
   preserved. A different role aborts. No membership, password, database login or
   business privilege is generated. Catalog locks cover the unused decision.
   Undo drops only a newly created, still exact and unused role; it refuses any
   dependency/ACL/credential/membership change and never drops a pre-existing role.
   Managed Supabase may disallow system-catalog locks or CREATE ROLE. Success as
   an isolated postgres superuser does **not** prove these production permissions.
2. **Fresh observation after role stage; add-only SQL PREPARE ONLY.** Missing role
   returns blockers and **zero SQL artifacts**, as verified against the actual
   absent-role observation. With a separately reviewed matching role, the second
   generator prepares exact-before install, initial postflight and unused restore.
   Existing setters are neither replaced nor called. All three reauthentication
   scope gates and both collector gates stay false. Existing schema privileges
   remain fixed except the bridge's explicit private USAGE needed to call the
   single ingest function; the bridge gets no table access or role membership.
3. **Separate Edge deployment.** Current main's small index wrapper and the exact
   reviewed 1345 handler must be reviewed/deployed separately. Do not enable a
   SQL gate because adding a table or passing CI succeeded.
4. **Trusted producer/key/admission/operations remain separate.** No key,
   producer, listener, host binding, endpoint, telemetry send, monitoring
   subscription, honeypot or dynamic blocking is provisioned by these scripts.
   Until their review, all gates remain OFF. The current Master user, original
   session, provider configuration and existing roles are unchanged.

## Authoritative source pins

Files under `tool/security_collector_deployment/reviewed_sources` are exact
GitHub bytes (Git blob checked), not restored from descriptions:

| Source | Exact commit | Git blob |
| --- | --- | --- |
| Base proof SQL | 145e9563cd1cabaa43d484d53296ad252a740e9f | 643fcbc6de5401482fd83c55cdcf0b7c7a692e85 |
| Candidate Edge handler | same | 9fae6b52da6967c689d2e90c244cdb2c7b2725d6 |
| Collector storage | 362a324375b47242a7fa3a2565a51ddbe3508fd0 | a45e8d1447d542f1997a67d65f6b3559499141a4 |
| Public reader | same | f50f6830dbebb050ceedb8a70d3b6996e98afb6d |

SHA-256 pins are enforced before any generation. Only the base proof file's exact
prefix before `replace_secondary_password_with_proof` is selected; therefore the
old secondary-password, Master-feature and Master-device setters are not changed.
The device-lock extension is not silently copied. This narrower subset receives
its own lifecycle tests rather than inheriting the full staged script's status.
New private objects additionally revoke managed service-role defaults; public
capabilities/reader grant only authenticated, issuance only service_role, ingest
only the isolated bridge, and internal consumers remain owner-only.

## Guards and current verification limits

Install/undo acquire protected relation locks before comparisons. Existing
function source/full pg_proc attributes, table/column/constraint/policy/trigger
catalogs, private schema ACL, roles/memberships and ten business-table hashes are
fixed by the fresh observation. Auth session **schema only** is protected without
selecting session rows or blocking ordinary session-row writes. New functions
pin source, language, return/argument types, full non-OID attributes, owner and
exact ACL. New tables pin owner, RLS, absence of policies/extra grantees, exact
column shape/default/identity and constraint count/validation class. Further
strengthening to exact normalized CHECK/index expressions remains a review item
before any production use; `production_ready` deliberately remains false.

Initial postflight and unused restore also demand all gates false and all proof,
event/read-audit tables empty. The audit sequence must never have been used.
These are initial/unused guards, not a general live monitoring health check or
online rollback. Stop/withdraw any Edge/producer/client use separately before
an operator considers undo; a SQL script cannot retract an already sent request.
Restore uses DROP without CASCADE and never deletes existing financial/account
objects or changes an existing setter. The bridge's stage-one undo is rejected
while stage-two schema/function grants still depend on it.

Local Python compile, Node syntax, source Git blobs and absent-role fail-closed
preparation succeeded. No local Flutter or local production SQL execution was
performed. Remote Native fixtures are new and pending: they use synthetic auth
helpers, not production RLS/real GoTrue, and are scoped to install / postflight /
unused undo / retry / used undo denial, unexpected existing/new function security
drift refusal, connected-role undo refusal and both physical proof-writer/restore
race orders (writer-first proof survives; restore-first writer cannot commit).
The existing real GoTrue checks need not be rerun just for this offline wrapper.
These new two-connection cases are prepared, not yet passed. Exact normalized
new relation CHECK/index catalog pins must be complete
before this candidate can become production-ready. No success is claimed yet.
