# Qualification inspection: Storage read binding source review

Read-only research, 2026-10-27. This note changes no SQL, application code, Auth, Storage policy, bucket setting, or production data. No real qualification object was downloaded. PR 1506 remains OFF / NO GRANT. The existing `readImmutableVersion` injection is not connected to a production reader by this review.

## Result and deployment limit

Supabase's S3 compatibility documentation says S3 bucket versioning is unsupported. That does **not** mean the internal `storage.objects.version` column is an AWS S3 `VersionId`. The reviewed Storage source uses its internal version to construct a different backend **key**, and the S3-compatible handler explicitly rejects an incoming AWS `VersionId`.

The current upstream REST implementation does accept `?versionId=` and binds the database lookup and backend key to that internal version. This is evidence about the fixed upstream source below, **not evidence that SKO's hosted Storage deployment runs it**. The deployed revision, migration state, query handling, cache behavior, and effective writer permissions are unknown. Do not enable the candidate, claim immutable storage, or fall back to an unversioned download on that basis.

Fixed source: [supabase/storage commit 024b4c7fc9b5724c1efc9aa91f5940e3c6848067](https://github.com/supabase/storage/commit/024b4c7fc9b5724c1efc9aa91f5940e3c6848067), upstream master observed 2026-10-27. SKO's deployed revision was not queried. All line references below refer to this fixed commit.

## Primary-source findings

| Boundary | Source and lines | Finding |
| --- | --- | --- |
| Public S3 API | [S3 compatibility](https://supabase.com/docs/guides/storage/s3/compatibility), object operations | S3 versioning is documented unsupported; GetObject/HeadObject conditional If-Match is documented supported. These are separate capabilities. |
| REST authenticated download | [getObject.ts](https://github.com/supabase/storage/blob/024b4c7fc9b5724c1efc9aa91f5940e3c6848067/src/http/routes/object/getObject.ts#L22-L86) | Query `versionId` reaches `findObject`; the selected row's version is passed to the asset renderer. Private-bucket reads use caller RLS. |
| Database selection | [pg.ts](https://github.com/supabase/storage/blob/024b4c7fc9b5724c1efc9aa91f5940e3c6848067/src/storage/database/pg.ts#L1916-L1966) | An explicit version adds a bound `version = $n` predicate; absent version selects the current row when the versioning migration exists. |
| Delete markers | [object.ts](https://github.com/supabase/storage/blob/024b4c7fc9b5724c1efc9aa91f5940e3c6848067/src/storage/object.ts#L813-L827) | `findObject` requests delete-marker exclusion. The DB helper applies that column filter when its migration exists. |
| Backend key | [adapter.ts](https://github.com/supabase/storage/blob/024b4c7fc9b5724c1efc9aa91f5940e3c6848067/src/storage/backend/adapter.ts#L289-L304) | `withOptionalVersion` appends internal version to the key, with separator chosen by configuration. A null version uses the unsuffixed legacy key. Do not synthesize physical keys or treat this as a public storage contract. |
| Actual S3 request | [s3/adapter.ts](https://github.com/supabase/storage/blob/024b4c7fc9b5724c1efc9aa91f5940e3c6848067/src/storage/backend/s3/adapter.ts#L128-L166) | The backend GET sets `Key: withOptionalVersion(...)`, not AWS `VersionId`. If-Match is sent as backend `IfMatch`. |
| REST If-Match | [asset.ts](https://github.com/supabase/storage/blob/024b4c7fc9b5724c1efc9aa91f5940e3c6848067/src/storage/renderer/asset.ts#L14-L26) | The incoming `if-match` header reaches backend GET. It compares the backend ETag, not the selected SHA-256 or internal version string. |
| Download response | [renderer.ts](https://github.com/supabase/storage/blob/024b4c7fc9b5724c1efc9aa91f5940e3c6848067/src/storage/renderer/renderer.ts#L124-L175) | Response includes ETag/content headers; this path does not explicitly return database object ID/version headers. A download alone is insufficient evidence of object-row identity. |
| Metadata REST route | [getObjectInfo.ts](https://github.com/supabase/storage/blob/024b4c7fc9b5724c1efc9aa91f5940e3c6848067/src/http/routes/object/getObjectInfo.ts) and [info.ts](https://github.com/supabase/storage/blob/024b4c7fc9b5724c1efc9aa91f5940e3c6848067/src/storage/renderer/info.ts#L12-L36) | `/object/info/authenticated/:bucket/*` also accepts versionId. JSON contains id, name, version, bucket_id, etag, size, content_type and optional archive/delete-marker flags. JSON `metadata` is user_metadata, not the storage.objects backend metadata column; do not confuse their provenance. |
| S3-compatible GET | [s3-handler.ts](https://github.com/supabase/storage/blob/024b4c7fc9b5724c1efc9aa91f5940e3c6848067/src/storage/protocols/s3/s3-handler.ts#L72-L88) and [GET](https://github.com/supabase/storage/blob/024b4c7fc9b5724c1efc9aa91f5940e3c6848067/src/storage/protocols/s3/s3-handler.ts#L1090-L1124) | Incoming AWS VersionId is rejected; current database version is looked up and sent to the backend, with conditional headers. REST versionId and S3 VersionId cannot be substituted. |

## Writer identity: evidence and remaining proof

The ordinary upload path calls `prepareUpload`, which generates a random UUID, uploads to that version's backend key, and sends the same version to the database completion transaction ([uploader.ts lines 129–188](https://github.com/supabase/storage/blob/024b4c7fc9b5724c1efc9aa91f5940e3c6848067/src/storage/uploader.ts#L129-L188)). Completion recognizes a retry of an already committed version and does not create a new logical write ([lines 240–300](https://github.com/supabase/storage/blob/024b4c7fc9b5724c1efc9aa91f5940e3c6848067/src/storage/uploader.ts#L240-L300)). Therefore the assertion “every request always creates a new version” would be incorrect.

TUS naming generates a random version for a new upload ([lifecycle.ts lines 254–270](https://github.com/supabase/storage/blob/024b4c7fc9b5724c1efc9aa91f5940e3c6848067/src/http/routes/tus/lifecycle.ts#L254-L270)). Copy and move allocate new random versions ([object.ts lines 870 and 1090](https://github.com/supabase/storage/blob/024b4c7fc9b5724c1efc9aa91f5940e3c6848067/src/storage/object.ts)). These observations support a prospective version-bound reader, but are not an exhaustive proof for multipart completion/retry, TUS retry after completion, lifecycle restore/promotion, direct database writes, physical backend writes, or the unknown hosted revision.

The database write path uses INSERT/ON CONFLICT in disabled/suspended modes and can retain a row ID while updating its version ([pg.ts lines 1369–1504](https://github.com/supabase/storage/blob/024b4c7fc9b5724c1efc9aa91f5940e3c6848067/src/storage/database/pg.ts#L1369-L1504)). Object ID alone cannot detect overwrite. Version promotion may make an existing version current again; that is distinct from mutating that version's bytes. The additive migration deliberately retains a nullable legacy version column ([0062 migration](https://github.com/supabase/storage/blob/024b4c7fc9b5724c1efc9aa91f5940e3c6848067/migrations/tenant/0062-object-versioning-core.sql#L38-L43)); null or unknown versions must be rejected by this candidate.

## Conditions for an isolated reader candidate

This is a proposed validation boundary, not a deployment authorization:

1. Obtain trusted deployed-revision/capability evidence. In a separate approved staging fixture, prove that an existing internal version retrieves its selected bytes and that an unknown version fails. An ignored query must be detected. Do not probe real employee files or write production test objects.
2. Use only the fixed trusted HTTPS Storage origin and authenticated versionId REST route. Encode every path segment; reject redirects, transformations, ranges, partial/304 responses, null/unknown versions, unsafe names, and incompatible response encoding. Never remove the version query as a fallback.
3. Read authoritative metadata before and after the bounded full download. Match company-scoped bucket/path, row ID, selected internal version, and non-archived/non-delete-marker state. A version-specific metadata endpoint can return an old row, so a separate current-row check is necessary where the SQL contract requires the current row. Do not silently interpret missing migration flags as a proven false value.
4. If ETag is used, take it from trusted metadata and bind it with If-Match. Do not equate ETag with SHA-256. Independently hash the exact complete downloaded bytes and match the selected SHA-256 and size, then run the existing parser. Receipt insertion and apply must still recheck current object identity/version and all existing authorization/CAS predicates.
5. Establish that the selected version's bytes cannot be rewritten through any enabled upload, multipart, retry, restore, privileged database, or physical-backend path. Source UUID allocation is useful evidence but is not sufficient by itself to establish that operational invariant. Bound time/memory and abort actual streams; prohibit credentials/paths/bytes in logs.

Even after a mock HTTP reader passes, it is a candidate only. Current unresolved gates include deployed capability, actual least-privilege DB/Storage credentials, writer constraints, trusted GoTrue verification, real parser isolation, origin/cache behavior, failure/retry tests against staging, and production approval. Keep public route/Storage allowance/feature enablement absent.

## Changelog check

The official [changelog index](https://supabase.com/changelog.md) was read; the relevant current HTTP transport notice is [CBC TLS cipher deprecation](https://supabase.com/changelog/cbc-tls-ciphers-deprecated), announced 2026-10-12 for removal no earlier than 2026-11-10. A modern verified TLS connection is required; this notice is not evidence that REST versionId support is deployed. No infrastructure or TLS setting was changed.
