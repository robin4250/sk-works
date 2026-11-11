"""Rejection tests. Real private captures are optional and never committed here."""
import copy
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).absolute().parent
spec = importlib.util.spec_from_file_location("formal_c_q", ROOT / "qualify_inputs.py")
q = importlib.util.module_from_spec(spec)
spec.loader.exec_module(q)
sys.modules["qualify_inputs"] = q
spec_p = importlib.util.spec_from_file_location("formal_c_p", ROOT / "prepare_review.py")
p = importlib.util.module_from_spec(spec_p)
spec_p.loader.exec_module(p)


def write_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")


class RefusalTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.manifest = {"contract": q.CONTRACT, "inputs": {name: None for name in q.ARTIFACTS}}
        self.save()

    def tearDown(self):
        self.temporary.cleanup()

    def save(self):
        write_json(self.root / "manifest.json", self.manifest)

    def artifact(self, name, data):
        path = self.root / (name + ".data")
        path.write_bytes(data)
        self.manifest["inputs"][name] = {"path": path.name, "sha256": q.digest(data)}
        self.save()

    def result(self):
        report, _ = q.qualify(self.root, "manifest.json")
        self.assertFalse(report["static_qualified"])
        self.assertFalse(report["deployable"])
        self.assertFalse(report["sql_executed"])
        return report

    def code(self, report, code):
        self.assertIn(code, {issue["code"] for issue in report["issues"]})

    def test_missing_inputs_cannot_prepare_or_create_output(self):
        report, status = p.prepare(self.root, "manifest.json", self.root / "output")
        self.assertEqual(status, 2)
        self.code(report, "missing_input")
        self.assertFalse(report["output_created"])
        self.assertFalse((self.root / "output").exists())

    def test_readiness_boolean_is_unknown_manifest_field(self):
        self.manifest["deployable"] = True
        self.save()
        self.code(self.result(), "unexpected_shape")

    def test_unknown_input_is_not_a_new_trusted_baseline(self):
        self.manifest["inputs"]["allow_unknown"] = True
        self.save()
        self.code(self.result(), "unexpected_shape")

    def test_duplicate_json_keys_refused(self):
        (self.root / "manifest.json").write_text('{"contract":"first","contract":"second","inputs":{}}')
        self.code(self.result(), "duplicate_json_key")

    def test_non_json_numeric_constant_refused(self):
        (self.root / "manifest.json").write_text('{"contract":NaN,"inputs":{}}')
        self.code(self.result(), "invalid_json_number")

    def test_declared_digest_does_not_authorize_changed_fixed_builder(self):
        self.artifact("builder", b"print('not the reviewed builder')")
        self.code(self.result(), "immutable_pin_mismatch")

    def test_integrity_digest_recomputed(self):
        self.artifact("builder", b"ordinary data")
        self.manifest["inputs"]["builder"]["sha256"] = "0" * 64
        self.save()
        self.code(self.result(), "artifact_integrity")

    def test_symlink_and_parent_paths_refused_before_read(self):
        target = self.root / "target"
        target.write_bytes(b"ordinary data")
        (self.root / "linked").symlink_to(target)
        self.manifest["inputs"]["builder"] = {"path": "linked", "sha256": q.digest(target.read_bytes())}
        self.save()
        self.code(self.result(), "symlink_forbidden")
        self.manifest["inputs"]["builder"]["path"] = "../outside"
        self.save()
        self.code(self.result(), "unsafe_path")

    def test_existing_output_and_files_never_overwritten(self):
        target = self.root / "already"
        target.mkdir()
        saved = target / "original"
        saved.write_bytes(b"preserve")
        with self.assertRaises(q.Rejected):
            p.new_directory(target)
        with self.assertRaises(FileExistsError):
            p.new_file(saved, b"overwrite")
        self.assertEqual(saved.read_bytes(), b"preserve")

    def test_private_output_modes(self):
        target = self.root / "new"
        p.new_directory(target)
        p.new_file(target / "record", b"data")
        self.assertEqual(stat.S_IMODE(target.stat().st_mode), 0o700)
        self.assertEqual(stat.S_IMODE((target / "record").stat().st_mode), 0o600)

    def test_cli_has_no_apply_interface(self):
        result = subprocess.run([sys.executable, str(ROOT / "prepare_review.py"), "--input-root", str(self.root), "--output", str(self.root / "out"), "--apply"], capture_output=True)
        self.assertEqual(result.returncode, 2)
        self.assertFalse((self.root / "out").exists())


