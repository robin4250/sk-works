# Trade central OFF foundation — phase A only

New review-only candidate, separate from build 12 main `e8ca207e`. No production
deployment, master toggle, proof issuer change or business-function patch is
included. The proposed key is `trade_document_reciprocal_seals`.

The current five-key central table/constraint and three routine source hashes,
owners, security attributes and ACLs are explicitly bound to the existing
observed catalog. Unknown, partial, already installed, six-key/image or
proof-setter baselines reject before DDL. Adding the image key merely to make
this the seventh row is prohibited. The observed-source fixture is a newly
prepared test input, not a recovered historical source or financial dataset.

The SQL adds only this distinct key with explicit FALSE (the old central table
default TRUE remains unchanged), extends the existing discovery reader with
missing/NULL=FALSE for this key, and adds an owner-only SECURITY INVOKER guard.
The guard requires an existing TRUE row and holds FOR SHARE until the caller's
business transaction ends. It cannot be called by anon/authenticated/service.
Existing legacy setter and vehicle/route guard remain byte-identical, so the
legacy setter cannot activate the new key. No new public setter exists.

The existing five rows and all three routines' security metadata/ACL are
checked after installation. Existing flags keep their original values and
defaults. No document, stamp, consent, history, approval, account, role,
financial row or stored PDF is read or changed by this candidate.

## Explicit remaining dependencies

This foundation alone does not gate existing reciprocal business functions.
Those APIs are still an uninstalled review candidate. Before installing or
enabling any reciprocal write, the trade owner must place the new guard after
existing actor/account/company/link authorization and before document locks
for both issuer and recipient directions. Existing immutable approved reads
and printing must remain available when OFF.

Phase B needs a separately reviewed complete server-issued proof lifecycle:
Edge `master.feature.set`, both SQL issuers (including the device replacement),
exact actor + original session + key + requested boolean binding, one-time
consume, expiry/revocation, existing Master/account checks and a proof-only
toggle. Legacy setters must continue to reject this key even when the old
reauthentication rollout is OFF. This SQL does not silently fall back to a
legacy setter when any of those prerequisites is missing. A future proof
deployment changes the baseline and must have its own pinned installer.

## Validation status

Python syntax/JSON and diff checks are local preparation only. The new Native
workflow is prepared, not yet run: exact-source five-key fixture, wrong baseline
rollback, repeated install refusal, explicit OFF, missing/NULL/OFF refusal,
discovery FALSE, anonymous discovery NULL, all API-role guard refusal, legacy
setter denial, old setter/guard source preservation and two-connection gate/OFF
serialization. Fixture-only owner writes TRUE to exercise the lock and restores
OFF; that is not a production activation or an available product toggle.

This suite does not prove real GoTrue/Edge proof, company authorization,
reciprocal business behavior or a hosted deployment. Those remain independent
requirements rather than being represented by synthetic Master predicates.

Supabase database-functions documentation was checked using search_docs:
https://supabase.com/docs/guides/database/functions . The changelog Markdown
fetch was attempted but rejected by the browsing tool's content-type handler;
no new Supabase client/API behavior was assumed here.
