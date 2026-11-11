"""Prepare private offline review material only. No apply/deploy/ON interface."""
from __future__ import annotations
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys

# Resolve the source-owned sibling, never an input-selected executable/module.
sys.path.insert(0, str(Path(__file__).absolute().parent))
from qualify_inputs import (PINS, SOURCES, UNRESOLVED, Rejected, canonical, digest,
                            fail, qualify, read_file, safe_path, strict_json,
                            verify_segments, keys)


def new_file(path: Path, data: bytes):
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    fd = os.open(path, flags, 0o600)
    with os.fdopen(fd, "wb") as stream:
        stream.write(data)
        stream.flush()
        os.fsync(stream.fileno())


def new_directory(path: Path):
    for component in [path, *path.parents]:
        if component.is_symlink():
            fail("symlink_output", "Output paths cannot traverse symlinks.")
    if path.exists():
        fail("output_exists", "Review preparation never overwrites an earlier output.")
    if not path.parent.is_dir():
        fail("output_parent_missing", "Create the private output parent separately.")
    path.mkdir(mode=0o700)


def stage_file(root: Path, relative: str, data: bytes):
    target = root / relative
    # All ancestors below this newly owned directory are created by this process.
    parents = list(target.relative_to(root).parents)[:-1]
    for parent in reversed(parents):
        directory = root / parent
        if directory.exists():
            if directory.is_symlink() or not directory.is_dir():
                fail("staging_path_changed", "A private staging path changed.")
        else:
            directory.mkdir(mode=0o700)
    new_file(target, data)
    return target


