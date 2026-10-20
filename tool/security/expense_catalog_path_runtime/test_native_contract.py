import copy,json,sys,unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).parent))
import owner_prepared_expense_path_rehearsal as n
class NativeContract(unittest.TestCase):
 def sample(self):
  return {'functions':[{'signature':'private.a()','oid':1,'definition':'source','owner':'postgres','acl':['postgres=X/postgres'],'config':[]}], 'triggers':[{'table':'public.p','name':'t','oid':2,'definition':'triggerdef','function':'private.a()'}],'event_triggers':[{'name':'e','oid':3,'definition':'eventdef'}]}
 def test_only_explicit_oid_change(self):
  a=self.sample();b=copy.deepcopy(a)
  for rows in b.values():
   for row in rows:row['oid']+=100
  m=n.map_catalog(a,b);self.assertEqual(m['functions'][0]['production_oid'],1);self.assertEqual(m['functions'][0]['clone_oid'],101)
  self.assertEqual(a['functions'][0]['oid'],1)
 def test_non_oid_and_scope_drift_refused(self):
  a=self.sample()
  for field,value in [('definition','drift'),('owner','other'),('acl',['anon=X/postgres']),('config',['search_path=public'])]:
   b=copy.deepcopy(a);b['functions'][0][field]=value
   with self.assertRaisesRegex(RuntimeError,'catalog_non_oid_drift'):n.map_catalog(a,b)
  b=copy.deepcopy(a);b['triggers'][0]['function']='private.other()'
  with self.assertRaisesRegex(RuntimeError,'catalog_non_oid_drift'):n.map_catalog(a,b)
  b=copy.deepcopy(a);b['event_triggers'].append(dict(b['event_triggers'][0],name='unknown',oid=4))
  with self.assertRaisesRegex(RuntimeError,'catalog_identity_scope_differs'):n.map_catalog(a,b)
 def test_duplicate_identity_or_oid_refused(self):
  a=self.sample();b=copy.deepcopy(a);b['functions'].append(dict(b['functions'][0]))
  with self.assertRaisesRegex(RuntimeError,'catalog_identity_not_unique'):n.map_catalog(a,b)
  b=copy.deepcopy(a);b['functions'].append(dict(b['functions'][0],signature='private.b()'))
  with self.assertRaisesRegex(RuntimeError,'catalog_identity_not_unique'):n.map_catalog(a,b)
 def test_fixture_grant_revoked_inside_original_commit(self):
  original='--review\nBEGIN;\nSET LOCAL ROLE postgres;\nDO $$BEGIN NULL;END$$;\nCOMMIT;'
  fixture=n.fixture_install(original)
  self.assertEqual(fixture.count('BEGIN;\n'),1);self.assertEqual(fixture.count('COMMIT;'),1)
  self.assertLess(fixture.index('GRANT CREATE'),fixture.index('SET LOCAL ROLE postgres'))
  self.assertLess(fixture.index('RESET ROLE;'),fixture.index('REVOKE CREATE'))
  self.assertLess(fixture.index('REVOKE CREATE'),fixture.index('COMMIT;'))
  self.assertNotIn('ALTER DATABASE',fixture);self.assertEqual(original.count('GRANT'),0)
 def test_runtime_hashes_and_source_reuse(self):
  import hashlib
  root=Path(__file__).parent;m=json.loads((root/'runtime_manifest.json').read_text())
  for name,h in m['files'].items():self.assertEqual(hashlib.sha256((root/name).read_bytes()).hexdigest(),h,name)
  previous=root.parent/'expense-prepare-driver-20261020'
  for name in ['expense_default_off_plan.mjs',*['source/'+p.name for p in (root/'source').iterdir()]]:self.assertEqual((root/name).read_bytes(),(previous/name).read_bytes(),name)
class DisplayContract(unittest.TestCase):
 def records(self):
  actual={'event_triggers':[]};physical=[]
  for i,(signature,md5) in enumerate(n.EVENT_REFERENCE_MD5.items()):
   name='synthetic_event_'+str(i);proname=signature.removeprefix('extensions.').removesuffix('()')
   actual['event_triggers'].append({'name':name,'function':signature,'source_md5':md5})
   physical.append({'event_name':name,'namespace':'extensions','signature':signature,'proname':proname,'no_arguments':True,'source_md5':md5})
  return actual,physical
 def test_exact_physical_reference(self):
  actual,physical=self.records();self.assertEqual(len(n.verify_event_references(actual,physical)),6)
 def test_shadow_same_source_and_unknown_drift_refused(self):
  actual,physical=self.records()
  for field,value in [('namespace','shadow'),('signature','shadow.set_graphql_placeholder()'),('no_arguments',False),('source_md5','0'*32)]:
   bad=copy.deepcopy(physical);bad[0][field]=value
   with self.assertRaisesRegex(RuntimeError,'physical_event_reference_differs'):n.verify_event_references(actual,bad)
  bad=copy.deepcopy(actual);bad['event_triggers'][0]['source_md5']='0'*32
  with self.assertRaisesRegex(RuntimeError,'production_event_source_changed'):n.verify_event_references(bad,physical)
 def test_helper_only_changes_display_path_and_adds_reference_check(self):
  source=(Path(__file__).parent/'owner_prepared_expense_path_rehearsal.py').read_text()
  self.assertIn('SET search_path=public;SET statement_timeout=',source)
  self.assertNotIn("removeprefix('extensions.')==",source)
  a=NativeContract().sample();b=copy.deepcopy(a);b['event_triggers'][0]['definition']='changed'
  with self.assertRaisesRegex(RuntimeError,'catalog_non_oid_drift'):n.map_catalog(a,b)
if __name__=='__main__':unittest.main()
