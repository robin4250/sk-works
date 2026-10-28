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
