import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('compare',Path(__file__).with_name('entry_compare.py'))
compare = importlib.util.module_from_spec(spec)
spec.loader.exec_module(compare)


class CompareTests(unittest.TestCase):
    def capsule(self, root):
        root.mkdir(mode=0o700)
        values = {'private-before.json':{'read_only':True,'payload':{'user':'PRIVATE-SYNTHETIC'}},
                  'private-after.json':{'read_only':True,'payload':{'user':'PRIVATE-SYNTHETIC'}},
                  'private-catalog.json':{'read_only':True,'payload':{'objects':[{'type':'table','schema':'public','name':'workers'}]}}}
        for name,value in values.items():
            (root/name).write_text(json.dumps(value));(root/name).chmod(0o600)
        manifest = {'read_only_api':True,'production_writes':0,'schema_archive_created':False,'restoration_verified':False,
                    'files':{name:compare.digest(root/name) for name in values}}
        (root/'private-manifest.json').write_text(json.dumps(manifest));(root/'private-manifest.json').chmod(0o600)
        return manifest

    def test_tamper_traversal_and_permissions_fail_closed(self):
        with tempfile.TemporaryDirectory() as td:
            r=Path(td)/'capsule';m=self.capsule(r)
            self.assertEqual(len(compare.verify_capsule(r)),3)
            (r/'private-before.json').write_text('{}')
            with self.assertRaises(ValueError):compare.verify_capsule(r)
            m['files']['../elsewhere']=m['files'].pop('private-before.json')
            (r/'private-manifest.json').write_text(json.dumps(m))
            with self.assertRaises(ValueError):compare.verify_capsule(r)
            (r/'private-manifest.json').chmod(0o644)
            with self.assertRaises(ValueError):compare.verify_capsule(r)

    def test_strict_evidence_and_identity_mismatch(self):
        for value in (True,False,'true',None):
            with tempfile.TemporaryDirectory() as td:
                r=Path(td)/'capsule';m=self.capsule(r)
                p=r/'private-after.json';p.write_text(json.dumps({'read_only':value,'payload':{'user':'CHANGED'}}))
                m['files'][p.name]=compare.digest(p);(r/'private-manifest.json').write_text(json.dumps(m))
                with self.assertRaises(ValueError):compare.verify_capsule(r)

    def test_offline_subprocess_has_no_connection_or_sql_execution(self):
        with tempfile.TemporaryDirectory() as td:
            r=Path(td);cap=r/'capsule';self.capsule(cap)
            archive=r/'database.dump';archive.write_bytes(b'PGDMPsynthetic');archive.chmod(0o600)
            tool=r/'pg_restore'
            tool.write_text('#!'+sys.executable+'''\nimport sys,os
assert not any(k.upper().startswith('PG') for k in os.environ)
assert 'SUPABASE_ACCESS_TOKEN' not in os.environ
if sys.argv[1:]==['--version']: print('pg_restore (PostgreSQL) 17.11')
else:
 assert len(sys.argv)==3 and sys.argv[1]=='--list'
 print('1; 1259 1 TABLE public workers postgres')
 print('2; 0 1 TABLE DATA public workers postgres')
''');tool.chmod(0o700)
            original=archive.read_bytes();out=io.StringIO()
            with patch.object(sys,'argv',['compare','--capsule',str(cap),'--archive',str(archive),'--pg-bin',str(r),'--output-parent',str(r)]),patch.dict(os.environ,{'PGHOST':'forbidden','SUPABASE_ACCESS_TOKEN':'PRIVATE-TOKEN'}),contextlib.redirect_stdout(out):
                self.assertEqual(compare.main(),2)
            self.assertNotIn('PRIVATE-SYNTHETIC',out.getvalue())
            self.assertNotIn('PRIVATE-TOKEN',out.getvalue())
            self.assertIn('"time_gap_closed": false',out.getvalue())
            self.assertEqual(archive.read_bytes(),original)
            evidence=Path(out.getvalue().split('Private evidence: ')[1].strip())
            self.assertEqual(evidence.parent,r)
            self.assertEqual(evidence.stat().st_mode & 0o777,0o700)

    def test_table_data_does_not_count_as_definition(self):
        values={'private-catalog.json':{'payload':{'objects':[]}}}
        report=compare.inspect_toc('1; 0 1 TABLE DATA public workers postgres',values)
        self.assertEqual(report['archive_table_count'],0)
        self.assertFalse(report['subset_restore_verified'])


if __name__ == '__main__':unittest.main()
