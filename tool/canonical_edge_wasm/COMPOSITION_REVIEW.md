# Fixed site-order HTTP and private canonical renderer composition — HOLD

`stage_workflow.py` fills the previous hand-copy gap. It verifies the five
reviewed HTTP/coordinator files at `e84fc59681282136187d20bb80760c2b339d6895`
against `workflow_source_pins.json`, verifies the generated canonical runtime
receipt, and stages exactly ten source/runtime files into a new private tree.
The original relative import from the HTTP handler to the pure DB coordinator
is preserved. No handler, coordinator, Auth policy, SQL, configuration or existing
deployment is edited. Later site workflow changes require an explicitly reviewed
pin update; this tool never adopts a moving branch.

The fixed Wasm source remains PR #1646 at
`3fab7b810091f1909d90d0ce3b878e3e784e1060`, using its original 25-file/6-asset
manifest. Compiling again with Dart 3.13.7 produced the same Wasm/glue/runtime
hashes as the retained proof. The prior successful cold, negative and pixel
comparison suites were not repeated for this composition-only change.

## Reproducible new checks

After the unchanged locked canonical build:

```sh
python3 tool/canonical_edge_wasm/stage_workflow_test.py
python3 tool/canonical_edge_wasm/stage_workflow.py --source-root . --output /new/private/site-order-tree
```

The new staging tests verify ten exact files, byte/hash/mode receipts, refusal to
overwrite an existing destination, and source drift/symlink refusal before any
destination is created. No `.env`, project config, customer seal/original, runtime
credential, node_modules or previous release is copied.

The dedicated composition CI caches the actual pinned npm imports in official
Deno 1.46.3, records the resolved lockfile, then runs the real reviewed runtime
import and real staged PDF adapter with `--cached-only` and a frozen lock. It
allows no network or project environment during execution. Four fixed nonsecret
Node compatibility variables are populated with synthetic values. It imports the
runtime without calling `serveSiteOrderWorkflow`, creating a network listener,
reading Supabase environment variables or connecting to a database. It checks
three rejected HTTP boundaries without invoking DB/render and renders one
existing synthetic immutable evidence case through the staged real Wasm.

This is import/composition evidence, not real JWT authentication, DB authorization,
delivery, runtime quota or hosted execution. A generated dependency lock must be
reviewed and retained before any deployment. The local Deno native npm-cache step
could not reach the registry in this environment; dedicated CI results must be
checked on its exact source head rather than inferred from local syntax/staging.

## Configuration and remaining deployment gates

The fixed target is now `site-order-workflow`. The following is a review fragment
to merge into the existing project config, **not a replacement config**:

```toml
[functions.site-order-workflow]
static_files = ["./functions/site-order-workflow/_canonical/main.wasm"]
```

Preserve existing static entries, JWT verification and every other project
setting. The staging script deliberately does not write or copy this fragment.
Use the installed official CLI's `--help` before forming commands. A local
Docker/CLI serve/bundle and its complete resulting bundle size are still needed;
the 14,362,129 bytes of staged source/static files exclude npm dependency and
bundling overhead. This is below the documented CLI 20 MB ceiling but does not
prove that the complete bundle fits. API/static deployment is not supported by
the documented path; do not switch to an API upload or weaken JWT verification.

Keep feature OFF and production HOLD. Real secrets, deployment, public delivery,
hosted WasmGC/CPU/memory limits, approved backend installation, new-session and
unknown-operation recovery, and owner iPhone evidence are separate unfinished
gates. This source preparation grants none of those approvals.

Official Supabase docs were checked again on 2026-10-31:
`/docs/guides/functions/wasm` documents Deno 1.46, CLI >= 2.7 static-file config and
Docker rather than `--use-api`; `/docs/guides/functions/limits` documents the
20 MB bundled size, 2-second CPU and 256 MB memory limits. No applicable breaking
change was established from the unavailable changelog fetch; that uncertainty is
not replaced with a compatibility claim.
