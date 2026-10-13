"""Disposable Git fixtures; no Mac, credentials or installation needed."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

from preserve_known_analysis_options import PREFIX

SCRIPT = Path(__file__).with_name("preserve_known_analysis_options.py")
BASE = b"include: package:flutter_lints/flutter.yaml\n\nlinter:\n"


class RecoveryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name) / "repo"
        self.root.mkdir()
        self.backups = Path(self.temp.name) / "backups"
        self.git("init", "-b", "main")
        self.git("config", "user.name", "fixture")
        self.git("config", "user.email", "fixture@example.invalid")
        self.source = self.root / "analysis_options.yaml"
        self.source.write_bytes(BASE)
        self.git("add", ".")
        self.git("commit", "-m", "fixture")
        self.source.write_bytes(PREFIX + BASE)

    def tearDown(self):
        self.temp.cleanup()

    def git(self, *args):
        return subprocess.check_output(["git", *args], cwd=self.root, stderr=subprocess.DEVNULL)

    def run_script(self):
        return subprocess.run(["python3", str(SCRIPT)], cwd=self.root,
                              env={**os.environ, "SKO_SOURCE_BACKUP_DIR": str(self.backups)},
                              capture_output=True)

    def test_exact_change_preserved_then_restored(self):
        self.assertEqual(self.run_script().returncode, 0)
        copies = list(self.backups.glob("*/analysis_options.yaml"))
        self.assertEqual(len(copies), 1)
        self.assertEqual(copies[0].read_bytes(), PREFIX + BASE)
        self.assertEqual(copies[0].stat().st_mode & 0o777, 0o600)
        self.assertEqual(copies[0].parent.stat().st_mode & 0o777, 0o700)
        self.assertEqual(self.source.read_bytes(), BASE)
        self.assertEqual(self.git("status", "--porcelain"), b"")
        self.assertEqual(self.run_script().returncode, 0)

    def test_other_dirty_or_staged_or_untracked_rejected(self):
        for case in ("untracked", "staged", "different", "branch"):
            with self.subTest(case=case):
                self.source.write_bytes(PREFIX + BASE)
                if case == "untracked":
                    (self.root / "other.txt").write_text("private fixture")
                elif case == "staged":
                    self.git("add", "analysis_options.yaml")
                elif case == "different":
                    self.source.write_bytes(PREFIX + BASE + b"# local edit\n")
                else:
                    self.git("checkout", "-b", "other")
                before = self.source.read_bytes()
                result = self.run_script()
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(self.source.read_bytes(), before)
                self.assertFalse(self.backups.exists())
                self.assertNotIn(b"private fixture", result.stdout + result.stderr)
                if case == "untracked":
                    (self.root / "other.txt").unlink()
                elif case == "staged":
                    self.git("reset", "HEAD", "analysis_options.yaml")
                elif case == "branch":
                    self.git("checkout", "main")


if __name__ == "__main__":
    unittest.main()
