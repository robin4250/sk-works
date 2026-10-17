import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('compare', Path(__file__).with_name('recovery_compare.py'))
c = importlib.util.module_from_spec(spec)
spec.loader.exec_module(c)


class CompareTests(unittest.TestCase):
    def test_synthetic_identity_roles_and_flags_are_compared_without_authorization(self):
        with tempfile.TemporaryDirectory() as folder:
            before, after = Path(folder) / 'before.json', Path(folder) / 'after.json'
            data = {'schema': 'sko-critical-state-v1', 'sections': {
                k: {'status': 'observed', 'value': 'b' * 64,
                    'evidence_sha256': 'a' * 64} for k in c.FIELDS}}
            identity = {'user_id': 'synthetic-admin', 'company_id': 'synthetic-company', 'role': 'owner'}
            data['sections']['admin_identity']['value'] = identity
            data['sections']['company_memberships']['value'] = [dict(identity)]
            data['sections']['master_role_assignments']['value'] = [{'user_id': 'synthetic-admin', 'enabled': True}]
            data['sections']['feature_flags']['value'] = {'synthetic-feature': False}
            for path in (before, after):
                path.write_text(json.dumps(data)); path.chmod(0o600)
            result = c.compare(before, after)
            self.assertTrue(result['all_critical_values_equal'])
            self.assertFalse(result['production_change_authorized'])
            data['sections']['company_memberships']['value'][0]['user_id'] = 'different-fixture'
            after.write_text(json.dumps(data))
            self.assertEqual(c.compare(before, after)['changed_sections'], ['company_memberships'])

    def test_unknown_missing_and_public_files_block(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'state.json'
            data = {'schema': 'sko-critical-state-v1', 'sections': {
                k: {'status': 'unknown', 'value': None, 'evidence_sha256': 'a' * 64} for k in c.FIELDS}}
            path.write_text(json.dumps(data)); path.chmod(0o600)
            with self.assertRaises(ValueError): c.checked(path)
            del data['sections']['admin_identity']
            path.write_text(json.dumps(data))
            with self.assertRaises(ValueError): c.checked(path)
            path.chmod(0o644)
            with self.assertRaises(ValueError): c.checked(path)


if __name__ == '__main__':
    unittest.main()
