import hashlib,json,unittest
from pathlib import Path
import owner_master_proof_http_rehearsal as h
import owner_collector_public_create_rehearsal as c
ROOT=Path(__file__).parent
class Contract(unittest.TestCase):
 def test_canonical_collector_proof_reuse(self):
  b=json.loads((ROOT/'collector_proof_bundle.json').read_text());s=c.transaction_sql(b)
  self.assertEqual(s.count(b['scenario']),1)
  installed=s.replace(b['scenario'],'',1).removesuffix('ROLLBACK;')+'COMMIT;'
  self.assertEqual(installed.count('COMMIT;'),1);self.assertNotIn('ALTER DATABASE',installed)
  self.assertNotIn('set_config(\'request.jwt.claim',installed)
 def test_original_auth_infrastructure_pins(self):
  self.assertEqual(h.AUTH_IMAGE,'supabase/gotrue@sha256:1736a63078f5922b198c4cbe50f80ab9a2d3b54fe8b7b6cfb2e9dc5dbbc12c6b')
  self.assertEqual(h.REST_IMAGE,'postgrest/postgrest@sha256:d155c6718ed9a9f990d159a2ab7c0a3f16944dbb6d0a0344557421042acfe0df')
 def test_owner_and_no_password_user_prompt(self):
  s=(ROOT/'owner_master_proof_http_rehearsal.py').read_text()
  self.assertNotIn('query(transport.DATABASE_BASELINE_SQL',s)
  self.assertNotIn('input(',s);self.assertNotIn('getpass',s)
  self.assertIn("'--internal'",s);self.assertNotIn("'--publish'",s)
 def test_original_handler_exact(self):
  self.assertEqual(hashlib.sha256((ROOT/'handler.mjs').read_bytes()).hexdigest(),'43631e87a6706af27a2c1388c92b671e3a4c2253ea5c4dbb8886e9e39949e268')
if __name__=='__main__':unittest.main()
