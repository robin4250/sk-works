import unittest,tempfile,shutil
from pathlib import Path
from unittest.mock import patch
import p34_atomic as p
class Composition(unittest.TestCase):
 def test_reviewed_input(self):
  root=Path(__file__).resolve().parents[2]
  s=p.compose(root)
  self.assertEqual(p.hashlib.sha256(s.encode()).hexdigest(),"500e3aa4620a85ad193bd912f475044d8bf9ed84a8605a7932ce2389a5039fd7")
  self.assertTrue(s.startswith("begin;\n"))
  self.assertTrue(s.endswith("commit;\n"))
  self.assertEqual(s.count("\ncommit;"),1)
  self.assertIn("Output metadata drift",s)
  for n in p.SOURCES:
   raw=(root/"supabase/migrations"/n).read_text()
   self.assertIn(raw[len("begin;\n"):-len("commit;\n")],s)
 def test_drift(self):
  with tempfile.TemporaryDirectory() as d:
   dest=Path(d)/"supabase/migrations";dest.mkdir(parents=True)
   root=Path(__file__).resolve().parents[2]
   for n in p.SOURCES: shutil.copyfile(root/"supabase/migrations"/n,dest/n)
   for n in p.SOURCES:
    file=dest/n;raw=file.read_bytes();file.write_bytes(raw+b"\n")
    with self.assertRaises(ValueError):p.compose(d)
    file.write_bytes(raw)
 def test_envelope_fails_even_if_hash_is_reapproved(self):
  with tempfile.TemporaryDirectory() as d:
   dest=Path(d)/"supabase/migrations";dest.mkdir(parents=True)
   name=next(iter(p.SOURCES));data=b"BEGIN;\nselect 1;\ncommit;\n";(dest/name).write_bytes(data)
   with patch.dict(p.SOURCES,{name:p.hashlib.sha256(data).hexdigest()},clear=True):
    with self.assertRaises(ValueError):p.compose(d)
if __name__=="__main__":unittest.main()
