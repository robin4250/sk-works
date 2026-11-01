import copy
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import qualify as q

class QualificationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.manifest = {'contract': q.CONTRACT, 'sources': [],
            'captures': {k: None for k in ('relations', 'functions', 'namespaces_default_acl', 'callers_and_edge_sql')},
            'operational_evidence': None}

    def ref(self, name, content):
        (self.root / name).write_bytes(content)
        return {'path': name, 'sha256': hashlib.sha256(content).hexdigest()}

    def source(self, unit, content=b'drift'):
        return {'commit': unit['commit'], 'source_path': unit['path'], 'mode': unit['mode'],
                'artifact': self.ref('source', content)}

    def test_empty_has_exact_fifteen_missing_current_captures_and_no_authority(self):
        r = q.qualify(self.root, self.manifest)
        self.assertEqual(len(set(r['inventory']['existing_relations'])), 15)
        self.assertIn('capture:relations', r['missing'])
        self.assertFalse(r['source_qualified'])
        self.assertFalse(r['capture_qualified'])
        self.assertFalse(r['deployable'])

    def test_superseded_compatibility_rejected(self):
        unit = next(x for x in q.source_units() if 'consumer-boundary' in x['path'])
        self.manifest['sources'] = [self.source(unit)]
        self.manifest['sources'][0]['commit'] = '1bcc8150cc4614f1f91ec2484495d3e3f0d89c7b'
        self.assertIn('unknown_or_superseded_source', q.qualify(self.root, self.manifest)['issues'])

    def test_fixture_helper_cannot_supply_source(self):
        self.manifest['sources'] = [{'commit': 'fixture', 'source_path': 'fixture/parent_binding.sql',
            'mode': 'exact_source', 'artifact': self.ref('source', b'select true')}]
        self.assertIn('unknown_or_superseded_source', q.qualify(self.root, self.manifest)['issues'])

    def test_actor_full_financial_bundle_rejected(self):
        unit = next(x for x in q.source_units() if x['mode'] == 'actor_only')
        row = self.source(unit)
        row['mode'] = 'exact_source'
        self.manifest['sources'] = [row]
        self.assertIn('financial_bundle_or_source_mode', q.qualify(self.root, self.manifest)['issues'])

    def test_duplicate_sources_rejected_before_silently_overwriting(self):
        unit = {'commit': 'test', 'path': 'unit', 'mode': 'exact_source', 'sha256': hashlib.sha256(b'a').hexdigest()}
        row = self.source(unit, b'a')
        self.manifest['sources'] = [row, row]
        with patch.object(q, 'source_units', return_value=[unit]):
            self.assertIn('duplicate_source', q.qualify(self.root, self.manifest)['issues'])

    def test_pinned_bytes_not_claimed_hash(self):
        self.manifest['sources'] = [self.source(q.source_units()[0])]
        self.assertIn('source_pin_drift', q.qualify(self.root, self.manifest)['issues'])

    def test_synthetic_complete_source_only_does_not_promote_deployment(self):
        # Parser contract only; not actual frozen-source or production evidence.
        unit = {'commit': 'test', 'path': 'unit', 'mode': 'exact_source', 'sha256': hashlib.sha256(b'a').hexdigest()}
        self.manifest['sources'] = [self.source(unit, b'a')]
        with patch.object(q, 'source_units', return_value=[unit]):
            r = q.qualify(self.root, self.manifest)
        self.assertTrue(r['source_qualified'])
        self.assertFalse(r['capture_qualified'])
        self.assertFalse(r['deployable'])
        self.assertIn('capture:callers_and_edge_sql', r['missing'])

    def test_native_flag_and_self_hashed_capture_not_trusted(self):
        self.manifest['captures']['relations'] = self.ref('relations', b'{"native":true,"all15":true}')
        self.assertIn('unregistered_actual_capture', q.qualify(self.root, self.manifest)['issues'])

    def test_operational_boolean_not_authority(self):
        self.manifest['operational_evidence'] = True
        self.assertIn('unregistered_operational_evidence', q.qualify(self.root, self.manifest)['issues'])

    def test_relation_scope_cannot_be_removed_or_claimed_by_extra_field(self):
        self.manifest['captures'].pop('relations')
        self.assertIn('unexpected_shape', q.qualify(self.root, self.manifest)['issues'])

    def test_duplicate_json_and_nonfinite_rejected(self):
        for data in ['{"a":1,"a":2}', '{"a":NaN}']:
            with self.assertRaises(q.Rejected):
                q.strict_json(data)

    def test_path_traversal_and_symlink_rejected(self):
        for relative in ['../outside', '/etc/passwd', 'a/../outside', './manifest.json']:
            with self.assertRaises(q.Rejected):
                q.read_path(self.root, relative)
        (self.root / 'link').symlink_to('/etc/passwd')
        with self.assertRaises(q.Rejected):
            q.read_path(self.root, 'link')

    def test_manifest_unknown_fields_refuse(self):
        self.manifest['deployable'] = True
        self.assertIn('unexpected_shape', q.qualify(self.root, self.manifest)['issues'])

    def test_fixed_source_scope_preserves_minimal_actor_and_compat_successor(self):
        units = q.source_units()
        self.assertEqual(len(units), 39)
        self.assertEqual(sum(x['mode'] == 'actor_only' for x in units), 1)
        compat = [x for x in units if 'consumer-boundary' in x['path']]
        self.assertEqual(len(compat), 1)
        self.assertEqual(compat[0]['commit'], '241a393077cc29b00c8e44b3518ab7a7fc050a91')
        self.assertTrue(all('canonical_edge_wasm' in x['path'] for x in units[-8:]))

if __name__ == '__main__':
    unittest.main()
