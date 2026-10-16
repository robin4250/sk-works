# Personnel permission regression and recovery rehearsal

This suite runs only against a disposable synthetic PGlite database or an empty
loopback PostgreSQL 17 database. The workflow additionally sends signed synthetic
JWTs to local PostgREST. It does not connect to a Supabase project or read real
users, identities, memberships, personnel records or master registrations.

The candidate replaces only the two personnel/family SELECT policies. Before
applying it, the suite captures both original policy definitions from the fixture
catalog. After testing the fix, it recreates those exact original policies and
verifies legitimate owner/admin/self access, then reapplies the candidate.

The migration fails closed if the two original policy predicates, roles,
permissiveness, commands or policy inventory differ from the reviewed catalog,
if table RLS flags differ, or if the canonical read helper's source, owner,
execution ACL, security mode, language, return type, volatility or search path
differ. Role/type names resolve through PostgreSQL catalogs; no environment's
numeric role IDs are copied. Target tables are locked for the short transaction
with a five-second lock timeout so concurrent policy edits cannot be overwritten.
The fixture preserves actual policy roles, including the original PUBLIC scope,
and the app_role enum needed to preserve the exact policy expressions. Synthetic
drift cases prove the whole migration aborts without changing the new snapshot.
Any drift requires a fresh protected snapshot and review, never bypassing the
guard to force a deployment.

The rehearsal asserts unchanged synthetic business rows and user IDs, provider
identities, company roles/memberships, master registrations, function definitions,
schema/table/column/function ACLs, RLS flags and non-SELECT policies. It does not
claim that a real production backup has been taken or that production recovery
has been proven. The small identity/master tables are sentinels, not a complete
Supabase Auth or master-device schema.

**Emergency restoration reopens the original known vulnerability.** The suite
explicitly proves that a manager with people permission OFF can again read
coworker personnel/family records after restoring the old policies. Restoration
is therefore not a safe normal rollback and must not be executed automatically.

No production permission change or restoration is authorized by this test or by
merging the PR. Before any production change: prepare a protected current backup
and an exact restoration plan, verify administrator/provider/membership recovery
protection, review the risks, and obtain the user's explicit approval. Stop if
these gates are incomplete. Never print real account identifiers or credentials
in test logs or reports.
