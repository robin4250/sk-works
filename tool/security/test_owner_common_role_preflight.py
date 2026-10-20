import importlib.util
import json
from pathlib import Path
import sys
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'backup-capture-preparation-20261020'))
spec=importlib.util.spec_from_file_location('helper',Path(__file__).with_name('owner_common_role_preflight.py'))
h=importlib.util.module_from_spec(spec);spec.loader.exec_module(h)
class Tests(unittest.TestCase):
 def payload(self):
  return [{'phase':'before','session_is_cli':True,'current_is_session':True,'member_postgres':True,'can_set_postgres':True,'initial_database_create':False},dict(phase='after',**{k:True for k in ('current_is_postgres','session_still_cli','read_only','database_owner_postgres','database_create','public_schema_create','authenticator_exists','anon_exists','authenticated_exists','new_schemas_absent','unit_functions_owned_by_postgres','unit_sources_match')})]
 def test_noinherit_create_false_valid(self):
  h.validate('\n'.join(json.dumps(x) for x in self.payload()))
 def test_set_denied(self):
  rows=self.payload();rows[0]['can_set_postgres']=False
  with self.assertRaises(Exception):h.validate('\n'.join(json.dumps(x) for x in rows))
 def test_after_guard_false(self):
  rows=self.payload();rows[1]['read_only']=False
  with self.assertRaises(Exception):h.validate('\n'.join(json.dumps(x) for x in rows))
 def test_nonboolean_reject(self):
  rows=self.payload();rows[1]['read_only']='true'
  with self.assertRaises(Exception):h.validate('\n'.join(json.dumps(x) for x in rows))
 def test_sql_readonly(self):
  self.assertTrue(h.SQL.startswith('BEGIN READ ONLY;'));self.assertIn('SET LOCAL ROLE postgres;',h.SQL);self.assertTrue(h.SQL.rstrip().endswith('ROLLBACK;'))
  for forbidden in ('GRANT ','ALTER ','CREATE ','INSERT ','UPDATE ','DELETE '): self.assertNotIn(forbidden,h.SQL)
if __name__=='__main__':unittest.main()
