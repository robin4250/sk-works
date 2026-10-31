"""Offline input integrity for Formal C review material. Never applies SQL."""
from __future__ import annotations
import argparse
import hashlib
import json
import re
from datetime import datetime
from pathlib import Path, PurePosixPath

CONTRACT = "sko.formal_c.offline_review.v1"
SOURCE_COMMIT = "74b7107392e3144d37612ec311636f602088f18b"
PINS = {
    "capsule": "0c1a57402c666e991001814af5cdaa0f5bde138bf05e533c3e375bffb2d0e8f4",
    "builder": "9df1d1863857fa12967b35d76a65004c02a64001f4b54d64bdddb20119d59f8d",
    "known_before": "1314526f956e5383e60209a8d1ac219cf87c90513561a8c162b03cc7380a9d5d",
    "after_a_reference": "72b4dfd53489d0650d23f0f30670d875d24daf7723d0572c383fc767b8a4151a",
    "source_c": "7796c2e7bcc7a9eca78f1b79ce8cfc87fcd978c1dc4a4ddb7a5a8ced17b597e5",
    "source_terms": "e5967ad6b5d54f413ba7db94887423f1f5c98057cafae6c1abed318ce171da5a",
    "source_v1": "d57918a806b72e0d52299a3e175c9841258eaa71ce18f2abaab0a7877bd62178",
    "source_v2": "bc53ac3daa85452c032d2e2880ca334fe1ce4aee4601cf9cc0be9c6d09818a79",
}
SOURCES = {
    "source_c": ("C", "docs/review/trade-documents-hub/master-and-standalone-context.sql.review-only"),
    "source_terms": ("terms", "docs/review/trade-document-terms/save-guard.sql.review-only"),
    "source_v1": ("v1", "docs/review/trade-document-form-input/server-save.sql.review-only"),
    "source_v2": ("v2", "docs/review/trade-document-month-end/server-upgrade.sql.review-only"),
}
ARTIFACTS = tuple(PINS) + ("formal_catalog", "hub_catalog", "dependency_snapshot", "b4_catalog", "b4_module", "expected_after", "expected_capture_receipt")
AFTER_A = "df97cfe987e2701d6d1abf5a484e3b04e9fb47faba492c0f050fd9a49a9704a9"
B_MODULE = "8a3464a52f8e0b174ddd47bcd5109258e0689dbc814bc404a4b57e931b19c068"
B_RECEIPT = {
    "contract": "worker_document_admin_self_correction_guard_v1", "activated": True,
    "before_sha256": AFTER_A, "deployment_id": "de2b53a1043a4d12970e7ba759a8480d",
    "module_sha256": B_MODULE, "source_sha256": "8e7dcb4b2fcc3fe77ada3c5d39333d1cb0802858690fd59584d216436868b04a",
    "before_export_sha256": "2bce6747459ba6c094196168f23914d12196bc03c135d868ef80404500825c3b",
}
B_ATTRIBUTES = {
    "private.worker_document_admin_correction_immutable": "0802814e8128922353c09261dbfc6847b8fd205e68f2571acc6c76990be02ef8",
    "private.worker_document_admin_correction_retains": "32f4ce8496121777cdca6260bebe087a403b0eb231c046f05d833f739a73fd1e",
    "private.worker_document_admin_correction_ticket_guard": "e4205a84ec4d39720a8b0ee980f15341903b4e4166044876adc365a74a7dcf5e",
    "public.worker_document_admin_self_correction": "35b170e7e6ef63435f6fd0bcca5a1211e9d62d817c42886141dd716f12a1e99b",
}
# No actual expected13 full-definition capture has been independently registered.
# Add a receipt digest only after its real fixed-source Native artifact is reviewed.
# No CLI/manifest override, synthetic definition or native:true flag can replace it.
TRUSTED_EXPECTED_CAPTURE_RECEIPTS: frozenset[str] = frozenset({
    # Independent artifact review and root source-only registration decision.
    # This binds capture provenance, never production maintenance authority.
    "c382cf9eaff49862c1af7ac8c822934bbbad24e34efef8a9ffa34e5632a18b7e",
})
UNRESOLVED = [
    "Actual ingress owner, closure acknowledgement and held operation epoch are not established by offline files.",
    "Dynamic/private/direct callers, accepted queues and active/idle/prepared transactions require actual drain evidence.",
    "Live metadata origin and freshness require independent capture/readback; matching files are not authorization.",
    "Modern read/RAM/queue exposure must be resolved before any old-saver restoration; unknown requires forward repair.",
    "Separate production approval and runtime/app verification remain required; orders remain OFF.",
]
MAX_BYTES = 8 * 1024 * 1024

