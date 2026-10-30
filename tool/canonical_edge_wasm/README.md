# Canonical Dart PDF in Deno: offline Wasm feasibility experiment

**Not deployed or production-connected.** This directory adds no application route,
DB writer, Auth change, grant, feature switch, network fetch, or public upload.
It demonstrates that the existing canonical renderer can execute as WasmGC in
stock official Deno, including Deno 1.46.3, without a Dart subprocess.

## Frozen boundary

`source_manifest.json` pins the existing 23-file renderer closure at source
`65eb8fcec6af422c6a78269c273ec900db1d0d42`, two package dependency files, and six
assets. `build.py` rejects any source/hash mismatch. It copies these files into
ignored `build/frozen`; only the copied IO asset loader is replaced. That hook
embeds exactly six gzip/base64 assets, restores original bytes, verifies SHA256,
and caches them. It accepts no arbitrary asset path or URL. The separate new
JSInterop entry invokes the unchanged canonical renderer after evidence checks.
This is an experiment against a pinned historical renderer, not an automatic
adoption of later renderer changes.

`runtime.mjs.in` verifies the compiled Wasm hash, initializes once, captures and
removes the global Dart export, rejects concurrent calls, bounds input/output,
and exposes fixed errors without raw causes. Evidence must come from an existing
trusted canonical coordinator. The wrapper does not authenticate a caller and
must not be exposed as a public endpoint by itself.

## Reproduce (Linux x64)

Use official Dart 3.13.7 with its `wasm-opt` executable and populated locked pub
cache. Install the two exact official npm runtime packages with scripts disabled:

```sh
npm install --prefix tool/canonical_edge_wasm/build/deno --ignore-scripts --save-exact @deno/linux-x64-glibc@2.9.6
npm install --prefix tool/canonical_edge_wasm/build/deno146 --ignore-scripts --save-exact @deno/linux-x64-glibc@1.46.3
chmod u+x tool/canonical_edge_wasm/build/deno146/node_modules/@deno/linux-x64-glibc/deno
python3 tool/canonical_edge_wasm/build.py --source-root /path/to/pinned/source --dart /path/to/dart
python3 tool/canonical_edge_wasm/measure.py
tool/canonical_edge_wasm/build/deno146/node_modules/@deno/linux-x64-glibc/deno run --no-remote --allow-read=tool/canonical_edge_wasm/build tool/canonical_edge_wasm/negative_deno.mjs
```

Verify npm package integrity against `runtime-pins.json`. Runs have read access
only to this build and write access only to its output; no network, environment,
subprocess, or credential permission. `measure.py` uses per-child `wait4` CPU and
peak RSS (Linux units), including startup. Synthetic evidence has no real company,
user, seal, or production data. PDFs and all large binaries remain ignored.

## Observed results

`build-proof.json`, `cold-measurements-proof.json`, and `comparison-proof.json`
record the actual tested artifacts, runtimes and outputs. Gzip Wasm is 14,332,197
bytes plus 12,802-byte glue, 200-byte support and 1,446-byte wrapper. All eight cold
runs (four cases on each runtime) succeeded, total process CPU 1.147–1.529 seconds,
peak RSS 178,098,176–204,230,656 bytes. These are local Linux measurements, not
hosted Edge quotas or performance guarantees.

Four current gzip outputs / eight A4 pages match the native Dart CLI reference in
extracted text and every raster pixel at 2x scale. Order first page and contract
page were rendered and visually inspected. Existing app/CLI equality is separately
established by the upstream renderer fixture; no local Flutter SDK was used here.
Eight invalid/overlapping calls were refused. No successful tests are substituted
with a mock renderer.

The original raw embedding was 19,725,720-byte Wasm. One raw cold run consumed
2.549395 CPU seconds, above the published 2-second hosted request limit. Its proof
is retained; gzip is the tested optimization, not a claim of universal quota fit.

## Unresolved deployment boundary

Supabase publishes 256 MB memory and 2 seconds CPU/request. Local CLI bundle limit
is 20 MB; API/dashboard bundle limit is 5 MB. This approximately 14.35 MB artifact
exceeds API deployment's limit and requires a CLI/static-file path if adopted.
A real Edge bundle-size measurement, hosted runtime execution, hosted CPU/memory,
concurrency/worker lifecycle, immutable artifact deployment root, request admission,
trusted JWT and private DB coordinator composition remain unverified. No production
secret was retrieved. No deployment or feature activation is authorized by this
experiment. A future connection must preserve existing role/company/session/purpose
checks and exact private PDF registration; service-role public storage is not a
substitute.

Primary references checked 2026-10-30:

- https://supabase.com/docs/guides/functions/wasm
- https://supabase.com/docs/guides/functions/limits
- https://dart.dev/tools/dart-compile
- https://dart.dev/web/wasm
- https://dart.dev/interop/js-interop/usage
- https://docs.deno.com/runtime/getting_started/installation/