@unittest.skipUnless(os.environ.get("SKO_FORMAL_C_TEST_INPUT_ROOT"), "Private actual-capture material is intentionally not committed; local evidence is separate.")
class ActualMaterialTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        original = Path(os.environ["SKO_FORMAL_C_TEST_INPUT_ROOT"])
        self.manifest = q.strict_json((original / "manifest.json").read_bytes())
        for ref in self.manifest["inputs"].values():
            if ref is not None:
                target = self.root / ref["path"]
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(original / ref["path"], target)
        self.save()

    def tearDown(self):
        self.temporary.cleanup()

    def save(self):
        write_json(self.root / "manifest.json", self.manifest)

    def mutate(self, name, operation):
        ref = self.manifest["inputs"][name]
        target = self.root / ref["path"]
        value = q.strict_json(target.read_bytes())
        operation(value)
        write_json(target, value)
        ref["sha256"] = q.digest(target.read_bytes())
        self.save()

    def result(self):
        report, _ = q.qualify(self.root, "manifest.json")
        self.assertFalse(report["deployable"])
        self.assertFalse(report["static_qualified"])
        return report

    def code(self, report, code):
        self.assertIn(code, {issue["code"] for issue in report["issues"]})

    def test_actual_retained_sources_C10_master_AB_and_B4_pass_but_expected13_blocks(self):
        report = self.result()
        passed = {entry["name"] for entry in report["checks"] if entry["passed"]}
        self.assertTrue({"four_source_segments", "C10_and_master_catalog", "afterA_dependency_preimage", "B4_module_and_current_attributes"}.issubset(passed))
        self.assertEqual({issue["check"] for issue in report["issues"]}, {"input.expected_after", "input.expected_capture_receipt", "actual_expected13_provenance"})
        before = {name: q.digest((self.root / ref["path"]).read_bytes()) for name, ref in self.manifest["inputs"].items() if ref}
        _, status = p.prepare(self.root, "manifest.json", self.root / "output")
        self.assertEqual(status, 2)
        self.assertFalse((self.root / "output").exists())
        self.assertEqual(before, {name: q.digest((self.root / ref["path"]).read_bytes()) for name, ref in self.manifest["inputs"].items() if ref})

    def test_C10_service_role_or_typed_flag_drift_is_rejected(self):
        def modify(rows):
            next(row for row in rows if row["name"] == "save_trade_document_attachment")["attributes"]["proacl"].append("service_role=X/postgres")
        self.mutate("formal_catalog", modify)
        self.code(self.result(), "before_function_drift")

    def test_master_unknown_constraint_is_rejected(self):
        self.mutate("hub_catalog", lambda rows: rows[0]["metadata"]["constraints"].append({"attributes": {"conname": "unknown", "oid": "1"}, "definition": "CHECK (true)"}))
        self.code(self.result(), "master_constraint_drift")

    def test_B4_owner_label_cannot_disagree_with_anchored_attributes(self):
        self.mutate("b4_catalog", lambda value: value["functions"][0].update(owner_name="anon"))
        self.code(self.result(), "b4_identity_inconsistent")

    def test_claimed_B_module_match_does_not_replace_preimage(self):
        self.mutate("b4_module", lambda value: value.update(module_text="{}", module_matches=True))
        self.code(self.result(), "b_module_drift")

    def test_raw_dependency_hash_is_not_parsed_reserialization(self):
        self.mutate("dependency_snapshot", lambda value: value.update(snapshot_text=json.dumps(q.strict_json(value["snapshot_text"]))))
        self.code(self.result(), "dependency_snapshot_drift")

    def test_caller_cannot_select_its_own_dependency_baseline(self):
        self.mutate("dependency_snapshot", lambda value: value.update(snapshot_text="{}", snapshot_sha256=q.digest(b"{}")))
        self.code(self.result(), "dependency_snapshot_drift")

    def test_fake_native_receipt_never_supplies_actual_definitions(self):
        after = self.root / "fake-after.json"
        after.write_text('{"native":true,"functions":[]}')
        receipt = self.root / "fake-receipt.json"
        receipt.write_text('{"native":true,"reviewed":true}')
        for name, path in [("expected_after", after), ("expected_capture_receipt", receipt)]:
            self.manifest["inputs"][name] = {"path": path.name, "sha256": q.digest(path.read_bytes())}
        self.save()
        self.code(self.result(), "unreviewed_expected_capture")
        _, status = p.prepare(self.root, "manifest.json", self.root / "output")
        self.assertEqual(status, 2)
        self.assertFalse((self.root / "output").exists())

    def test_retained_metadata_comparator_preserves_private_authenticated_EXECUTE(self):
        capsule_ref = self.manifest["inputs"]["capsule"]
        contract = q.retained_contract((self.root / capsule_ref["path"]).read_bytes())
        rows = copy.deepcopy(contract["after"])
        context = {"server_version_num": 170006, "namespaces": {}, "roles": {}, "languages": {}}
        for row in rows:
            context["namespaces"][row["schema"]] = row["attributes"]["pronamespace"]
            context["roles"]["postgres"] = row["attributes"]["proowner"]
            context["languages"][row["language"]] = row["attributes"]["prolang"]
        # These are retained real metadata views, not fabricated pg_get_functiondef captures.
        q.compare_expected_metadata(rows, context, contract["after"])
        protected = next(row for row in rows if row["schema"] == "private" and row["name"] == "require_standalone_trade_document_access")
        self.assertIn("authenticated=X/postgres", protected["attributes"]["proacl"])
        protected["attributes"]["proacl"] = ["postgres=X/postgres"]
        with self.assertRaises(q.Rejected) as result:
            q.compare_expected_metadata(rows, context, contract["after"])
        self.assertEqual(result.exception.code, "expected_attribute_drift")
        rows = copy.deepcopy(contract["after"])
        protected = next(row for row in rows if row["attributes"]["prosecdef"] is True)
        protected["attributes"]["prosecdef"] = 1
        with self.assertRaises(q.Rejected):
            q.compare_expected_metadata(rows, context, contract["after"])


