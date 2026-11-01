"""Exercise actual Git scans, without printing or storing real credentials."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

SCANNER = Path(__file__).resolve().parents[1] / 'check_no_client_secrets.sh'

class SecretScanTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        subprocess.run(['git', 'init', '-q', str(self.root)], check=True)
        (self.root / 'tool').mkdir()
        shutil.copyfile(SCANNER, self.root / 'tool/check_no_client_secrets.sh')
        self.track()

    def track(self):
        subprocess.run(['git', 'add', '.'], cwd=self.root, check=True)

    def scan(self, **kwargs):
        return subprocess.run(['bash', str(self.root / 'tool/check_no_client_secrets.sh')],
                              cwd=kwargs.pop('cwd', self.root), capture_output=True, text=True, **kwargs)

    def test_clean_tracked_source(self):
        (self.root / 'app.txt').write_text('public configuration only')
        self.track()
        self.assertEqual(self.scan().returncode, 0)

    def test_detects_secret_and_reports_path_without_value(self):
        value = 'sb_' + 'secret_' + 'syntheticfixturevalue012345'
        (self.root / 'app.txt').write_text(value)
        self.track()
        result = self.scan()
        self.assertEqual(result.returncode, 1)
        self.assertIn('app.txt', result.stdout)
        self.assertNotIn(value, result.stdout + result.stderr)

    def test_missing_checkout_is_not_clean(self):
        outside = self.root / 'outside'
        outside.mkdir()
        shutil.rmtree(self.root / '.git')
        result = self.scan(cwd=outside)
        self.assertEqual(result.returncode, 2)
        self.assertNotIn('No tracked production', result.stdout)

    def test_git_grep_failure_is_not_clean(self):
        bindir = self.root / 'bin'
        bindir.mkdir()
        real_git = shutil.which('git')
        shim = bindir / 'git'
        shim.write_text('#!/bin/sh\nif [ "$1" = grep ]; then exit 2; fi\nexec "' + real_git + '" "$@"\n')
        shim.chmod(0o700)
        result = self.scan(env={**os.environ, 'PATH': str(bindir) + os.pathsep + os.environ['PATH']})
        self.assertEqual(result.returncode, 2)
        self.assertNotIn('No tracked production', result.stdout)

if __name__ == '__main__':
    unittest.main()
