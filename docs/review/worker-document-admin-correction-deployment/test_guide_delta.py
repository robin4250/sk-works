import copy,importlib.util,json,pathlib,unittest
ROOT=pathlib.Path(__file__).resolve().parent
sp=importlib.util.spec_from_file_location('guide_delta',ROOT/'guide_delta.py');m=importlib.util.module_from_spec(sp);sp.loader.exec_module(m)
class DeltaTests(unittest.TestCase):
 def setUp(self):
  self.seal=json.loads((ROOT/'guide-function-seal.json').read_text())
  old={'oid':10,'nspname':'private','proname':'existing','args':'','attributes_sha256':'c'*64,'comment_sha256':m.EMPTY_SHA}
  snapshot={'role':'postgres','server_version_num':170006,'version':2,'relations':[{'name':'same','catalog':{}}],'schemas':[],'functions':[old]}
  self.before={'snapshot':snapshot,'snapshot_sha256':'a'*64};self.after=copy.deepcopy(self.before);self.after['snapshot_sha256']='b'*64;self.receipt=[]
  for i,entry in enumerate(self.seal):
   ns=entry['nspname'];fn={'oid':20+i,'nspname':ns,'proname':m.NAME,'args':'2950','attributes_sha256':str(i+1)*64,'comment_sha256':m.EMPTY_SHA}
   self.after['snapshot']['functions'].append(fn)
   self.receipt.append({**fn,'owner':'postgres','lanname':'plpgsql' if ns=='private' else 'sql','catalog':entry['catalog'],'acl':[{'role':r,'grantor':'postgres','privilege':'EXECUTE','grant_option':False}for r in ['authenticated','postgres']]})
 def check(self):return m.check(self.before,self.after,self.receipt,self.seal,'a'*64)
 def test_exact_two_function_delta(self):
  self.assertEqual(self.check()['status'],'known_two_functions_only');self.assertFalse(self.check()['apply_authorized_by_tool'])
 def test_relation_or_existing_function_drift_rejected(self):
  for key in ['relations','functions']:
   with self.subTest(key=key):
    original=copy.deepcopy(self.after)
    if key=='relations':self.after['snapshot'][key][0]['catalog']['unknown']='drift'
    else:self.after['snapshot'][key][0]['attributes_sha256']='d'*64
    with self.assertRaises(ValueError):self.check()
    self.after=original
 def test_unknown_function_or_overload_rejected(self):
  self.after['snapshot']['functions'].append({'oid':99,'nspname':'private','proname':'unknown','args':''})
  with self.assertRaises(ValueError):self.check()
 def test_body_or_acl_or_owner_change_rejected(self):
  for key,value in [('owner','service_role'),('acl',[]),('catalog',{**self.receipt[0]['catalog'],'body_md5':'0'*32})]:
   with self.subTest(key=key):
    original=copy.deepcopy(self.receipt);self.receipt[0][key]=value
    with self.assertRaises(ValueError):self.check()
    self.receipt=original
 def test_receipt_hash_not_bound_to_after_catalog_rejected(self):
  self.receipt[0]['attributes_sha256']='d'*64
  with self.assertRaises(ValueError):self.check()
 def test_changed_before_or_server_rejected(self):
  self.before['snapshot_sha256']='e'*64
  with self.assertRaises(ValueError):self.check()
if __name__=='__main__':unittest.main()
