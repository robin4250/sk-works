import copy
import unittest
import common_payroll_unused_undo as undo

class UnusedUndoTests(unittest.TestCase):
    def snapshots(self):
        originals=[]
        for i,name in enumerate(undo.REPLACED,1):
            originals.append({'oid':i,'name':name.split('(')[0],'signature':name,'definition':'CREATE OR REPLACE FUNCTION '+name+' RETURNS jsonb LANGUAGE sql AS $$SELECT null::jsonb$$','owner':'original_owner','owner_oid':5,'acl':None,'config':['search_path='],'definer':True})
        before={'schema':1,'source_hashes':dict(undo.common.EXPECTED),'catalog':{'hash':'a'*32,'catalog':{}},'functions':originals,'business_hash':'b'*32}
        after=copy.deepcopy(before);after['catalog']['hash']='c'*32
        for i,f in enumerate(after['functions']):f['definition']+=' -- reviewed replacement'
        for i,name in enumerate(sorted(undo.NEW_FUNCTION_NAMES),100):
            after['functions'].append({'oid':i,'name':name,'signature':name+'()','definition':'new','owner':'original_owner','owner_oid':5,'acl':None,'config':None,'definer':False})
        return before,after

    def test_exact_sources_and_eleven_empty_tables_only(self):
        before,after=self.snapshots();sql=undo.build_unused_undo(before,after)
        self.assertTrue(sql.startswith('-- REVIEW ONLY:'))
        self.assertTrue(sql.endswith('COMMIT;'))
        self.assertNotIn('CASCADE',sql)
        self.assertEqual(sql.count('common payroll was used: undo refused'),11)
        self.assertEqual(sql.count('DROP TABLE '),2) # temp fingerprint plus exact new tables
        self.assertLess(sql.index(before['functions'][0]['definition']),sql.index('DROP TRIGGER'))
        self.assertLess(sql.index('DROP TRIGGER'),sql.index('DROP FUNCTION'))
        self.assertIn('IN ACCESS EXCLUSIVE MODE;',sql)
        self.assertIn('original catalog mismatch: undo rolled back',sql)

    def test_changed_owner_acl_config_or_existing_oid_refused(self):
        for key,value in [('owner','someone_else'),('owner_oid',999),('acl',['someone=X/someone']),('config',None),('oid',999)]:
            before,after=self.snapshots();after['functions'][0][key]=value
            with self.assertRaises(RuntimeError):undo.build_unused_undo(before,after)

    def test_unknown_or_missing_new_functions_refused(self):
        before,after=self.snapshots();after['functions'].pop()
        with self.assertRaisesRegex(RuntimeError,'exact_new_function_set'):undo.build_unused_undo(before,after)
        before,after=self.snapshots();after['functions'][-1]['name']='public.unknown'
        with self.assertRaisesRegex(RuntimeError,'exact_new_function_set'):undo.build_unused_undo(before,after)

    def test_source_or_business_drift_refused(self):
        before,after=self.snapshots();after['business_hash']='d'*32
        with self.assertRaisesRegex(RuntimeError,'changed_business'):undo.build_unused_undo(before,after)
        before,after=self.snapshots();after['source_hashes']={}
        with self.assertRaisesRegex(RuntimeError,'source_mismatch'):undo.build_unused_undo(before,after)

    def test_rejection_probe_only_executes_guard_never_destructive_steps(self):
        before,after=self.snapshots();sql=undo.rejection_assertion(undo.build_unused_undo(before,after),'common payroll was used: undo refused')
        self.assertNotIn('DROP ',sql)
        self.assertNotIn('CREATE OR REPLACE',sql)
        self.assertIn('unused undo did not reject protected case',sql)

if __name__=='__main__':unittest.main()
