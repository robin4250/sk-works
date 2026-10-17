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
 def test_actual_universal_header_contract(self):
  b=pathlib.Path("/Library/Frameworks/Python.framework/Versions/3.12/bin/python3.12")
  sample=str(b)+" (architecture x86_64):\n\t/usr/lib/libSystem.B.dylib (compatibility version 1.0.0, current version 1345.0.0)\n"+str(b)+" (architecture arm64):\n\t/usr/lib/libSystem.B.dylib (compatibility version 1.0.0, current version 1345.0.0)\n"
  self.assertEqual(p.parse_otool(sample,b),["/usr/lib/libSystem.B.dylib"]*2)
 def test_unknown_or_other_filename_header_is_not_skipped(self):
  b=pathlib.Path("/opt/runtime/python")
  for sample in (str(b)+" (architecture unknown):\n", "/other/python (architecture arm64):\n",str(b)+":\nUNKNOWN\n",str(b)+":\n\n"):
   with self.assertRaises(ValueError):p.parse_otool(sample,b)
 def test_library_before_header_and_duplicate_header_refused(self):
  b=pathlib.Path("/opt/runtime/python")
  for sample in ("\t/usr/lib/libSystem.B.dylib (compatibility version 1.0.0, current version 1.0.0)\n",str(b)+":\n"+str(b)+":\n"):
   with self.assertRaises(ValueError):p.parse_otool(sample,b)
 def timezone_package(self,d):
  root=pathlib.Path(d)/"brew/Cellar/postgresql@17/17.7";bin=root/"bin";bin.mkdir(parents=True)
  data=root/"share/postgresql/timezone";data.mkdir(parents=True)
  for name in ("postgres","psql","initdb","pg_ctl","pg_config"):(bin/name).write_bytes(b"synthetic-runtime")
  shared=pathlib.Path(d)/"brew/share/postgresql@17";shared.mkdir(parents=True)
  alias=shared/"timezone";alias.symlink_to(data,target_is_directory=True)
  def runner(argv,**kw):
   values={"--version":"PostgreSQL 17.7","--bindir":str(bin),"--sharedir":str(shared)}
   return type("Result",(),{"stdout":values[argv[-1]]+"\n"})()
  return bin,data,shared,alias,runner
 def test_exact_timezone_alias_only(self):
  with tempfile.TemporaryDirectory() as d:
   bin,data,shared,alias,runner=self.timezone_package(d)
   allowed,proof=p.timezone_runtime(bin,runner)
   self.assertEqual(allowed,(alias,));self.assertEqual(proof["timezone_canonical"],str(data))
   self.assertEqual(set(proof["binary_sha256"]),{"postgres","psql","initdb","pg_ctl","pg_config"})
   profile=p.profile(pathlib.Path("/tmp/inside"),pathlib.Path("/tmp/inside/socket"),[],allowed)
   self.assertIn('(literal "'+str(alias)+'")',profile)
   self.assertNotIn('(subpath "'+str(shared)+'")',profile)
 def test_timezone_alias_drift_external_config_and_writable_mode_refused(self):
  with tempfile.TemporaryDirectory() as d:
   bin,data,shared,alias,runner=self.timezone_package(d)
   other=pathlib.Path(d)/"other";other.mkdir()
   alias.unlink();alias.symlink_to(other,target_is_directory=True)
   with self.assertRaises(ValueError):p.timezone_runtime(bin,runner)
   alias.unlink();alias.symlink_to(data,target_is_directory=True)
   data.chmod(0o777)
   with self.assertRaises(ValueError):p.timezone_runtime(bin,runner)
   data.chmod(0o700);config=bin/"pg_config";config.unlink();external=other/"pg_config";external.write_bytes(b"other");config.symlink_to(external)
   with self.assertRaises(ValueError):p.timezone_runtime(bin,runner)
 def test_unknown_sharedir_version_bindir_refused(self):
  with tempfile.TemporaryDirectory() as d:
   bin,data,shared,alias,runner=self.timezone_package(d)
   for flag,value in (("--sharedir",str(pathlib.Path(d))),("--version","PostgreSQL 18.0"),("--bindir",str(pathlib.Path(d)))):
    def bad(argv,**kw):
     if argv[-1]==flag:return type("Result",(),{"stdout":value+"\n"})()
     return runner(argv,**kw)
    with self.assertRaises(ValueError):p.timezone_runtime(bin,bad)
 def test_runtime_directory_wrong_owner_refused(self):
  with tempfile.TemporaryDirectory() as d:
   bin,data,shared,alias,runner=self.timezone_package(d);original=pathlib.Path.stat
   def changed(path,*args,**kwargs):
    info=original(path,*args,**kwargs)
    if path==shared:
     values=list(info);values[4]=info.st_uid+1
     return p.os.stat_result(values)
    return info
   with patch.object(pathlib.Path,"stat",changed):
    with self.assertRaises(ValueError):p.timezone_runtime(bin,runner)
 def real_timezone_tree(self,d):
  bin,data,shared,alias,runner=self.timezone_package(d)
  (data/"UTC").write_bytes(b"synthetic-zone")
  (data/"Zone").mkdir();(data/"Zone/Demo").write_bytes(b"synthetic-other-zone")
  alias.unlink();alias.mkdir()
  (alias/"UTC").symlink_to(data/"UTC")
  (alias/"Zone").mkdir();(alias/"Zone/Demo").symlink_to(data/"Zone/Demo")
  return bin,data,shared,alias,runner
 def test_closed_real_directory_tree_uses_only_exact_literals(self):
  with tempfile.TemporaryDirectory() as d:
   bin,data,shared,alias,runner=self.real_timezone_tree(d)
   literals,proof=p.timezone_runtime(bin,runner)
   self.assertEqual(set(literals),{alias,alias/"UTC",alias/"Zone",alias/"Zone/Demo"})
   self.assertEqual(proof["timezone_entry_count"],4)
   profile=p.profile(pathlib.Path("/tmp/inside"),pathlib.Path("/tmp/inside/socket"),[],literals)
   self.assertNotIn('(subpath "'+str(alias)+'")',profile)
   prior=proof;(data/"UTC").write_bytes(b"synthetic-new-zone")
   self.assertNotEqual(p.timezone_runtime(bin,runner)[1],prior,"content drift changes comparison snapshot")
 def test_unknown_entry_or_outside_file_and_directory_link_refused(self):
  with tempfile.TemporaryDirectory() as d:
   bin,data,shared,alias,runner=self.real_timezone_tree(d)
   (alias/"unknown").write_bytes(b"must-not-be-granted")
   with self.assertRaises(ValueError):p.timezone_runtime(bin,runner)
   (alias/"unknown").unlink()
   outside=pathlib.Path(d)/"outside";outside.mkdir();(outside/"secret").write_bytes(b"synthetic-private")
   (alias/"UTC").unlink();(alias/"UTC").symlink_to(outside/"secret")
   with self.assertRaises(ValueError):p.timezone_runtime(bin,runner)
   (alias/"UTC").unlink();(alias/"UTC").symlink_to(data/"UTC")
   (alias/"Zone/Demo").unlink();(alias/"Zone").rmdir();(alias/"Zone").symlink_to(outside,target_is_directory=True)
   with self.assertRaises(ValueError):p.timezone_runtime(bin,runner)
 def test_timezone_tree_count_and_size_bounds(self):
  with tempfile.TemporaryDirectory() as d:
   bin,data,shared,alias,runner=self.real_timezone_tree(d)
   with patch.object(p,"MAX_TIMEZONE_ENTRIES",2):
    with self.assertRaises(ValueError):p.timezone_runtime(bin,runner)
   with patch.object(p,"MAX_TIMEZONE_BYTES",1):
    with self.assertRaises(ValueError):p.timezone_runtime(bin,runner)

 def test_pkglib_listing_only_and_foreign_entries_refused(self):
  with tempfile.TemporaryDirectory() as d:
   bin,data,shared,alias,runner=self.timezone_package(d)
   canonical=bin.parent/"lib/postgresql";canonical.mkdir(parents=True)
   (canonical/"plpgsql.so").write_bytes(b"synthetic-never-loaded")
   dest=bin.parent.parents[2]/"lib/postgresql@17";dest.mkdir(parents=True)
   (dest/"plpgsql.so").symlink_to(canonical/"plpgsql.so")
   def config(argv,**kw):
    if argv[-1]=="--pkglibdir":return type("Result",(),{"stdout":str(dest)+"\n"})()
    return runner(argv,**kw)
   literal,proof=p.pkglib_directory(bin,config)
   self.assertEqual(literal,dest)
   policy=p.profile(pathlib.Path("/tmp/inside"),pathlib.Path("/tmp/inside/socket"),[],[literal])
   self.assertIn('(literal "'+str(dest)+'")',policy)
   self.assertNotIn('(subpath "'+str(dest)+'")',policy)
   self.assertNotIn(str(dest/"plpgsql.so"),policy)
   (dest/"unknown").write_bytes(b"unknown")
   with self.assertRaises(ValueError):p.pkglib_directory(bin,config)
   (dest/"unknown").unlink();(dest/"plpgsql.so").unlink()
   outside=pathlib.Path(d)/"outside.so";outside.write_bytes(b"synthetic")
   (dest/"plpgsql.so").symlink_to(outside)
   with self.assertRaises(ValueError):p.pkglib_directory(bin,config)
 def test_pkglib_unknown_path_and_writable_directory_refused(self):
  with tempfile.TemporaryDirectory() as d:
   bin,data,shared,alias,runner=self.timezone_package(d)
   canonical=bin.parent/"lib/postgresql";canonical.mkdir(parents=True)
   dest=bin.parent.parents[2]/"lib/postgresql@17";dest.mkdir(parents=True)
   def config(argv,**kw):return type("Result",(),{"stdout":str(dest)+"\n"})()
   p.pkglib_directory(bin,config)
   dest.chmod(0o777)
   with self.assertRaises(ValueError):p.pkglib_directory(bin,config)
   dest.chmod(0o700)
   def bad(argv,**kw):return type("Result",(),{"stdout":str(canonical)+"\n"})()
   with self.assertRaises(ValueError):p.pkglib_directory(bin,bad)


 def test_pkglib_pgxs_real_directory_closed_metadata_no_child_grants(self):
  with tempfile.TemporaryDirectory() as d:
   bin,data,shared,alias,runner=self.timezone_package(d)
   canonical=bin.parent/"lib/postgresql";(canonical/"pgxs/src").mkdir(parents=True)
   (canonical/"pgxs/src/Makefile").write_bytes(b"synthetic-never-read")
   (canonical/"pkgconfig").mkdir();(canonical/"pkgconfig/libpq.pc").write_bytes(b"synthetic-pkgconfig")
   dest=bin.parent.parents[2]/"lib/postgresql@17";(dest/"pgxs/src").mkdir(parents=True)
   (dest/"pgxs/src/Makefile").symlink_to(canonical/"pgxs/src/Makefile")
   (dest/"pkgconfig").mkdir();(dest/"pkgconfig/libpq.pc").symlink_to(canonical/"pkgconfig/libpq.pc")
   def config(argv,**kw):return type("Result",(),{"stdout":str(dest)+"\n"})()
   literal,proof=p.pkglib_directory(bin,config)
   self.assertEqual(literal,dest)
   self.assertEqual(len(proof["entries"]),5)
   policy=p.profile(pathlib.Path("/tmp/inside"),pathlib.Path("/tmp/inside/socket"),[],[literal])
   self.assertNotIn(str(dest/"pgxs"),policy)
   (dest/"pgxs/unknown").write_bytes(b"unknown")
   with self.assertRaises(ValueError):p.pkglib_directory(bin,config)
   (dest/"pgxs/unknown").unlink()
   (dest/"pgxs/src/Makefile").unlink()
   outside=pathlib.Path(d)/"outside";outside.write_bytes(b"synthetic")
   (dest/"pgxs/src/Makefile").symlink_to(outside)
   with self.assertRaises(ValueError):p.pkglib_directory(bin,config)

if __name__=="__main__":unittest.main()
