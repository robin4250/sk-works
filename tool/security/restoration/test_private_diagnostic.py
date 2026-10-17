import importlib.util
from pathlib import Path
import tempfile
import unittest
import json

spec = importlib.util.spec_from_file_location('diagnostic', Path(__file__).with_name('diagnose_private_collection.py'))
diagnostic = importlib.util.module_from_spec(spec)
spec.loader.exec_module(diagnostic)


class PrivateDiagnosticTests(unittest.TestCase):
    def test_partial_initial_read_and_no_private_text(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / 'private-before.json').write_text('t\n')
            (root / 'private-errors.log').write_text('SYNTHETIC-SECRET permission denied for schema private ACTOR-SENTINEL')
            result = diagnostic.inspect(root)
            self.assertEqual(result['stage_hint'], 'initial_identity_read')
            self.assertEqual(result['error_class'], 'private_schema_permission_denied')
            self.assertNotIn('SYNTHETIC-SECRET', json.dumps(result))
            self.assertNotIn('ACTOR-SENTINEL', json.dumps(result))
            self.assertFalse(result['retry_authorized'])

    def test_completed_first_snapshot_catalog_failure(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / 'private-before.json').write_text('t\n{"private":"SENTINEL"}\n')
            (root / 'private-catalog.json').write_text('t\n')
            (root / 'private-errors.log').write_text('ERROR: column synthetic does not exist')
            result = diagnostic.inspect(root)
            self.assertEqual(result['stage_hint'], 'catalog_read')
            self.assertEqual(result['error_class'], 'missing_column')
            self.assertNotIn('SENTINEL', json.dumps(result))