def prepare(input_root: Path, manifest_path: str, output: Path):
    report, state = qualify(input_root, manifest_path)
    if not report["static_qualified"]:
        return {**report, "preparation": "blocked", "output_created": False}, 2
    output = output.absolute()
    new_directory(output)
    new_file(output / "qualification-report.json", canonical(report) + b"\n")
    try:
        stage = output / "private-inputs"
        stage.mkdir(mode=0o700)
        builder = stage_file(stage, "fixed-builder.py", state["blobs"]["builder"])
        if digest(builder.read_bytes()) != PINS["builder"]:
            fail("staged_builder_changed", "The staged fixed builder differs.")
        source_root = stage / "sources"
        source_root.mkdir(mode=0o700)
        for name, (_, relative) in SOURCES.items():
            stage_file(source_root, relative, state["blobs"][name])
        formal = stage_file(stage, "formal.json", canonical(state["engine_inputs"]["formal"]))
        hub = stage_file(stage, "hub.json", canonical([{"metadata": state["engine_inputs"]["hub"]}]))
        expected = stage_file(stage, "expected.json", canonical(state["expected_records"]))
        # Keep a readable JSON copy of the exact PG preimage without parsing or
        # reserializing it for hashing (numeric spellings remain intact).
        dependency = strict_json(state["blobs"]["dependency_snapshot"])
        stage_file(stage, "dependency-snapshot-parsed.json", dependency["snapshot_text"].encode())
        stage_file(stage, "dependency-capture-original.json", state["blobs"]["dependency_snapshot"])
        capsule = output / "review-capsule"
        capsule.mkdir(mode=0o700)
        command = [sys.executable, "-I", "-B", str(builder), "--formal-catalog", str(formal),
                   "--hub-catalog", str(hub), "--expected-fixture", str(expected),
                   "--formal-root", str(source_root), "--hub-root", str(source_root), "--output", str(capsule)]
        # The pinned program imports only stdlib and has no DB/network calls.
        # No project credentials or caller-controlled interpreter flags are forwarded.
        result = subprocess.run(command, cwd=stage, env={"PATH": os.defpath, "LANG": "C.UTF-8", "LC_ALL": "C.UTF-8"},
                                capture_output=True, timeout=30, check=False, umask=0o077)
        if result.returncode != 0:
            fail("offline_builder_failed", "The fixed offline builder failed; private partial output is retained.")
        if len(result.stdout) > 65536 or len(result.stderr) > 65536:
            fail("offline_builder_output_bound", "The fixed builder exceeded its diagnostic bound.")
        receipt = strict_json(result.stdout)
        keys(receipt, {"status", "before_functions", "after_scope", "sql_sha256"}, "Fixed builder receipt")
        if receipt.get("status") != "review bundle generated, not applied" or type(receipt.get("before_functions")) is not int or receipt["before_functions"] != 10 or type(receipt.get("after_scope")) is not int or receipt["after_scope"] != 13:
            fail("offline_builder_receipt", "The fixed builder did not return the expected review-only receipt.")
        generated = read_file(capsule / "atomic-forward.sql.review-only")
        if digest(generated) != receipt.get("sql_sha256"):
            fail("generated_sql_integrity", "Generated review SQL differs from its builder receipt.")
        # Verify every retained functional source segment; metadata rebinding is
        # distinct from a change to the immutable C0c1a historical capsule.
        segment_blobs = {**state["blobs"], "capsule": generated}
        segment_hash = verify_segments(segment_blobs)
        if segment_hash != report["retained_source_segments_sha256"]:
            fail("generated_source_drift", "Generated functional source segments differ.")
        root = input_root.absolute()
        if digest(read_file(safe_path(root, manifest_path))) != state["manifest_sha256"]:
            fail("input_changed", "The manifest changed during preparation.")
        for name, ref in state["manifest"]["inputs"].items():
            if digest(read_file(safe_path(root, ref["path"]))) != report["input_hashes"][name]:
                fail("input_changed", "A verified input changed during preparation.")
        result_manifest = {
            "contract": "sko.formal_c.source_review_material.v1", "preparation": "review_material_created",
            "deployable": False, "sql_executed": False, "production_changed": False,
            "builder_sha256": PINS["builder"], "retained_capsule_sha256": PINS["capsule"],
            "review_sql_sha256": digest(generated), "source_segments_sha256": segment_hash,
            "input_hashes": report["input_hashes"], "before_functions": 10, "expected_after": 13,
            "receipt_scope": 18, "live_capture_or_maintenance_authority_verified": False,
            "review_capsule_quarantined": True, "legacy_restore_operationally_authorized": False,
            "ready_to_apply": False,
            "unresolved_requirements": UNRESOLVED.copy(),
        }
        new_file(output / "OPERATION-PROHIBITED.json", canonical({
            "quarantined_directory": "review-capsule", "apply_authorized": False,
            "maintenance_authority_verified": False, "legacy_restore_authorized": False,
            "reason": "Ingress/drain and modern read/RAM/queue exposure are unproven. Old builder restore guidance is historical review material, not an operational plan.",
            "unknown_exposure_action": "retain guarded writers and review forward repair",
            "saved_modern_row_count_zero_is_insufficient": True,
        }) + b"\n")
        new_file(output / "review-material-manifest.json", canonical(result_manifest) + b"\n")
        return result_manifest, 0
    except (Rejected, subprocess.TimeoutExpired, OSError, ValueError) as error:
        code = error.code if isinstance(error, Rejected) else "private_preparation_failed"
        failure = {"preparation": "failed", "code": code, "output_created": True, "partial_output_retained": True,
                   "deployable": False, "sql_executed": False, "production_changed": False}
        if not (output / "preparation-failure.json").exists():
            new_file(output / "preparation-failure.json", canonical(failure) + b"\n")
        return failure, 2


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input-root", required=True, type=Path)
    parser.add_argument("--manifest", default="manifest.json")
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    try:
        result, status = prepare(args.input_root, args.manifest, args.output)
    except (Rejected, OSError):
        result, status = {"preparation": "refused", "deployable": False, "sql_executed": False, "production_changed": False}, 2
    print(json.dumps(result, sort_keys=True))
    return status


if __name__ == "__main__":
    raise SystemExit(main())