class Rejected(ValueError):
    def __init__(self, code: str, detail: str):
        super().__init__(detail)
        self.code, self.detail = code, detail

def fail(code: str, detail: str):
    raise Rejected(code, detail)

def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()

def canonical(value) -> bytes:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False).encode()

def exact(actual, expected, code="catalog_drift"):
    if canonical(actual) != canonical(expected):
        fail(code, "Typed complete metadata differs from the reviewed reference.")

def keys(value, required, label):
    if not isinstance(value, dict) or set(value) != set(required):
        fail("unexpected_shape", label + " has missing or unknown fields.")

def strict_json(data: bytes | str):
    def pairs(items):
        result = {}
        for key, value in items:
            if key in result:
                fail("duplicate_json_key", "Duplicate JSON fields are forbidden.")
            result[key] = value
        return result
    def invalid(_):
        fail("invalid_json_number", "Non-JSON numeric constants are forbidden.")
    try:
        return json.loads(data, object_pairs_hook=pairs, parse_constant=invalid)
    except Rejected:
        raise
    except (ValueError, UnicodeError, TypeError):
        fail("invalid_json", "Canonical plain JSON input is required; raw MCP wrappers are unsupported.")

def safe_path(root: Path, relative: str) -> Path:
    if not isinstance(relative, str) or not relative or len(relative) > 2048 or "\\" in relative or any(ord(c) < 32 for c in relative):
        fail("unsafe_path", "Artifact paths must be canonical relative POSIX file paths.")
    part = PurePosixPath(relative)
    if part.is_absolute() or ".." in part.parts or part.as_posix() != relative:
        fail("unsafe_path", "Artifact paths must remain inside the input root.")
    current = root
    for item in part.parts:
        current = current / item
        if current.is_symlink():
            fail("symlink_forbidden", "Symlink inputs are forbidden.")
    if not current.is_file():
        fail("missing_file", "A referenced regular input file is missing.")
    return current

def read_file(path: Path) -> bytes:
    if path.stat().st_size > MAX_BYTES:
        fail("input_too_large", "An input exceeds the fixed private-artifact bound.")
    return path.read_bytes()

def timestamp(value):
    if not isinstance(value, str):
        fail("invalid_capture_time", "A timezone-aware capture time is required.")
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
        if parsed.tzinfo is None:
            raise ValueError()
    except ValueError:
        fail("invalid_capture_time", "A timezone-aware capture time is required.")

def literal(capsule: str, declaration: str):
    pattern = re.escape(declaration) + r"\$([A-Za-z_0-9]+)\$([\s\S]*?)\$\1\$::jsonb"
    matches = list(re.finditer(pattern, capsule))
    if len(matches) != 1:
        fail("capsule_contract_missing", "A fixed capsule data declaration is missing or ambiguous.")
    return strict_json(matches[0][2])

def retained_contract(capsule: bytes):
    if digest(capsule) != PINS["capsule"]:
        fail("immutable_pin_mismatch", "The retained C capsule is not the fixed original.")
    text = capsule.decode()
    return {
        "before": literal(text, "create temporary table reviewed_old_functions on commit drop as select value item from jsonb_array_elements("),
        "after": literal(text, "create temporary table reviewed_expected_after on commit drop as select value item from jsonb_array_elements("),
        "table": literal(text, "create temporary table reviewed_master_table on commit drop as select "),
        "constraints": literal(text, "create temporary table reviewed_master_constraints on commit drop as select value item from jsonb_array_elements("),
    }

def signature(row):
    return row["schema"] + "." + row["name"] + "(" + row["identity"] + ")"

def normalise_record(row):
    keys(row, {"schema", "name", "identity", "definition", "source_md5", "attributes"}, "Function record")
    if not all(isinstance(row[k], str) for k in ("schema", "name", "identity", "definition", "source_md5")) or not isinstance(row["attributes"], dict):
        fail("invalid_function_record", "Function metadata types differ.")
    match = re.search(r"\bAS (\$[A-Za-z_0-9]*\$)([\s\S]*?)\1", row["definition"])
    if match is None or hashlib.md5(match[2].encode()).hexdigest() != row["source_md5"]:
        fail("definition_digest_mismatch", "Actual captured definition and source digest differ.")
    if row["attributes"].get("prosrc") != match[2]:
        fail("definition_body_mismatch", "Captured full pg_proc body and definition differ.")
    return row