@unittest.skipUnless(os.environ.get("SKO_FORMAL_C_QUALIFIED_INPUT_ROOT"), "Independently reviewed actual13 material is private and optional.")
class QualifiedMaterialTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name) / "inputs"
        shutil.copytree(Path(os.environ["SKO_FORMAL_C_QUALIFIED_INPUT_ROOT"]), self.root)

    def tearDown(self):
        self.temporary.cleanup()

    def test_actual13_builds_quarantined_review_only_without_touching_inputs(self):
        before = {str(f.relative_to(self.root)): q.digest(f.read_bytes()) for f in self.root.rglob("*") if f.is_file()}
        report, _ = q.qualify(self.root, "manifest.json")
        self.assertTrue(report["static_qualified"])
        self.assertFalse(report["deployable"])
        output = self.root.parent / "quarantined-output"
        material, status = p.prepare(self.root, "manifest.json", output)
        self.assertEqual(status, 0)
        self.assertFalse(material["deployable"])
        self.assertFalse(material["ready_to_apply"])
        self.assertFalse(material["legacy_restore_operationally_authorized"])
        self.assertFalse(material["sql_executed"])
        prohibition = q.strict_json((output / "OPERATION-PROHIBITED.json").read_bytes())
        self.assertFalse(prohibition["apply_authorized"])
        self.assertTrue(prohibition["saved_modern_row_count_zero_is_insufficient"])
        self.assertEqual(q.digest((output / "review-capsule/atomic-forward.sql.review-only").read_bytes()), material["review_sql_sha256"])
        self.assertEqual(before, {str(f.relative_to(self.root)): q.digest(f.read_bytes()) for f in self.root.rglob("*") if f.is_file()})
        for f in output.rglob("*"):
            self.assertEqual(stat.S_IMODE(f.stat().st_mode), 0o700 if f.is_dir() else 0o600)
        with self.assertRaises(q.Rejected):
            p.prepare(self.root, "manifest.json", output)

    def test_reviewed_receipt_does_not_authorize_changed_capture(self):
        manifest = q.strict_json((self.root / "manifest.json").read_bytes())
        ref = manifest["inputs"]["expected_after"]
        target = self.root / ref["path"]
        target.write_bytes(target.read_bytes() + b"\n")
        ref["sha256"] = q.digest(target.read_bytes())
        write_json(self.root / "manifest.json", manifest)
        report, _ = q.qualify(self.root, "manifest.json")
        self.assertFalse(report["static_qualified"])
        self.assertIn("expected_artifact_drift", {i["code"] for i in report["issues"]})
        output = self.root.parent / "refused-output"
        _, status = p.prepare(self.root, "manifest.json", output)
        self.assertEqual(status, 2)
        self.assertFalse(output.exists())


if __name__ == "__main__":
    unittest.main()
