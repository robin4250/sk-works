import contextlib
import importlib.util
import io
from pathlib import Path
import sys
import tempfile
import types
import unittest
from unittest.mock import patch

spec=importlib.util.spec_from_file_location('native',Path(__file__).with_name('entry_native_probe.py'))
native=importlib.util.module_from_spec(spec);spec.loader.exec_module(native)


class NativeTests(unittest.TestCase):
    def test_failed_kernel_probe_blocks_native_work_and_restores_arguments(self):
        original=sys.argv
        guard=types.SimpleNamespace(main=lambda:1)
        with self.assertRaises(ValueError):native.verify_host(guard,Path('/private/example'))
        self.assertIs(sys.argv,original)

    def test_no_probe_is_inert(self):
        with patch.object(sys,'argv',['native','--pg-bin','/unused']),patch.object(native.subprocess,'Popen') as run,contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(native.main(),2)
        run.assert_not_called()

    def test_unsupported_platform_never_starts_database(self):
        with patch.object(sys,'argv',['native','--probe','--pg-bin','/unused']),patch.object(sys,'platform','linux'),patch.object(native.subprocess,'Popen') as run,contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(native.main(),1)
        run.assert_not_called()

    def test_guard_mismatch_never_imports(self):
        with tempfile.TemporaryDirectory() as td:
            p=Path(td)/'guard.py';marker=Path(td)/'executed'
            p.write_text('from pathlib import Path\nPath('+repr(str(marker))+').touch()')
            with self.assertRaises(ValueError):native.load_guard(p)
            self.assertFalse(marker.exists())

    def test_environment_has_no_inherited_credentials_or_preloads(self):
        env=native.clean_environment(Path('/private/new'),{'PGHOST':'production','PGPASSWORD':'SYNTHETIC-SECRET',
            'SUPABASE_ACCESS_TOKEN':'SYNTHETIC-SECRET','DYLD_INSERT_LIBRARIES':'SYNTHETIC-SECRET','PSQLRC':'SYNTHETIC-SECRET'})
        self.assertFalse(any(k.upper().startswith('PG') for k in env))
        self.assertNotIn('SYNTHETIC-SECRET',str(env))
        self.assertEqual(env['HOME'],'/private/new')

    def test_strict_sql_evidence(self):
        native.parse_flags('{"reader_access":true}\n{"rollback_preserved":true}\n{"synthetic_cleanup":true}\n')
        for value in ('false','1','"true"','null'):
            with self.assertRaises(ValueError):native.parse_flags('{"reader_access":'+value+'}\n{"rollback_preserved":true}\n{"synthetic_cleanup":true}')
        with self.assertRaises(ValueError):native.parse_flags('{}')
        self.assertNotIn('auth.',native.SQL)
        self.assertNotIn('master_',native.SQL)


if __name__=='__main__':unittest.main()