def unique_records(rows, count):
    if not isinstance(rows, list) or len(rows) != count:
        fail("function_count_mismatch", "The exact reviewed function count is required.")
    result = {}
    for row in rows:
        row = normalise_record(row)
        key = signature(row)
        if key in result:
            fail("duplicate_function", "Function identities must be unique.")
        result[key] = row
    return result

def without_wrapper(text):
    lines = text.splitlines(keepends=True)
    begins = [i for i, line in enumerate(lines) if line.strip().lower() == "begin;"]
    commits = [i for i, line in enumerate(lines) if line.strip().lower() == "commit;"]
    if len(begins) != 1 or len(commits) != 1 or begins[0] >= commits[0]:
        fail("source_wrapper_drift", "Exactly one pinned source transaction wrapper is required.")
    for i in sorted(begins + commits, reverse=True):
        del lines[i]
    return "".join(lines)

def verify_segments(blobs):
    capsule = blobs["capsule"].decode()
    joined = "\n".join("-- Exact source segment " + stage + "\n" + without_wrapper(blobs[name].decode()) for name, (stage, _) in SOURCES.items())
    start = capsule.index("-- Exact source segment C\n")
    end = capsule.index("\ndo $postflight$", start)
    if capsule[start:end] != joined:
        fail("retained_source_drift", "Pinned source segments do not reconstruct the retained capsule exactly.")
    return digest(joined.encode())

def verify_engine_inputs(blobs, contract):
    known = unique_records(strict_json(blobs["known_before"]), 10)
    for old in contract["before"]:
        current = dict(known[signature(old)])
        del current["definition"]
        exact(current, old, "known_before_capsule_mismatch")
    formal = unique_records(strict_json(blobs["formal_catalog"]), 3)
    hub_doc = strict_json(blobs["hub_catalog"])
    if not isinstance(hub_doc, list) or len(hub_doc) != 1:
        fail("unexpected_shape", "One canonical hub metadata row is required.")
    keys(hub_doc[0], {"metadata"}, "Hub result")
    hub = hub_doc[0]["metadata"]
    keys(hub, {"functions", "table", "constraints"}, "Hub metadata")
    hub_functions = unique_records(hub["functions"], 8)
    formal_names = {"partner_company_profile_value", "trade_document_source", "save_trade_document_attachment"}
    if {r["name"] for r in formal.values()} != formal_names or any(r["schema"] != "private" for r in formal.values()):
        fail("formal_scope_drift", "Formal three-function scope differs.")
    combined = dict(hub_functions)
    for key, row in formal.items():
        if key in combined:
            exact(combined[key], row, "shared_capture_mismatch")
        combined[key] = row
    if set(combined) != set(known):
        fail("before_scope_drift", "The exact reviewed ten-function union is required.")
    for key in known:
        exact(combined[key], known[key], "before_function_drift")
    exact(hub["table"], contract["table"], "master_table_drift")
    if not isinstance(hub["constraints"], list):
        fail("unexpected_shape", "Master constraints must be a list.")
    sort_constraints = lambda rows: sorted(rows, key=lambda row: row["attributes"]["conname"])
    exact(sort_constraints(hub["constraints"]), sort_constraints(contract["constraints"]), "master_constraint_drift")
    return {"formal": list(formal.values()), "hub": hub}

def verify_dependency_snapshot(blobs):
    reference = strict_json(blobs["after_a_reference"])
    keys(reference, {"snapshot", "snapshot_sha256"}, "Reviewed afterA reference")
    if reference["snapshot_sha256"] != AFTER_A:
        fail("after_a_anchor_drift", "The afterA dependency anchor differs.")
    current = strict_json(blobs["dependency_snapshot"])
    keys(current, {"captured_at", "snapshot_text", "snapshot_sha256"}, "Dependency capture")
    timestamp(current["captured_at"])
    if not isinstance(current["snapshot_text"], str) or digest(current["snapshot_text"].encode()) != AFTER_A or current["snapshot_sha256"] != AFTER_A:
        fail("dependency_snapshot_drift", "The complete reviewed dependency preimage differs.")
    # The fixed historical wrapper crossed a JS transport that collapsed two
    # JSON numeric spellings (10.0/0.0 to 10/0). Do not normalize fields or hash
    # reserialized data. The independently pinned complete PostgreSQL preimage
    # digest above is authoritative for every field, not that lossy projection.
    actual = strict_json(current["snapshot_text"])
    if len(actual["functions"]) != 1021:
        fail("dependency_function_count", "The reviewed afterA function count differs.")
    return current["captured_at"]

