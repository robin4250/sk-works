import copy
import importlib.util
import json
import pathlib
import unittest

HERE = pathlib.Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('catalog_guard', HERE / 'compare_catalog.py')
guard = importlib.util.module_from_spec(spec)
spec.loader.exec_module(guard)


class CatalogGuard(unittest.TestCase):
    def setUp(self):
        self.manifest = json.loads((HERE / 'manifest.json').read_text())
        self.before = {'server_version_num': '170000', 'default_acls': [], 'new_namespace_presence': None,
                       'functions': [{'signature': f['signature'], 'body_md5': f['source_md5'],
                                      'owner': f['owner'], 'acl': f['acl'], 'attrs': {'prosecdef': f['security_definer'], 'provolatile': f['volatility'],
                                                'proconfig': f['config']}}
                                     for f in self.manifest['existing_function_contracts']],
                       'relations': [{'name': name, 'columns': [{'type': 'uuid'}],
                                      'attrs': {'relrowsecurity': True}, 'triggers': [], 'policies': []}
                                     for name in self.manifest['existing_relation_names']]}

    def test_equal_prerequisites_still_not_install_ready(self):
        result = guard.compare(self.before, copy.deepcopy(self.before), self.manifest)
        self.assertTrue(result['existing_prerequisites_unchanged'])
        self.assertFalse(result['installation_ready'])
        self.assertTrue(result['new_object_catalog_not_covered'])

    def test_body_change_denied(self):
        after = copy.deepcopy(self.before)
        after['functions'][0]['body_md5'] = '0' * 32
        with self.assertRaisesRegex(ValueError, 'helper contract changed'):
            guard.compare(self.before, after, self.manifest)

    def test_full_existing_acl_rls_trigger_policy_default_drift(self):
        changes = [('functions', 'acl', [{'grantee': 'PUBLIC'}]),
                   ('relations', 'attrs', {'relrowsecurity': False}),
                   ('relations', 'triggers', ['changed']), ('relations', 'policies', ['changed'])]
        for section, field, value in changes:
            with self.subTest(field=field):
                after = copy.deepcopy(self.before)
                after[section][0][field] = value
                with self.assertRaises(ValueError):
                    guard.compare(self.before, after, self.manifest)
        after = copy.deepcopy(self.before)
        after['default_acls'] = [{'changed': True}]
        with self.assertRaisesRegex(ValueError, 'catalog drift'):
            guard.compare(self.before, after, self.manifest)

    def test_missing_helper_or_relation_denied(self):
        for section in ['functions', 'relations']:
            after = copy.deepcopy(self.before)
            after[section].pop()
            with self.assertRaises(ValueError):
                guard.compare(self.before, after, self.manifest)


if __name__ == '__main__':
    unittest.main()
