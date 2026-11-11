# Private CLI/static deployment preparation — HOLD

This is a preparation recipe, **not approval to deploy**. No project config, Edge
handler, JWT verifier, database coordinator or production secret is changed here.
The site-order owner must supply the already reviewed request admission and
private transactional coordinator. Initial feature OFF remains mandatory.

## Renderer port agreement

Generated `edge_adapter.mjs` exports `createCanonicalEdgeRenderer()`, resolving to
`async (trustedEvidence) => Uint8Array`. It accepts structured evidence, changes
none of it, and returns only actual canonical PDF bytes. No HTTP/body/request or
DB connection is accepted. It does not claim evidence is authorized: only the
owner's existing coordinator may load immutable evidence after live JWT, company,
role, SID, master flag, site/doc/trade and connection checks. Caller-supplied seal,
PDF or arbitrary rendering SQL must never reach this adapter.

The singleton worker initializes the pinned runtime once and permits one active
render. Concurrent work fails closed; the coordinator must preserve the same
request/job identity and original-byte retry contract. No automatic DB retry is
added. COMMIT-unknown connection handling remains exclusively with the coordinator.
Do not bypass private registration by uploading bytes with a service-role storage
client. Print/send/notification completion requires their own committed receipts.

## Prepare without installing or deploying

1. Run the locked build and dedicated CI. Review the exact source SHA, generated
   `build/build-receipt.json`, official runtime pins and all actual PDF comparisons.
2. Run `python3 tool/canonical_edge_wasm/stage_static.py --output /new/private/path`.
   Destination must not exist. The script verifies fixed compiled hashes and
   sizes, stages only five fixed private runtime files, and writes a manifest.
   It never reads a project, credentials, env secrets or network, invokes CLI,
   creates an HTTP handler, or deploys. Stage on a private filesystem, not a public
   assets directory, static website, client app bundle or public storage bucket.
3. The owner may compose these files with the existing reviewed Edge handler in
   a separate disposable Supabase project checkout. Keep `runtime.mjs`, generated
   glue/support and Wasm together; adapter imports only its fixed sibling runtime.
   No runtime asset URL or remote seal endpoint is needed. The six fixed font/
   test-seal assets are already inside the verified Wasm; existing real originals
   and company-specific seals must never be published by this step.
4. The exact function config must add only its Wasm static file to the existing
   function's `static_files` list, preserving prior entries. Example placeholder:

   ```toml
   [functions.EXISTING_REVIEWED_FUNCTION]
   static_files = ["./functions/EXISTING_REVIEWED_FUNCTION/private_renderer/main.wasm"]
   ```

   The owner must verify path resolution with the installed official CLI and local
   Docker Edge runtime. There is deliberately no runnable deployment command here:
   function name, reviewed handler, project binding and real bundle are not yet
   established. Do not replace a config or disable JWT verification to make it run.
5. Before any requested production approval, locally bundle/serve with official
   Supabase CLI + Docker and measure the complete bundle. This stage's roughly
   14.35 MB alone is below the documented CLI 20 MB limit but above API/dashboard
   5 MB. Remaining imports/handler/dependencies count too. No API upload fallback.
6. Test exact hosted-compatible runtime, initialization, concurrent requests,
   private file access, fixed-artifact tamper refusal, CPU and memory. Published
   limits are 2 seconds CPU/request and 256 MB memory. Local Linux Deno success
   does not establish the hosted runtime's WasmGC or quotas. The earlier raw
   embedding overrun remains in the proof, and gzip results are observations only.
7. Only after root/user approval of exact target, impact, validation and recovery
   may the owner run a reviewed CLI deployment. Keep feature OFF, preserve prior
   immutable release and originals, and use the existing forward recovery process.
   No credential or DB password should be printed/copied into this directory.

## Still unverified

Local Docker/Supabase CLI bundle, hosted Edge execution/quota, reviewed HTTP/JWT
composition, private database coordinator integration, delivery/notification workers
and iPhone-visible behavior. No deployment, production feature activation or
security-complete claim follows from this artifact.

Official references: https://supabase.com/docs/guides/functions/wasm and
https://supabase.com/docs/guides/functions/limits (checked 2026-10-30).
