# Personal PDF private Storage transport candidate

Build25 review only. Based on download-size branch 2c3cb37a, which already contains the bounded-stream branch's shared helper. No parallel reimplementation of that helper.

The delivery coordinator passes the saved receipt's exact size and SHA-256 into a server-only private Storage GET transport. It streams into the existing bounded reader, rejects redirects, error bodies, unexpected MIME/encoding/length, oversize/truncated bytes and receipt-hash mismatches. A global deadline also terminates unresponsive fetch/reader adapters; cancellation is not awaited indefinitely. There are no retries. Only a server-configured publishable key and an independently verified user bearer provider are accepted; no service key or public/signed download URL.

The Storage REST endpoint reads the current object. Matching bytes by saved hash is not proof that immutable historical versions are retained. Real Storage RLS, live GoTrue/session binding, immutable retention, and an independent owner-only PDF content inspector remain unconnected and unverified. This is not a deployable endpoint and must not be enabled.

Validation: 19 isolated Node/PGlite tests passed locally (including coordinator-to-transport composition). The dedicated dependency-free CI runs transport, shared bounded stream and byte verification tests; this is synthetic fetch, not a real Storage access test. No production requests/data/keys were used.

Official API checked: Supabase Storage private bucket access and storage-js StorageFileApi.download (GET /storage/v1/object/{bucket}/{path}, user Authorization header). Changelog checked 2026-10-28: current TLS deprecation requires a current TLS stack; no new SDK dependency introduced.

## Source snapshot binding candidate

The owner-only `personal_vault25_source_mine` review-only RPC returns the saved catalog company/worker/source IDs, revision, source snapshot hash, manifest hash and kind. The delivery coordinator now requires an `own-snapshot-v2` trusted inspector receipt bound to all of these fields, in addition to actor, manifest, artifact and PDF hash. It rereads the binding after inspection and rejects changed context. Old v1 proofs and proofs for a different source/revision/snapshot are rejected. This adds no production endpoint and is not applied.

The catalog records are still supplied by a trusted exporter; this binding does **not** prove that the source snapshot was independently owner-filtered or that arbitrary PDF content contains no third-party information. No proof issuer is implemented here. Text-only PDF observations must never be adapted to `passed:true`; existing signature/stamp images and original PDFs are unchanged. Storage immutable historical retention, actual source projection/provenance, inspector authority, deployment and device checks remain incomplete.

Validation: 12 isolated Node/PGlite coordinator tests passed, including every source-binding field mismatch, stale binding after inspection, foreign/expired actor and anonymous/service ACL rejection. Native PostgreSQL source-binding checks are added to the catalog CI. Sessions in this new SQL test are synthetic; existing real GoTrue/Storage tests are separate.

## Integrated v2 real RPC/Storage validation

The disposable real-boundary runner now applies the existing read APIs and source-binding RPC, reloads only its local PostgREST schema cache, and calls the v2 coordinator through real user JWT / PostgREST and private Storage GET. It requires the exact company/worker/source/revision/snapshot/manifest/kind tuple, rejects every changed proof field and old v1 proofs, rejects a real catalog revision change during inspection, and rejects expiry during inspection. Foreign users must fail before the Storage downloader is called. The independent content-inspection proof issuer and storageMetadata adapter remain explicit test fixtures; no real owner-only content proof or immutable Storage retention is claimed. No production credentials or objects are accessed. Native/real-stack execution is CI-only; local Node syntax was checked.

## Stable selected-document authorization

The coordinator detaches the selected list entry before source lookup and independently restricts the saved source kind to own attendance/payroll. A regression demonstrates that a mutable adapter-owned list entry could otherwise change its already-accepted kind while awaiting source lookup. The old implementation accepted the synthetic substituted kind; the fixed implementation rejects before Storage download. All 14 isolated Node/PGlite coordinator tests passed. This is an in-process adapter mutation regression, not evidence of an exploited production API. It does not establish independent owner-only PDF inspection or immutable Storage retention; signature/stamp images and production records remain unchanged.


## Create-only upload candidate

`storage_create_only_transport.mjs` is a server-internal standard upload boundary for already frozen, independently owner-authorized PDFs. It accepts at most 6 MiB (larger originals remain unsupported and must not be truncated), detaches the buffer before awaiting credentials, verifies its digest/basic PDF envelope, and makes exactly one POST with `x-upsert: false`. It never retries an unknown outcome, updates an existing object, writes Storage SQL, records a catalog receipt or seals a manifest. Credentials/provider errors are not returned. A success returns only `created_unverified`; read-back/hash verification and trusted metadata remain required.

This is **not immutable retention/object lock or independent owner-content inspection**. Privileged Storage operators can still alter/delete provider objects, and no authenticated upload route or application INSERT grant is added. The real disposable Storage test uses an explicit fixture bridge with its isolated exporter credential and proves duplicate POSTs preserve the original bytes/version; it is not a production owner-upload authorization test. Existing signature/seal originals and renderers are unchanged.

Official API references: [standard uploads](https://supabase.com/docs/guides/storage/uploads/standard-uploads), [Storage access control](https://supabase.com/docs/guides/storage/security/access-control), [Storage schema is read-only](https://supabase.com/docs/guides/storage/schema/design). Local Node synthetic tests cover exact POST/no overwrite, byte detachment, invalid digest/size/path, deadline and redirect/error handling. Real Storage duplicate preservation runs in the existing disposable CI. Production deployment, independently controlled retention, frozen original-owner snapshot inspection and endpoint wiring remain incomplete.