def verify_b4(blobs):
    current = strict_json(blobs["b4_catalog"])
    keys(current, {"captured_at", "functions", "installation_receipt_comment"}, "B4 capture")
    timestamp(current["captured_at"])
    exact(strict_json(current["installation_receipt_comment"]), B_RECEIPT, "b_receipt_drift")
    if not isinstance(current["functions"], list) or len(current["functions"]) != 4:
        fail("b4_count_drift", "Exactly four current B functions are required.")
    records = {}
    for row in current["functions"]:
        keys(row, {"oid", "nspname", "proname", "identity", "definition", "attributes", "owner_name", "comment", "acl"}, "B function capture")
        name = row["nspname"] + "." + row["proname"]
        if name not in B_ATTRIBUTES or name in records or digest(canonical(row["attributes"])) != B_ATTRIBUTES[name]:
            fail("b4_attribute_drift", "Current B full attributes or identities differ.")
        normalise_record({"schema": row["nspname"], "name": row["proname"], "identity": row["identity"], "definition": row["definition"], "attributes": row["attributes"], "source_md5": hashlib.md5(row["attributes"]["prosrc"].encode()).hexdigest()})
        if row["owner_name"] != "postgres" or row["oid"] != row["attributes"].get("oid") or row["proname"] != row["attributes"].get("proname"):
            fail("b4_identity_inconsistent", "Expanded B function identity/owner differs from full attributes.")
        expected_acl = [{"grantor": "postgres", "grantee": "postgres", "privilege": "EXECUTE", "grantable": False}]
        if name.endswith("worker_document_admin_correction_retains") or name.startswith("public."):
            expected_acl.append({"grantor": "postgres", "grantee": "authenticated", "privilege": "EXECUTE", "grantable": False})
        if not isinstance(row["acl"], list):
            fail("b4_acl_inconsistent", "Expanded B ACL must be explicit.")
        for entry in row["acl"]:
            keys(entry, {"grantor", "grantee", "privilege", "grantable"}, "Expanded B ACL")
        sort_acl = lambda entries: sorted(entries, key=lambda entry: (entry["grantee"], entry["grantor"], entry["privilege"]))
        exact(sort_acl(row["acl"]), sort_acl(expected_acl), "b4_acl_inconsistent")
        records[name] = row["attributes"]
    module = strict_json(blobs["b4_module"])
    keys(module, {"captured_at", "module_text", "module_sha256", "receipt", "module_matches"}, "B module capture")
    timestamp(module["captured_at"])
    if not isinstance(module["module_text"], str) or digest(module["module_text"].encode()) != B_MODULE or module["module_sha256"] != B_MODULE:
        fail("b_module_drift", "The raw B module preimage differs; a claimed match is insufficient.")
    exact(module["receipt"], B_RECEIPT, "b_receipt_drift")
    if module["module_matches"] is not True:
        fail("b_capture_inconsistent", "B capture reported an inconsistent comparison.")
    module_data = strict_json(module["module_text"])
    keys(module_data, {"functions", "relations", "types", "trigger", "storage_policies"}, "B module preimage")
    expected = [dict((k, v) for k, v in row.items() if k != "oid") for row in records.values()]
    sort_functions = lambda rows: sorted(rows, key=lambda row: (row["pronamespace"], row["proname"]))
    exact(sort_functions(module_data["functions"]), sort_functions(expected), "b4_module_binding_drift")
    return {"catalog": current["captured_at"], "module": module["captured_at"]}

