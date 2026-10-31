# Offline Formal C review qualification

This is a review-material tool, not a deployment or maintenance controller. It has no apply, ON, send, credential or network interface. The retained C capsule and published offline builder remain unchanged. Its report always says `deployable:false` and `sql_executed:false`, including when static input checks pass.

## Fixed sources and authority

The immutable capsule SHA256 is `0c1a57402c666e991001814af5cdaa0f5bde138bf05e533c3e375bffb2d0e8f4`. The builder is the published `tool/build_trade_document_deployment_review.py` at `74b7107392e3144d37612ec311636f602088f18b`, SHA256 `9df1d1863857fa12967b35d76a65004c02a64001f4b54d64bdddb20119d59f8d`. The four C/terms/v1/v2 SQL hashes are fixed in the qualifier. Their functional segments must reconstruct the retained capsule byte-for-byte.

Input files are canonical plain JSON and regular files beneath a private input root. The manifest schema enumerates every input; unknown fields, duplicate JSON keys, non-JSON numbers, parent traversal and symlinks are refused. Declared file hashes are independently recomputed and do not replace the fixed reviewed anchors.

The known before catalog is bound to ten original functions. Current formal3/hub8 records must have the exact ten-record union, complete definitions/body hashes/pg_proc attributes, full master table and unchanged constraints. No existing owner, authorization dependency, invoker/definer flag, OID or required authenticated EXECUTE grant is relaxed.

The complete reviewed afterA dependency snapshot is anchored to `df97cfe987e2701d6d1abf5a484e3b04e9fb47faba492c0f050fd9a49a9704a9`, and its historical wrapper file to a separate fixed digest. The current PostgreSQL `snapshot_text` is hashed **before parsing or reserialization**. It covers the existing reviewed projection: 1021 functions, seventeen relations, declared schemas/default ACLs, role authority and fixed document-bucket configuration. That query excludes only the four B functions and already-reviewed B trigger/policies, which are independently covered by the B module anchor. It is not an assertion that every relation or external route in the project has been audited.

The historical wrapper crossed a JavaScript transport that rendered two numeric defaults as `10`/`0` instead of the PostgreSQL preimage's `10.0`/`0.0`. The qualifier does not normalize these or omit catalog fields. The full raw PostgreSQL preimage digest is the authority, not a redundant strict comparison to that lossy projection. Retain the original capture and a readable JSON copy of the exact preimage; successful preparation writes both privately. Other typed metadata comparisons remain strict, including boolean versus number.

B is bound to four complete current function records and the full raw module preimage `8a3464a52f8e0b174ddd47bcd5109258e0689dbc814bc404a4b57e931b19c068`, together with the exact independently saved activated installation receipt. A supplied `module_matches:true` is insufficient. This checks catalog integrity and receipt identity, not the current rollout row or a real employee-document/Storage operation.

## Required expected13 capture

No actual full-definition expected13 capture receipt is registered yet. Missing or self-asserted captures therefore block qualification and preparation. Do not construct `pg_get_functiondef` strings from stored attributes/prosrc to make the tool run.

The existing frozen published producer is `tool/prepare_trade_document_atomic_review_fixture.py` at the same fixed commit. Its generated ordered fixture writes `expected-after-fixture.json` with thirteen actual records: `schema`, `name`, `arguments`, `definition`, `source_md5`, `attributes`, `owner`. The old workflow retains only an atomic summary artifact, not those full definitions. Obtaining and retaining that real file is a separate, purpose-specific Native capture step; the generic1711 rehearsal is not a replacement.

After independent review of that capture and its run/job/source/artifact digest, a source-reviewed receipt digest can be registered in `TRUSTED_EXPECTED_CAPTURE_RECEIPTS`. There is no CLI or manifest bypass. The receipt format is `sko.formal_c.native_expected_capture.v1` with `artifact_sha256`, fixed `source_commit`, the four `source_pins`, `runtime:postgresql`, actual `server_version_num`, `job_id` and `run_id`.

The adapter validates the producer's real owner field and losslessly renames `arguments` to `identity`. It preserves the captured full definitions. Only the four cluster-local fields already resolved by the original builder—function OID, namespace, postgres owner and language OIDs—may vary in expected-after metadata, with consistent captured bindings. Every other source, ACL and attribute remains exact. Actual Auth/GoTrue/hosted behavior is not established by that metadata capture.

## Commands

```bash
python3 tool/formal_c_rebind_review/qualify_inputs.py \
  --input-root /absolute/private/input-root --manifest manifest.json

python3 tool/formal_c_rebind_review/prepare_review.py \
  --input-root /absolute/private/input-root --manifest manifest.json \
  --output /absolute/private/new-review-output
```

Blocked inputs return exit2 and create no preparation output. An eligible preparation invokes only the fixed builder under isolated Python with a minimal environment, no forwarded project credentials, a thirty-second bound and a new0700 directory/0600 files. Existing outputs are never overwritten. Changed inputs, failed receipts or builder failure retain private partial material with a failure marker. Generated SQL is review-only and is never executed.

The currently unavailable expected13 input means successful end-to-end material generation has not been demonstrated. Do not report that path as verified because refusal tests pass.

## Verification and operational limits

```bash
python3 -m unittest discover -s tool/formal_c_rebind_review -p test_qualification.py -v
```

Eleven public refusal/output tests need no private project material. Nine additional tests use `SKO_FORMAL_C_TEST_INPUT_ROOT` to exercise the actual private capture package without committing it: valid C10/master/afterA/B bindings, missing expected13, metadata/ACL drift, claimed hashes, fake Native receipts and preserved private authenticated EXECUTE. The local combined run passes20 tests; the public-only run intentionally skips9 private-material tests. These are source/input checks, not production or iPhone tests.

Actual ingress closure, old accepted work, private/direct/dynamic callers, idle/active/prepared transactions and queue/pool outcomes remain unqualified. Existing public save is an invoker wrapper; an owner-only private helper cannot simply be added there, and required authenticated EXECUTE must not be stripped or the wrapper changed to DEFINER to bypass that fact. No new guard/table/bootstrap/RPC or Auth change is implemented here.

Feature OFF is not ordinary-write admission. After modern input/read exposure, zero saved modern rows does not rule out RAM or queued drafts; unknown exposure prohibits old-saver restoration. Retain originals/history and repair forward by default. Any actual maintenance controller, production application, activation, restored availability, user operation or iPhone update requires its own explicit scope, evidence and authorization.
