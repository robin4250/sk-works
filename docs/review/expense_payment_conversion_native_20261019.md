# Explicit v1 draft conversion: native lock verification

Review-only preparation. Production data, schema, authentication, permissions and gates are unchanged. The native workflow uses only a fresh localhost PostgreSQL 17 disposable database with no existing auth/private schemas.

The verifier reuses the exact existing conversion fixture initialization and candidate SQL, then uses separate connections and `pg_blocking_pids` to prove actual lock waits. It checks duplicate command serialization and one immutable receipt, conversion before finalization (finalized -1,000 / one consumption), finalization before conversion (retryable conflict, legacy finalized +1,000 preserved), and claim-first allocation versus scope-first conversion (allocation fails 40001 without deadlock or receipt; unchanged source converts -1,000).

PGlite boundaries run separately before native races. Native CI results must be recorded after execution; source preparation is not a passing result. Existing production backup/restore, HTTP JWT/RLS paths and old-client exclusion are still unproven. Both activation gates remain default false. No migration file or product caller is introduced.