def compare_expected_metadata(actual_rows, context, retained_rows):
    keys(context, {"server_version_num", "namespaces", "roles", "languages"}, "Expected catalog context")
    if type(context["server_version_num"]) is not int or context["server_version_num"] != 170006:
        fail("expected_runtime_drift", "The reviewed Native PostgreSQL version is required.")
    keys(context["namespaces"], {"public", "private"}, "Expected namespaces")
    keys(context["roles"], {"postgres"}, "Expected owner role")
    keys(context["languages"], {"sql", "plpgsql"}, "Expected languages")
    known = {signature(row): row for row in retained_rows}
    if len(known) != 13 or len(actual_rows) != 13:
        fail("expected_count_drift", "Exactly thirteen expected functions are required.")
    found = set()
    for row in actual_rows:
        key = signature(row)
        if key not in known or key in found:
            fail("expected_scope_drift", "Expected identities are missing, duplicated or unknown.")
        found.add(key)
        expected = known[key]
        exact({k: row[k] for k in ("schema", "name", "identity", "source_md5", "language")}, {k: expected[k] for k in ("schema", "name", "identity", "source_md5", "language")}, "expected_source_drift")
        attrs = row["attributes"]
        dynamic = {"oid", "pronamespace", "proowner", "prolang"}
        if set(attrs) != set(expected["attributes"]):
            fail("expected_attribute_shape", "Full pg_proc attribute sets differ.")
        for value in [attrs[k] for k in dynamic]:
            if not isinstance(value, str) or not value.isdigit() or int(value) <= 0:
                fail("expected_oid_invalid", "Expected cluster-local identifiers must be positive catalog OIDs.")
        exact(attrs["pronamespace"], context["namespaces"][row["schema"]], "expected_namespace_drift")
        exact(attrs["proowner"], context["roles"]["postgres"], "expected_owner_drift")
        exact(attrs["prolang"], context["languages"][row["language"]], "expected_language_drift")
        exact({k: v for k, v in attrs.items() if k not in dynamic}, {k: v for k, v in expected["attributes"].items() if k not in dynamic}, "expected_attribute_drift")

def verify_expected(blobs, contract):
    receipt_data = blobs["expected_capture_receipt"]
    if digest(receipt_data) not in TRUSTED_EXPECTED_CAPTURE_RECEIPTS:
        fail("unreviewed_expected_capture", "No independently reviewed actual expected13 capture receipt is registered.")
    receipt = strict_json(receipt_data)
    keys(receipt, {"contract", "artifact_sha256", "source_commit", "source_pins", "runtime", "server_version_num", "job_id", "run_id"}, "Expected capture receipt")
    if receipt["contract"] != "sko.formal_c.native_expected_capture.v1" or receipt["runtime"] != "postgresql" or receipt["source_commit"] != SOURCE_COMMIT:
        fail("expected_provenance_drift", "Expected capture producer provenance differs.")
    if type(receipt["job_id"]) is not int or type(receipt["run_id"]) is not int or min(receipt["job_id"], receipt["run_id"]) <= 0:
        fail("expected_provenance_drift", "Actual capture run and job identifiers are required.")
    exact(receipt["source_pins"], {name: PINS[name] for name in SOURCES}, "expected_source_pin_drift")
    if receipt["artifact_sha256"] != digest(blobs["expected_after"]):
        fail("expected_artifact_drift", "Expected capture bytes differ from the reviewed receipt.")
    document = strict_json(blobs["expected_after"])
    # Consume the actual frozen published fixture export verbatim. Its
    # `arguments` -> `identity` rename is lossless; `owner` is validated, not
    # fabricated. Full definitions must already be present in the capture.
    if not isinstance(document, list) or len(document) != 13:
        fail("expected_count_drift", "The real published thirteen-record export is required.")
    records = []
    comparison = []
    context = {"server_version_num": receipt["server_version_num"], "namespaces": {}, "roles": {}, "languages": {}}
    for row in document:
        keys(row, {"schema", "name", "arguments", "definition", "source_md5", "attributes", "owner"}, "Published expected capture record")
        if row["owner"] != "postgres" or row["schema"] not in {"public", "private"}:
            fail("expected_owner_drift", "The fixed published fixture must retain its known owner and schemas.")
        normal = normalise_record({"schema": row["schema"], "name": row["name"], "identity": row["arguments"],
                                   "definition": row["definition"], "source_md5": row["source_md5"], "attributes": row["attributes"]})
        language = re.search(r"\bLANGUAGE ([a-z0-9_]+)", normal["definition"])
        if language is None or language[1] not in {"sql", "plpgsql"}:
            fail("expected_language_missing", "Actual expected definitions must declare a known language.")
        for group, name, oid in [("namespaces", row["schema"], row["attributes"]["pronamespace"]),
                                  ("roles", row["owner"], row["attributes"]["proowner"]),
                                  ("languages", language[1], row["attributes"]["prolang"])]:
            if name in context[group]:
                exact(context[group][name], oid, "expected_context_inconsistent")
            context[group][name] = oid
        records.append(normal)
        comparison.append({**{k: v for k, v in normal.items() if k != "definition"}, "language": language[1]})
    unique_records(records, 13)
    compare_expected_metadata(comparison, context, contract["after"])
    return records

