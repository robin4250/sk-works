import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('recovery', Path(__file__).with_name('recovery_source.py'))
r = importlib.util.module_from_spec(spec)
spec.loader.exec_module(r)


class RecoveryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.parent = Path(self.temp.name)
        self.repo = self.parent / 'source'
        self.repo.mkdir()
        r.command(self.repo, 'init', '-b', 'main')
        (self.repo / 'roles.json').write_text(json.dumps({'admin_id': 'synthetic-admin', 'company_id': 'synthetic-company', 'role': 'owner'}))
        (self.repo / 'keep.txt').write_text('committed')
        r.command(self.repo, 'add', '--all')
        r.command(self.repo, '-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '-m', 'fixture')
        self.output = self.parent / 'backup'

    def test_restore_staged_unstaged_untracked_and_no_source_mutation(self):
        (self.repo / 'keep.txt').write_text('staged')
        r.command(self.repo, 'add', 'keep.txt')
        (self.repo / 'keep.txt').write_text('staged plus unsaved')
        (self.repo / 'new.txt').write_text('untracked')
        before = r.state(self.repo)
        r.snapshot(self.repo, self.output)
        result = r.rehearse(self.output, self.parent)
        self.assertTrue(result['source_files_equal'])
        self.assertTrue(result['staged_index_equal'])
        self.assertEqual(r.state(self.repo), before)
        self.assertFalse(result['database_restore_executed'])
        self.assertFalse(result['production_permission_change_authorized'])
        self.assertEqual(self.output.stat().st_mode & 0o777, 0o700)
        self.assertEqual((self.output / 'manifest.json').stat().st_mode & 0o777, 0o600)

    def test_staged_delete_add_and_executable_restore(self):
        (self.repo / 'keep.txt').unlink()
        (self.repo / 'run.sh').write_text('#!/bin/sh\nexit 0\n')
        (self.repo / 'run.sh').chmod(0o700)
        r.command(self.repo, 'add', '--all')
        r.snapshot(self.repo, self.output)
        self.assertTrue(r.rehearse(self.output, self.parent)['dirty_status_equal'])

    def test_existing_output_and_output_inside_git_refused(self):
        self.output.mkdir()
        (self.output / 'sentinel').write_text('keep')
        with self.assertRaises(ValueError): r.snapshot(self.repo, self.output)
        self.assertEqual((self.output / 'sentinel').read_text(), 'keep')
        with self.assertRaises(ValueError): r.snapshot(self.repo, self.repo / 'unsafe')
        self.assertFalse((self.repo / 'unsafe').exists())

    def test_tampered_snapshot_and_inside_git_restore_refused(self):
        r.snapshot(self.repo, self.output)
        with self.assertRaises(ValueError): r.rehearse(self.output, self.repo)
        (self.output / 'working.patch').write_bytes(b'tampered')
        with self.assertRaises(ValueError): r.rehearse(self.output, self.parent)

    def test_symlink_never_follows_secret_or_backup_output(self):
        (self.repo / 'link').symlink_to('/etc/passwd')
        with self.assertRaises(ValueError): r.snapshot(self.repo, self.output)
        self.assertFalse(self.output.exists())

    def test_database_guard_rejects_prod_remote_credentials_and_nonfresh_names(self):
        for url in ['postgres://ztktgquxvcxcjxtluspu.supabase.co/db',
                    'postgres://db.example.invalid:5432/sko_recovery_fixture_' + 'a' * 32,
                    'postgres://user:secret@127.0.0.1:5432/sko_recovery_fixture_' + 'a' * 32,
                    'postgres://127.0.0.1:5432/postgres',
                    'postgres://localhost:5432/sko_recovery_fixture_' + 'a' * 32,
                    'postgres://127.0.0.1:5432/sko_recovery_fixture_' + 'a' * 32 + '?host=remote']:
            with self.assertRaises(ValueError): r.database_target_shape(url)
        result = r.database_target_shape('postgres://127.0.0.1:5432/sko_recovery_fixture_' + 'a' * 32)
        self.assertFalse(result['fresh_database_verified'])
        self.assertFalse(result['database_restore_authorized'])

    def test_cli_guard_never_prints_credentials_or_real_identifier(self):
        result = subprocess.run(['python3', r.__file__, 'database-target-shape', '--target',
            'postgres://synthetic-secret@ztktgquxvcxcjxtluspu.supabase.co:5432/postgres'], capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn(b'synthetic-secret', result.stdout + result.stderr)
        self.assertNotIn(b'ztktgquxvcxcjxtluspu', result.stdout + result.stderr)


if __name__ == '__main__':
    unittest.main()
