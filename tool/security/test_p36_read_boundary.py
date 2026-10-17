import importlib.util, pathlib, tempfile, unittest
from unittest.mock import patch
spec=importlib.util.spec_from_file_location("p36",pathlib.Path(__file__).with_name("p36_read_boundary.py"));p=importlib.util.module_from_spec(spec);spec.loader.exec_module(p)
class ReadBoundary(unittest.TestCase):
 def test_allowlist_no_global_data_read(self):
  s=p.profile(pathlib.Path("/private/tmp/owned"),pathlib.Path("/private/tmp/owned/socket"),[pathlib.Path("/opt/runtime/17")],[pathlib.Path("/opt/library.dylib")])
  self.assertNotIn("(allow file-read*)",s)
  self.assertIn("(allow file-read-metadata)",s)
  self.assertIn('(allow file-read-data (subpath "/opt/runtime/17"))',s)
  self.assertIn('(allow file-read-data (literal "/opt/library.dylib"))',s)
  self.assertNotIn('(subpath "/Users")',s);self.assertIn('(deny network*)',s)
 def test_socket_boundary(self):
  with self.assertRaises(ValueError):p.profile(pathlib.Path("/tmp/a"),pathlib.Path("/tmp/b/socket"),[],[])
 def test_quote(self):
  self.assertEqual(p.quote('/tmp/a"b'),'\"/tmp/a\\\"b\"')
  with self.assertRaises(ValueError):p.quote("/tmp/a\n")
 def test_broad_runtime_refused(self):
  for root in ("/","/usr","/opt",str(pathlib.Path.home())):
   with self.assertRaises(ValueError):p.runtime_root(root)
 def test_unknown_dylib_refused(self):
  with self.assertRaises(ValueError):p.library_reference("@rpath/libx.dylib",pathlib.Path("/opt/runtime/bin/postgres"))
  self.assertEqual(p.library_reference("@loader_path/../lib/libx.dylib",pathlib.Path("/opt/runtime/bin/postgres")),pathlib.Path("/opt/runtime/bin/../lib/libx.dylib"))
 def test_source_hash_before_import(self):
  with tempfile.TemporaryDirectory() as d:
   path=pathlib.Path(d)/"native.py";path.write_text("raise AssertionError('must not execute')")
   with self.assertRaises(ValueError):p.load_native(path)
 def test_missing_probe_has_no_subprocess(self):
  with patch.object(p.sys,"argv",["p36","--sources","/tmp","--pg-bin","/tmp","--output-parent","/tmp"]),patch.object(p.subprocess,"run",side_effect=AssertionError("unexpected process")):
   self.assertEqual(p.main(),2)
if __name__=="__main__":unittest.main()
