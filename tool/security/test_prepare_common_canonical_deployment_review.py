"""Offline guard tests. Synthetic observations only; no database execution."""
import copy
import importlib.util
from pathlib import Path
import unittest

SPEC=importlib.util.spec_from_file_location('prepare',Path(__file__).with_name('prepare_common_canonical_deployment_review.py'))
m=importlib.util.module_from_spec(SPEC);SPEC.loader.exec_module(m)
ADDED=[
 'company_common_canonical_review_private.snapshot_plan(uuid,text,bigint,jsonb,jsonb,text)',
 'company_common_canonical_review_private.publication_preview(uuid,text,date,bigint,jsonb,bigint,jsonb,text,uuid)',
 'company_common_canonical_review_private.resolve_legacy(uuid,uuid,date,date,jsonb,bigint,date)',
 'company_common_canonical_review_private.preview(uuid,text,date,bigint,jsonb,bigint,jsonb,text)',
 'company_common_allowance_private.preview_payroll_v2(uuid,text,date,bigint,jsonb,bigint,jsonb,text)',
 'company_common_allowance_private.publish_payroll_v2(uuid,text,date,bigint,jsonb,bigint,jsonb,text,uuid,text,boolean,text)',
 'company_common_allowance_private.read_publish_receipt_v2(uuid,uuid,jsonb)',
 'public.preview_company_common_payroll_v2(uuid,text,date,bigint,jsonb,bigint,jsonb,text)',
 'public.publish_company_common_payroll_v2(uuid,text,date,bigint,jsonb,bigint,jsonb,text,uuid,text,boolean,text)',
 'public.read_company_common_payroll_publish_receipt_v2(uuid,uuid,jsonb)',
 'public.company_common_payroll_publication_v2_contract_version()']

def pair():
    before={'schema':1,'routines':{},'data':{'company_common_allowance_private.payroll_publications':{'count':0,'sha256':'synthetic'},'company_common_allowance_private.payroll_publication_receipts':{'count':0,'sha256':'synthetic'}},'namespaces':{},'relations':{},'counts':{},'impact':{}}
    for sig,body in m.ORIGINAL.items():
        before['routines'][sig]={'source_md5':body,'owner':'postgres','definition':'CREATE OR REPLACE FUNCTION '+sig+' RETURNS jsonb LANGUAGE sql AS $$SELECT null::jsonb$$','attributes':{'proacl':['synthetic owner ACL']}}
    after=copy.deepcopy(before);sources=m.reviewed_sources()
    for sig in list(m.ORIGINAL)+ADDED:
        after['routines'].setdefault(sig,{'owner':'postgres','definition':'synthetic','attributes':{}})
        after['routines'][sig]['source_md5']=sources[sig.split('(')[0]]
    for table in m.NEW_TABLES:
        after['data'][table]={'count':0,'sha256':'empty'}
        after['relations'][table]={'owner':'postgres'}
    after['namespaces']['company_common_canonical_review_private']={'owner':'postgres','acl':['postgres=UC/postgres']}
    return before,after

class GuardTests(unittest.TestCase):
    def test_unused_review_generation(self):
        before,after=pair();sql=m.prepare_restore(before,after)
        self.assertIn('in access exclusive mode;',sql)
        self.assertLess(sql.index('lock table'),sql.index('do $sko_observe$'))
        self.assertIn('post-install catalog/data changed; restore refused',sql)
        self.assertNotIn('cascade',sql.lower())
        self.assertNotIn('update public.payroll',sql.lower())
        self.assertIn("set local search_path='';",sql)
    def test_changed_pinned_source_refuses(self):
        a,b=pair();b['routines'][ADDED[0]]['source_md5']='0'*32
        with self.assertRaisesRegex(ValueError,'pinned unit'):m.prepare_restore(a,b)
    def test_changed_original_acl_refuses(self):
        a,b=pair();b['routines'][next(iter(m.ORIGINAL))]['attributes']['proacl']=['authenticated grant']
        with self.assertRaisesRegex(ValueError,'attributes'):m.prepare_restore(a,b)
    def test_used_activation_refuses(self):
        a,b=pair();b['data'][m.NEW_TABLES[0]]['count']=1
        with self.assertRaisesRegex(ValueError,'already used'):m.prepare_restore(a,b)
    def test_changed_publication_or_receipt_refuses(self):
        for table in ['payroll_publications','payroll_publication_receipts']:
            a,b=pair();b['data']['company_common_allowance_private.'+table]['sha256']='changed'
            with self.assertRaisesRegex(ValueError,'existing application data'):m.prepare_restore(a,b)
    def test_extra_routine_refuses(self):
        a,b=pair();b['routines']['public.unexpected()']={'source_md5':'x'}
        with self.assertRaisesRegex(ValueError,'pinned unit'):m.prepare_restore(a,b)

if __name__=='__main__':unittest.main()
