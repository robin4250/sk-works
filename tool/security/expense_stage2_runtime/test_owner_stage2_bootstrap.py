import contextlib
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import owner_stage2_bootstrap as bootstrap


class BootstrapBoundaryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.home = Path(self.temp.name)
        self.root = self.home/'SKO-source-backups'/('expense-default-off-production-'+bootstrap.PROJECT)
        self.root.mkdir(mode=0o700, parents=True)
        self.stack = contextlib.ExitStack()
        self.stack.enter_context(patch.object(bootstrap.Path,'home',return_value=self.home))
        self.stack.enter_context(patch.object(bootstrap.sys,'platform','darwin'))
        self.stack.enter_context(patch.object(bootstrap.sys,'flags',SimpleNamespace(isolated=1)))
        self.fetch=self.stack.enter_context(patch.object(bootstrap.subprocess,'run'))
        self.read=self.stack.enter_context(patch.object(bootstrap.subprocess,'check_output',return_value=b'changed'))

    def tearDown(self):
        self.stack.close()
        self.temp.cleanup()

    def test_existing_marker_refuses_before_fetch(self):
        (self.root/'expense-stage2-install-attempt.json').write_text('unknown')
        with self.assertRaisesRegex(RuntimeError,'previous_stage2_attempt'):bootstrap.run()
        self.fetch.assert_not_called()
        self.read.assert_not_called()

    def test_changed_source_refuses_before_package_or_import(self):
        with self.assertRaisesRegex(RuntimeError,'package_source_hash_changed'):bootstrap.run()
        self.assertFalse((self.root/'stage2-runtime').exists())

    def test_put_refuses_existing_bytes(self):
        target=self.root/'file'
        target.write_bytes(b'original')
        target.chmod(0o600)
        with self.assertRaisesRegex(RuntimeError,'existing_package_differs'):bootstrap.put(target,b'changed!')
        self.assertEqual(target.read_bytes(),b'original')


if __name__=='__main__':unittest.main()
