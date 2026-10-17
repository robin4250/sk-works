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
    def test_inert_without_flag(self):
        with patch.object(sys,'argv',['probe']),patch.object(metadata,'load_sources') as load,contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(metadata.main(),2)
        load.assert_not_called()

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
        code,root,module,_=self.run_case([inv,{'read_only':True,'payload':{'read_only':True,'relations':[]}},inv])
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
        code,root,_,_=self.run_case([{'payload':{'id':'old'}},{'payload':{'read_only':True}},{'payload':{'id':'new'}}])
        self.assertEqual(code,1);self.assertFalse((root/'private-manifest.json').exists())

    def test_api_error_never_prints_error_body_or_token(self):
        code,_,module,out=self.run_case([RuntimeError('SYNTHETIC-SECRET')])
        self.assertEqual(code,1);self.assertEqual(module.read_query.call_count,1)
        self.assertIn('RuntimeError',out)

if __name__=='__main__':unittest.main()
