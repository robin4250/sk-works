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

## Fixed reply delivery and app inbox

The reply worker resolves the saved job and stable request from the private package; client input cannot change its recipient or original. It registers the canonical PDF in a separate committed transaction, then atomically stores the original sender's private acceptance receipt and actual `app_notifications` rows. A notification insertion failure rolls back recipient storage, while the registered original is reused on retry. COMMIT ACK loss at any of the three stages stays UNKNOWN and is never automatically resent or rolled back.

Approval HTTP now invokes this fixed worker after its own commit; failure returns the known approval plus a pending/unknown reply classification. A dedicated manual `process_reply` command resumes the same saved intent. This is request-driven processing, not a deployed background scheduler. Notifications use a dedicated `site_order_package` action and fixed text without prices, notes or PDF URLs. Private notification receipts suppress duplicates. Inbox insertion is distinct from device push/read confirmation. Current production `pg_catalog` READ ONLY metadata confirms notification column types/nullability and RLS; the install candidate rejects schema drift. No business row was read.

The private list/detail surfaces expose only authorized management histories, support stable time/UUID pagination, and keep OFF archive reads available. Acceptance originals become readable by the original sender only after the recipient receipt commits. Existing native app notification routing/UI is a remaining connection. The HTTP archive uses `application/octet-stream`: the exact locked Dart functions_client2.7.1 source (archive SHA256 equals pubspec.lock) parses that response as bytes; `application/pdf` would be decoded as text by that SDK. The payload remains a PDF and carries an inline .pdf filename.

Latest delivery candidate local checks: package167 (including real ES256 verification through HTTP/private SQL), worker/HTTP16, existing coordinator12. Native CI must be checked on the new published exact head. The repeated fixture JWKS issuer uses a new key ID per ephemeral key pair, preserving the SDK cache's proper same-key-ID behavior.