def qualify(input_root: Path, manifest_path: str):
    report = {"contract": "sko.formal_c.source_review_report.v1", "static_qualified": False, "review_material_preparation_permitted": False, "deployable": False, "sql_executed": False, "production_changed": False, "checks": [], "issues": [], "unresolved_requirements": UNRESOLVED.copy(), "b_runtime_enabled_state_rechecked": False}
    state = {"blobs": {}, "manifest": None, "engine_inputs": None, "expected_records": None}
    def check(name, operation):
        try:
            value = operation()
            report["checks"].append({"name": name, "passed": True})
            return value
        except Rejected as error:
            report["issues"].append({"check": name, "code": error.code, "detail": error.detail})
        except (KeyError, IndexError, TypeError, ValueError, OSError):
            report["issues"].append({"check": name, "code": "invalid_input", "detail": "Required typed metadata is missing or inconsistent."})
        report["checks"].append({"name": name, "passed": False})
        return None
    root = input_root.absolute()
    for component in [root, *root.parents]:
        if component.is_symlink():
            report["issues"].append({"check": "input_root", "code": "symlink_forbidden", "detail": "The input root cannot traverse symlinks."})
            return report, state
    def manifest_load():
        raw = read_file(safe_path(root, manifest_path))
        state["manifest_sha256"] = digest(raw)
        value = strict_json(raw)
        keys(value, {"contract", "inputs"}, "Review manifest")
        if value["contract"] != CONTRACT:
            fail("manifest_contract", "The exact offline review contract is required.")
        keys(value["inputs"], ARTIFACTS, "Input references")
        return value
    manifest = check("manifest", manifest_load)
    if manifest is None:
        return report, state
    state["manifest"] = manifest
    blobs = state["blobs"]
    for name in ARTIFACTS:
        def load(name=name):
            ref = manifest["inputs"][name]
            if ref is None:
                fail("missing_input", "A required review input has not been captured.")
            keys(ref, {"path", "sha256"}, "Artifact reference")
            if not isinstance(ref["sha256"], str) or re.fullmatch(r"[0-9a-f]{64}", ref["sha256"]) is None:
                fail("invalid_artifact_digest", "A lowercase SHA256 digest is required.")
            data = read_file(safe_path(root, ref["path"]))
            if digest(data) != ref["sha256"]:
                fail("artifact_integrity", "Referenced bytes differ from the manifest digest.")
            if name in PINS and digest(data) != PINS[name]:
                fail("immutable_pin_mismatch", "A fixed source or reviewed reference differs.")
            blobs[name] = data
        check("input." + name, load)
    def require(names):
        if any(name not in blobs for name in names):
            fail("missing_verified_input", "This check requires missing or rejected input bytes.")
    def contract_load():
        require(["capsule"])
        return retained_contract(blobs["capsule"])
    contract = check("retained_contract", contract_load)
    if contract is not None:
        def segments():
            require(["capsule", *SOURCES])
            return verify_segments(blobs)
        value = check("four_source_segments", segments)
        if value:
            report["retained_source_segments_sha256"] = value
        def engine():
            require(["known_before", "formal_catalog", "hub_catalog"])
            return verify_engine_inputs(blobs, contract)
        state["engine_inputs"] = check("C10_and_master_catalog", engine)
        def expected():
            require(["expected_after", "expected_capture_receipt"])
            return verify_expected(blobs, contract)
        state["expected_records"] = check("actual_expected13_provenance", expected)
    def dependencies():
        require(["after_a_reference", "dependency_snapshot"])
        return verify_dependency_snapshot(blobs)
    value = check("afterA_dependency_preimage", dependencies)
    if value:
        report["dependency_capture_time"] = value
    def b4():
        require(["b4_catalog", "b4_module"])
        return verify_b4(blobs)
    value = check("B4_module_and_current_attributes", b4)
    if value:
        report["b4_capture_times"] = value
    report["static_qualified"] = not report["issues"]
    report["review_material_preparation_permitted"] = report["static_qualified"]
    report["input_hashes"] = {name: digest(data) for name, data in blobs.items()}
    return report, state

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input-root", required=True, type=Path)
    parser.add_argument("--manifest", default="manifest.json")
    args = parser.parse_args()
    report, _ = qualify(args.input_root, args.manifest)
    print(json.dumps(report, sort_keys=True))
    return 0 if report["static_qualified"] else 2

if __name__ == "__main__":
    raise SystemExit(main())
