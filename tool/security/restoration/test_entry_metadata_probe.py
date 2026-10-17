import contextlib
import importlib.util
import io
import json
from pathlib import Path
import sys
import tempfile
import types
import unittest
from unittest.mock import Mock,patch

spec=importlib.util.spec_from_file_location('metadata',Path(__file__).with_name('entry_metadata_probe.py'))
metadata=importlib.util.module_from_spec(spec);spec.loader.exec_module(metadata)

class MetadataTests(unittest.TestCase):
    def test_role_map_rejects_unknown_oid_owner_or_extra_fields(self):
        valid={'definitions':{'read_only':True,'policies':[{'roles':[0,20]}],'functions':[{'owner':'reader'}]},'role_map':[{'oid':20,'name':'reader'}]}
        metadata.validate_map(valid)
        import copy
        for change in ('oid','owner','extra'):
            value=copy.deepcopy(valid)
            if change=='oid':value['definitions']['policies'][0]['roles']=[99]
            if change=='owner':value['definitions']['functions'][0]['owner']='missing'
            if change=='extra':value['role_map'][0]['password']='SYNTHETIC-SECRET'
            with self.assertRaises(ValueError):metadata.validate_map(value)

    def test_inert_without_flag(self):
        with patch.object(sys,'argv',['probe']),patch.object(metadata,'load_sources') as load,contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(metadata.main(),2)
        load.assert_not_called()

    def test_fixed_query_is_bound_to_repository_bytes(self):
        import hashlib
        p=Path(__file__).with_name('entry_definitions.sql.review-only')
        self.assertEqual(hashlib.sha256(p.read_bytes()).hexdigest(),metadata.DEFINITIONS_SHA)

    def test_fixed_role_query_is_bound_to_repository_bytes(self):
        import hashlib
        p=Path(__file__).with_name('entry_role_map.sql.review-only')
        self.assertEqual(hashlib.sha256(p.read_bytes()).hexdigest(),metadata.ROLE_MAP_SHA)

    def test_each_metadata_source_mismatch_prevents_import(self):
        import hashlib
        with tempfile.TemporaryDirectory() as td:
            root=Path(td)
            source=b'raise RuntimeError(\"must never execute\")'
            (root/'entry_snapshot.py').write_bytes(source)
            (root/'entry_definitions.sql.review-only').write_text('SELECT synthetic_definition')
            (root/'entry_role_map.sql.review-only').write_text('SELECT synthetic_role')
            with patch.object(metadata,'SNAPSHOT_SHA',hashlib.sha256(source).hexdigest()),patch.object(metadata.importlib.util,'spec_from_file_location') as imported:
                with self.assertRaises(ValueError):metadata.load_sources(root)
                imported.assert_not_called()
                raw=(root/'entry_definitions.sql.review-only').read_bytes()
                with patch.object(metadata,'DEFINITIONS_SHA',hashlib.sha256(raw).hexdigest()):
                    with self.assertRaises(ValueError):metadata.load_sources(root)
                imported.assert_not_called()

    def test_source_mismatch_before_import_or_credential_access(self):
        with tempfile.TemporaryDirectory() as td:
            base=Path(td);marker=base/'executed'
            (base/'entry_snapshot.py').write_text('from pathlib import Path\nPath('+repr(str(marker))+').touch()')
            (base/'entry_definitions.sql.review-only').write_text('SELECT 1')
            with self.assertRaises(ValueError):metadata.load_sources(base)
            self.assertFalse(marker.exists())

    def run_case(self,payloads):
        td=tempfile.TemporaryDirectory();self.addCleanup(td.cleanup)
        root=Path(td.name)
        module=types.SimpleNamespace(token_from_store=Mock(return_value='SYNTHETIC-SECRET'),
            make_opener=Mock(return_value=object()),read_query=Mock(side_effect=payloads))
        collector=types.SimpleNamespace(new_capsule_directory=lambda parent:root)
        output=io.StringIO()
        with contextlib.redirect_stdout(output):code=metadata.collect(module,collector,'FIXED INVARIANTS','FIXED METADATA',root)
        self.assertNotIn('SYNTHETIC-SECRET',output.getvalue())
        return code,root,module,output.getvalue()

    def test_equal_invariants_and_readonly_required(self):
        inv={'read_only':True,'payload':{'id':'synthetic'}}
        code,root,module,_=self.run_case([inv,{'read_only':True,'payload':{'read_only':True,'definitions':{'read_only':True,'relations':[]},'role_map':[]}},inv])
        self.assertEqual(code,2)
        manifest=json.loads((root/'private-manifest.json').read_text())
        self.assertIs(manifest['restoration_verified'],False)
        self.assertIs(manifest['business_auth_row_export'],False)
        self.assertEqual(module.read_query.call_count,3)

    def test_missing_metadata_proof_stops_before_after_read(self):
        code,root,module,_=self.run_case([{'payload':{}},{'payload':{'read_only':False}}])
        self.assertEqual(code,1);self.assertEqual(module.read_query.call_count,2)
        self.assertFalse((root/'private-manifest.json').exists())

    def test_drift_does_not_create_success_manifest(self):
        code,root,_,_=self.run_case([{'payload':{'id':'old'}},{'payload':{'read_only':True,'definitions':{'read_only':True},'role_map':[]}},{'payload':{'id':'new'}}])
        self.assertEqual(code,1);self.assertFalse((root/'private-manifest.json').exists())

    def test_api_error_never_prints_error_body_or_token(self):
        code,_,module,out=self.run_case([RuntimeError('SYNTHETIC-SECRET')])
        self.assertEqual(code,1);self.assertEqual(module.read_query.call_count,1)
        self.assertIn('RuntimeError',out)

if __name__=='__main__':unittest.main()
