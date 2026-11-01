# Inert OFF stage A: review-only extraction

**deployable:false. Fixture-only SQL. No production installer, ON or Phone qualification.**

This stage creates only two new private tables (OFF state and an empty immutable removal ledger), one owner-only immutable trigger function, and two triggers on that new ledger. Existing tables, readers, public RPCs, Auth bodies, Storage, notifications, payroll/calculation and receipt metadata are untouched. It cannot accept a removal or send a notification.

## Minimal prerequisite and exact effects

The disposable database name, postgres creator/private-schema ownership and anon/authenticated/service_role identities are checked. Client roles cannot be superusers or members of the creator role. New table names of any relation kind and any overload of the new function name must be absent. Existing objects are never replaced. All client/PUBLIC grants are revoked, RLS enabled, and unexpected creator-default grants cause transaction rollback. The only inserted row is the new singleton with enabled=false.

The ledger carries the original `before_row`, separate receipt metadata snapshot and explicit attached-metadata-only/reserved/unrecorded states. Those fields provide no evidence of actual photo bytes. Its immutable body is exact frozen77dc source; canonical receipt shape follows72ef.

**The claim foreign key is deliberately deferred.** Copying the old REFERENCES expense_claims(id) into stage A would install internal RI triggers on the existing claim table, violating this stage's existing-table-trigger invariant. Consequently this ledger is not a qualified removal store and has no writer API. A later stage must first prove this OFF ledger unused, validate real claim identity/FK and existing guards, then introduce a separately reviewed successor atomically. Never rerun frozen77dc or72ef against installed stage A, drop history, infer usage from catalog alone, or treat private owner access as business admission.

## Deferred, separate scopes

Stage B would require current real Auth/account/session/role and approval contracts; canonical receipt wrappers/RLS/Storage metadata; notification recipient/atomicity; CAS/journal/legacy-write protection; existing-reader shape and rollout. The old full OFF candidate already edits existing reader JSON and installs triggers on existing tables: it is not this inert stage and is not impact-free merely because enabled=false.

The Mac financial owner separately owns new-draft purpose/provenance, saved historical/manual/frozen originals, financial readers/refreshers and correction/consumption integration. They are neither installation targets nor prerequisites falsely satisfied by this stage. Financial-reader RED remains.

The previous large catalog attempt has completion UNKNOWN. Do not call it unexecuted and do not rerun it. Actual production baseline and object absence remain unresolved; limited prior account-helper fingerprint equality does not settle them. No production changes or new catalog queries occur here.

## Validation

`node docs/candidates/expense_removal_inert_off_stage_a_20261101/verify_source.mjs` checks source boundaries and exact frozen immutable-body reuse. It does not execute SQL or establish PostgreSQL runtime, production ACL/defaults, real Auth/Storage or deployment qualification. Any later production installer needs separate ownership, live precondition resolution and explicit approval.
