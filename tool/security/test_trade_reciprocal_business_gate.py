import importlib.util,json,tempfile,unittest,shutil
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('generator',ROOT/'tool/prepare_trade_reciprocal_business_gate.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
class GateSourceTests(unittest.TestCase):
 def sandbox(self):
  t=tempfile.TemporaryDirectory();self.addCleanup(t.cleanup);r=Path(t.name)
  for rel in m.FILES+['tool/fixtures/trade_reciprocal_gate/source_manifest.json']:
   (r/rel).parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(ROOT/rel,r/rel)
  m.ROOT=r;self.addCleanup(setattr,m,'ROOT',ROOT);return r
 def test_deterministic_six_routine_only(self):
  r=self.sandbox();m.main();p=r/'docs/candidates/trade_reciprocal_business_gate_20261024.sql.review-only';a=p.read_bytes();m.main();self.assertEqual(a,p.read_bytes())
  manifest=json.loads((r/'docs/candidates/trade_reciprocal_business_gate_20261024.manifest.json').read_text());self.assertEqual(len(manifest['routines']),6)
  for x in manifest['routines']:self.assertNotEqual(x['before_md5'],x['after_md5'])
 def test_unknown_source_refused_before_output(self):
  r=self.sandbox();p=r/m.FILES[0];p.write_bytes(p.read_bytes()+b'\n-- unknown source\n')
  with self.assertRaises(AssertionError):m.main()
  self.assertFalse((r/'docs/candidates/trade_reciprocal_business_gate_20261024.sql.review-only').exists())
 def test_reads_and_issuer_page_rules_unchanged(self):
  r=self.sandbox();m.main();s=(r/'docs/candidates/trade_reciprocal_business_gate_20261024.sql.review-only').read_text()
  self.assertNotIn('create or replace function trade_document_consent_private.render_approved(',s)
  self.assertNotIn('create or replace function trade_document_consent_private.bind_local(',s)
  self.assertNotIn('create or replace function trade_document_confirmation_api_private.received_workspace(',s)
  self.assertIn("require_gated_write_pair(cid,d.counterparty_company_id,action<>'cancel')",s)
  self.assertIn("'unavailable_reason','reciprocal_feature_disabled'",s)
if __name__=='__main__':unittest.main()
