import copy
import tempfile
import unittest
from pathlib import Path
import prepare_resident_annual_deployment_review as m


ROOT=Path(__file__).resolve().parents[2]


def checkpoint():
    return {'schema':1,
      'data':{t:{'count':0,'sha256':'synthetic-empty'} for t in m.PROTECTED_TABLES},
      'relations':{t:{'owner':'postgres','rls':True} for t in m.PROTECTED_TABLES},
      'routines':{s:{'source_md5':m.PINNED.get(s,'synthetic-unpinned'),
        'definition':'synthetic baseline only','owner':'postgres',
        'attributes':{'prosecdef':True,'proconfig':['search_path=""']}}
        for s in m.DEPENDENCIES},
      'namespaces':{s:{'owner':'postgres'} for s in m.EXISTING_NAMESPACES}}


class Preparation(unittest.TestCase):
    def test_exact_unit_and_bounded_guard(self):
        body,expected=m.sources(ROOT)
        self.assertEqual(len(expected),14)
        sql=m.prepare_install(checkpoint(),ROOT)
        self.assertIn(body,sql)
        self.assertIn('in access exclusive mode',sql)
        self.assertIn('annual installation changed originals',sql)
        self.assertIn("set_config('search_path','',true)",sql)
        self.assertTrue(sql.endswith('commit;\n'))

    def test_changed_source_refused(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d);p=root/m.UNIT;p.parent.mkdir(parents=True)
            p.write_bytes((ROOT/m.UNIT).read_bytes()+b'\n')
            with self.assertRaisesRegex(ValueError,'reviewed annual unit changed'):
                m.prepare_install(checkpoint(),root)

    def test_incomplete_or_drifted_baseline_refused(self):
        before=checkpoint();before['data'].pop(m.PROTECTED_TABLES[0])
        with self.assertRaisesRegex(ValueError,'complete annual'):
            m.prepare_install(before,ROOT)
        before=checkpoint();before['routines'][next(iter(m.PINNED))]['source_md5']='changed'
        with self.assertRaisesRegex(ValueError,'pinned prerequisite'):
            m.prepare_install(before,ROOT)

    def test_private_artifact_does_not_overwrite(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'private.sql';m.write_private(p,'first')
            self.assertEqual(p.stat().st_mode & 0o777,0o600)
            with self.assertRaises(FileExistsError):m.write_private(p,'second')
            self.assertEqual(p.read_text(),'first')

    def test_used_removal_refused(self):
        before=checkpoint();after=copy.deepcopy(before)
        for t in m.NEW_TABLES:
            after['data'][t]={'count':0,'sha256':'synthetic-empty'}
            after['relations'][t]={'owner':'postgres','rls':True}
        _,expected=m.sources(ROOT)
        for s in m.NEW_ROUTINES:
            e=expected[s.split('(')[0]]
            after['routines'][s]={'source_md5':e['source_md5'],'owner':'postgres',
              'attributes':{'proconfig':['search_path=""'],'prosecdef':e['security_definer'],'provolatile':e['volatility']}}
        after['namespaces'][m.NEW_SCHEMA]={'owner':'postgres'}
        sql=m.prepare_restore(before,after,ROOT)
        self.assertIn('drop schema resident_tax_annual_private;',sql)
        self.assertNotIn(' cascade;',sql.lower())
        after['data'][m.NEW_TABLES[0]]['count']=1
        with self.assertRaisesRegex(ValueError,'already used'):
            m.prepare_restore(before,after,ROOT)


if __name__=='__main__':unittest.main()
