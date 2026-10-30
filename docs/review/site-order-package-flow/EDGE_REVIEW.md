# Review-only verified HTTP connection

Production HOLD. No deploy, SQL apply, feature ON, live-user JWT, app UI or message dispatch is claimed. This candidate stacks on PR1645 and requires its exact private SQL installation plus `archive-read.sql.review-only`.

## Fixed request boundary

The new Edge handler accepts bounded JSON and an exact allowlist of command fields. Clients cannot choose SQL, company identity, authorizers, renderer paths/URLs, evidence or PDF bytes. A pinned Supabase JS2.78.0 `getClaims(token)` verifies signatures; the project issuer, authenticated audience/role, UUID subject and session, expiry and issued time are checked. Editable user metadata is dropped. Current sessions, exact membership, master flag and purpose are rechecked by the existing SQL.

Each request opens a dedicated TLS-verified `pg`8.16.3 connection from the documented server-only `SUPABASE_DB_URL`. BEGIN READ COMMITTED precedes transaction-local verified claims; the pure core owns this sequence for rendering. Connections always close, including COMMIT ACK loss. No automatic retry, rollback-after-unknown or pool reuse is permitted. The fixed manager export alone is selected by the renderer action.

## Feature OFF

Archive/status reads have a separate current-session/exact-membership actor helper for owner/admin/manager. They do not invoke the write actor/master gate. Both parties can read the immutable existing order/acceptance originals and persisted status with the feature OFF; new approval and rendering remain blocked. Foreign companies and worker roles remain denied. The status never calls an unsent acceptance delivered.

## Wasm deployment prerequisite

`runtime.mjs` imports `_canonical/edge_adapter.mjs`, staged from the separately reviewed PR1646 build. That factory is async and initialized lazily only after DB authorization selects a job. The private deployment directory must contain the fixed five staged files with the reviewed hashes, not public asset URLs. No static files are committed here. CLI staging/deployment is required for the ~14.3MB payload; the management API 5MB limit is insufficient. The source must be Deno-checked against the exact staged adapter before approval. Production deploy remains on HOLD.

## Evidence and limits

Unit tests use a genuinely signed ephemeral ES256 JWT and the pinned SDK's JWKS verification, including invalid signature/issuer/role/SID/expiry refusal before any DB connection. The disposable SQL fixture routes verified requests through the actual HTTP handler and transaction-local claims to private SQL, checks both companies' OFF archive reads, foreign refusal, write stop and original registration reuse. Native CI opens and closes a fresh PostgreSQL connection per request. These are isolated issuer/session fixtures, not production Supabase account or iPhone verification.

The remaining connections are order-draft input/UI, automatic reply scheduling/delivery, persisted delivered/failed/unknown attempt receipts, actual app notification dispatch, company history/screens, deployed real-user and iPhone tests. Existing registration buttons stay until a working destination is verified.

Docs verified2026-10-30: supabase.com/changelog.md, guides/functions/connect-to-postgres.md, guides/functions/secrets.md and reference/javascript/auth-getclaims. Relevant database upgrade and schema exposure changes do not authorize production DDL/grants here. New schemas/functions remain private.
