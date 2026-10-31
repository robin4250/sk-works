"""Verify the real fixed source/static closure, without credentials or deployment."""
import importlib.util
import os
from pathlib import Path
import shutil
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('stage_edge', HERE / 'stage_edge.py')
stager = importlib.util.module_from_spec(spec)
spec.loader.exec_module(stager)


class FixedStageTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = HERE.parents[1]
        cls.renderer = Path(os.environ['SKO_RENDERER_ROOT']).resolve()

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.addCleanup(self.temp.cleanup)

    def test_actual_closure_and_no_overwrite(self):
        output = self.root / 'fixed'
        receipt = stager.stage(self.source, self.renderer, output)
        self.assertEqual(len(receipt['files']), 14)
        self.assertFalse(receipt['deployed'])
        self.assertFalse(receipt['complete_cli_bundle_measured'])
        self.assertEqual({str(p.relative_to(output)) for p in output.rglob('*') if p.is_file()},
                         set(receipt['files']) | {'private-current-edge-manifest.json'})
        for name, pin in receipt['files'].items():
            file = output / name
            self.assertEqual(stager.sha(file.read_bytes()), pin['sha256'])
            self.assertEqual(file.stat().st_mode & 0o777, 0o600)
        with self.assertRaises(ValueError):
            stager.stage(self.source, self.renderer, output)

    def test_source_drift_refused_before_output(self):
        source = self.root / 'source'
        for name in stager.EXPECTED_SOURCES:
            target = source / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(self.source / name, target)
        target.write_bytes(target.read_bytes() + b'\n// drift\n')
        output = self.root / 'rejected'
        with self.assertRaises(ValueError):
            stager.stage(source, self.renderer, output)
        self.assertFalse(output.exists())

    def test_symlink_source_and_output_parent_refused(self):
        link = self.root / 'link'
        link.symlink_to(self.source / 'tool', target_is_directory=True)
        with self.assertRaises(ValueError):
            stager.regular(self.root, 'link/site_order_canonical_core.mjs')
        link.unlink()
        target = self.root / 'target'
        target.mkdir()
        link.symlink_to(target, target_is_directory=True)
        with self.assertRaises(ValueError):
            stager.stage(self.source, self.renderer, link / 'forbidden')
        self.assertFalse((target / 'forbidden').exists())

    def test_compiled_drift_refused_before_output(self):
        renderer = self.root / 'renderer'
        shutil.copytree(self.renderer, renderer)
        target = renderer / 'build/main.wasm'
        target.write_bytes(b'not the fixed wasm')
        output = self.root / 'rejected'
        with self.assertRaises(ValueError):
            stager.stage(self.source, renderer, output)
        self.assertFalse(output.exists())


if __name__ == '__main__':
    unittest.main()
