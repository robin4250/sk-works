import copy
import importlib.util
import tempfile
import unittest
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
spec = importlib.util.spec_from_file_location('png_deploy', HERE / 'prepare_company_png_deployment_review.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
ROOT = HERE.parents[1]


def before():
    attrs={'proconfig':['search_path=""'],'prosecdef':True}
    routines={s:{'source_md5':'fixture-helper','definition':'fixture helper', 'owner':'postgres','attributes':dict(attrs)} for s in module.DEPENDENCIES}
    routines[module.ORIGINAL]={'source_md5':module.ORIGINAL_MD5,'owner':'postgres','attributes':dict(attrs),
        'definition':"fixture baseline\ndeclare c public.companies;\nbegin\n if not p_new then return p_existing;end if;\n select * into c from public.companies where id=p_company for share;\nend"}
    return {'schema':1,'relations':{t:{'rls':True} for t in module.PROTECTED_TABLES},
        'data':{t:{'count':1,'sha256':'fixture'} for t in module.PROTECTED_TABLES},
        'routines':routines,'namespaces':{'private':{},'public':{}}}


def after(b):
    a=copy.deepcopy(b)
    for t in module.NEW_TABLES:
        a['relations'][t]={'rls':True}
        a['data'][t]={'count':0,'sha256':'empty'}
    _,sources=module.sources(ROOT)
    for s in module.NEW_ROUTINES:
        a['routines'][s]={'source_md5':sources[s.split('(')[0]],'owner':'postgres','attributes':{},'definition':'fixture'}
    a['routines'][module.ORIGINAL]['definition']=module.patched_snapshot(b)
    return a


class CheckpointBoundaryTest(unittest.TestCase):
    def test_dependency_catalog_alone_is_insufficient(self):
        with self.assertRaisesRegex(ValueError,'checkpoint required'):
            module.prepare_install({'schema':1,'relations':{},'data':{}},ROOT)

    def test_restore_refuses_registered_png_or_changed_financial_original(self):
        b=before();a=after(b);a['data'][module.NEW_TABLES[0]]['count']=1
        with self.assertRaisesRegex(ValueError,'no longer unused'):
            module.prepare_restore(b,a,ROOT)
        a=after(b);a['data']['public.invoices']['sha256']='changed'
        with self.assertRaisesRegex(ValueError,'protected original changed'):
            module.prepare_restore(b,a,ROOT)

    def test_restore_refuses_changed_snapshot_source_and_owner(self):
        b=before();a=after(b);a['routines'][module.ORIGINAL]['definition']+=' changed'
        with self.assertRaisesRegex(ValueError,'source differs'):
            module.prepare_restore(b,a,ROOT)
        a=after(b);a['routines'][next(iter(module.NEW_ROUTINES))]['owner']='unexpected'
        with self.assertRaisesRegex(ValueError,'installed source differs'):
            module.prepare_restore(b,a,ROOT)

    def test_generates_single_transaction_without_cascade(self):
        b=before();a=after(b)
        for sql in (module.prepare_install(b,ROOT),module.prepare_restore(b,a,ROOT)):
            self.assertTrue(sql.endswith('commit;\n'))
            self.assertEqual(sql.count('\nbegin;'),1)
            self.assertNotIn('CASCADE',sql.upper())
            self.assertIn('access exclusive mode',sql)
            self.assertIn('PNG catalog/data checkpoint changed',sql)


if __name__=='__main__':unittest.main()
