import copy,hashlib,json,sys,unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).parent))
import owner_expense_contract_diagnostic as d
class Diagnostic(unittest.TestCase):
 def sample(self):return {'functions':[{'signature':'private.a()','oid':1,'definition':'PRIVATE_SOURCE_SECRET','owner':'postgres','volatility':'v','strict':False,'acl':['postgres=X/postgres'],'config':[]}],'triggers':[{'table':'public.a','name':'t','oid':2,'definition':'PRIVATE_TRIGGER_BODY','source_md5':'abc'}],'event_triggers':[]}
 def test_oid_only_not_reported(self):
  a=self.sample();b=copy.deepcopy(a);b['functions'][0]['oid']=10;self.assertEqual(d.compare(a,b),[])
 def test_private_values_never_reported(self):
  a=self.sample();b=copy.deepcopy(a);b['functions'][0]['definition']='ANOTHER_PRIVATE_BODY';b['triggers'][0]['definition']='ANOTHER_PRIVATE_TRIGGER';diff=d.compare(a,b);s=json.dumps(diff)
  self.assertIn('definition',s)
  for secret in ('PRIVATE_SOURCE_SECRET','PRIVATE_TRIGGER_BODY','ANOTHER_PRIVATE_BODY','ANOTHER_PRIVATE_TRIGGER'):self.assertNotIn(secret,s)
 def test_exact_safe_metadata_and_fields(self):
  a=self.sample();b=copy.deepcopy(a);b['functions'][0]['volatility']='s';diff=d.compare(a,b);self.assertEqual(diff,[{'kind':'functions','identity':['private.a()'],'differing_fields':['volatility'],'safe_metadata':{'volatility':{'production':'v','clone':'s'}}}])
 def test_scopes_and_duplicates(self):
  a=self.sample();b=copy.deepcopy(a);b['triggers']=[];self.assertEqual(d.compare(a,b)[0]['scope'],'production_only')
  b=copy.deepcopy(a);b['triggers'].append(dict(b['triggers'][0]))
  with self.assertRaisesRegex(RuntimeError,'duplicate_catalog_identity'):d.compare(a,b)
 def test_exact_pinned_query_and_no_ddl_sql(self):
  p=Path(__file__).parent/'capture_queries.json';self.assertEqual(hashlib.sha256(p.read_bytes()).hexdigest(),d.CAPTURE_SHA256)
  query=json.loads(p.read_text())['catalogSql'];self.assertTrue(query.startswith('select jsonb_build_object('));self.assertNotIn('CREATE ',query);self.assertNotIn('UPDATE ',query)
if __name__=='__main__':unittest.main()
