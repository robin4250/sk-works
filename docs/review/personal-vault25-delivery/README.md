# Personal PDF private Storage transport candidate

Build25 review only. Based on download-size branch 2c3cb37a, which already contains the bounded-stream branch's shared helper. No parallel reimplementation of that helper.

The delivery coordinator passes the saved receipt's exact size and SHA-256 into a server-only private Storage GET transport. It streams into the existing bounded reader, rejects redirects, error bodies, unexpected MIME/encoding/length, oversize/truncated bytes and receipt-hash mismatches. A global deadline also terminates unresponsive fetch/reader adapters; cancellation is not awaited indefinitely. There are no retries. Only a server-configured publishable key and an independently verified user bearer provider are accepted; no service key or public/signed download URL.

The Storage REST endpoint reads the current object. Matching bytes by saved hash is not proof that immutable historical versions are retained. Real Storage RLS, live GoTrue/session binding, immutable retention, and an independent owner-only PDF content inspector remain unconnected and unverified. This is not a deployable endpoint and must not be enabled.

Validation: 19 isolated Node/PGlite tests passed locally (including coordinator-to-transport composition). The dedicated dependency-free CI runs transport, shared bounded stream and byte verification tests; this is synthetic fetch, not a real Storage access test. No production requests/data/keys were used.

Official API checked: Supabase Storage private bucket access and storage-js StorageFileApi.download (GET /storage/v1/object/{bucket}/{path}, user Authorization header). Changelog checked 2026-10-28: current TLS deprecation requires a current TLS stack; no new SDK dependency introduced.
