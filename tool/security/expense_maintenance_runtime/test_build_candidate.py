import unittest
from pathlib import Path
from build_candidate import build
class Candidate(unittest.TestCase):
 def test_pinned_and_unknown(self):
  source=(Path(__file__).parent/'source/conversion.sql').read_bytes()
  out=build(source)
  self.assertEqual(out,(Path(__file__).parent/'maintenance.sql.review-only').read_text())
  with self.assertRaisesRegex(ValueError,'unknown_converter_source'):build(source+b'\n')
 def test_identity_boundary(self):
  out=(Path(__file__).parent/'maintenance.sql.review-only').read_text()
  self.assertNotIn('set_config',out)
  self.assertNotIn('actor_id',out)
  self.assertNotIn('create function private.convert_payment_expense_v1_draft',out.lower())
  self.assertIn('SECURITY INVOKER'.lower(),out.lower())
  self.assertIn("execution_kind='maintenance'",out)
  self.assertIn('authorization_reference',out)
if __name__=='__main__':unittest.main()
