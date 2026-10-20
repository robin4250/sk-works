import contextlib
import io
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import owner_external_config_capture as capture


class ExternalCaptureTests(unittest.TestCase):
    def prepare(self, home):
        root = home / 'SKO-source-backups'
        root.mkdir(mode=0o700)
        original = root / capture.DATABASE_CAPTURE
        original.mkdir(mode=0o700)
        files = {}
        for name in ('database.dump', 'roles.sql', 'archive-list.txt'):
            p = original / name
            p.write_bytes(b'synthetic archive fixture')
            p.chmod(0o600)
            files[name] = {'bytes': p.stat().st_size, 'sha256': capture.digest(p)}
        status = original / 'capture-status.json'
        status.write_text(json.dumps({'capture_completed': True, 'files': files}))
        status.chmod(0o600)
        return root

    def runner(self, calls, help_missing=False, config_value='https://fixture.invalid'):
        def run(command, **kwargs):
            calls.append(command)
            self.assertNotIn('shell', kwargs)
            self.assertEqual(kwargs['stdin'], subprocess.DEVNULL)
            self.assertFalse(any(k.startswith(('PG', 'SUPABASE_')) for k in kwargs['env']))
            stdout = ''
            if command == ['supabase', '--version']:
                stdout = capture.CLI_VERSION + '\n'
            elif command == ['supabase', 'config', 'pull', '--help']:
                if help_missing:
                    return subprocess.CompletedProcess(command, 1, '', 'unsupported')
                stdout = 'supabase config pull --project-ref --force'
            elif command == ['supabase', 'functions', 'list', '--help']:
                stdout = '--project-ref'
            elif command == ['supabase', '--help']:
                stdout = '--output-format --yes --workdir'
            elif command[:3] == ['supabase', 'config', 'pull']:
                p = Path(command[command.index('--workdir') + 1]) / 'supabase' / 'config.toml'
                p.write_text('[auth]\nsite_url = "' + config_value + '"\n[auth.external.google]\nsecret = "private-fixture-secret"\n')
                stdout = 'private-fixture-secret'
            elif command[:3] == ['supabase', 'functions', 'list']:
                stdout = json.dumps({'data': [{'slug': 'fixture', 'version': 1}]})
            else:
                raise AssertionError('unexpected or write-capable command: ' + str(command))
            return subprocess.CompletedProcess(command, 0, stdout, '')
        return run

    def test_private_cli_read_capture_never_echoes_secrets_or_changes_original(self):
        with tempfile.TemporaryDirectory() as folder:
            home = Path(folder)
            root = self.prepare(home)
            original_status = root / capture.DATABASE_CAPTURE / 'capture-status.json'
            before = capture.digest(original_status)
            calls = []
            with patch.dict(capture.os.environ, {'SUPABASE_ACCESS_TOKEN': 'do-not-copy', 'PGPASSWORD': 'do-not-use'}, clear=False), \
                    patch.object(capture.subprocess, 'run', side_effect=self.runner(calls)), \
                    contextlib.redirect_stdout(io.StringIO()) as output:
                stage = capture.run_capture(root)
            status = json.loads((stage / 'external-status.json').read_text())
            self.assertTrue(status['captured'])
            self.assertFalse(status['project_settings_written'])
            self.assertFalse(status['database_connected'])
            self.assertFalse(status['full_platform_restore_verified'])
            self.assertEqual(status['storage_objects_in_scope'], 0)
            self.assertEqual(capture.digest(original_status), before)
            self.assertNotIn('private-fixture-secret', output.getvalue())
            self.assertTrue(all(not p.is_symlink() and not (p.stat().st_mode & 0o077) for p in stage.rglob('*')))
            self.assertFalse(any('push' in c or 'deploy' in c or 'storage' in c or 'api-keys' in c for c in calls))

    def test_unsupported_cli_command_stops_before_remote_capture(self):
        with tempfile.TemporaryDirectory() as folder:
            root = self.prepare(Path(folder))
            calls = []
            with patch.object(capture.subprocess, 'run', side_effect=self.runner(calls, help_missing=True)):
                with self.assertRaises(capture.CaptureFailure):
                    capture.run_capture(root)
            self.assertFalse(any(c[:3] == ['supabase', 'config', 'pull'] and '--help' not in c for c in calls))
            status = json.loads(next(root.glob('external-config-*/external-status.json')).read_text())
            self.assertFalse(status['captured'])

    def test_compare_unchanged_then_changed_config(self):
        with tempfile.TemporaryDirectory() as folder:
            root = self.prepare(Path(folder))
            with patch.object(capture.subprocess, 'run', side_effect=self.runner([])):
                first = capture.run_capture(root)
                second = capture.run_capture(root, first.name)
            self.assertTrue(json.loads((second / 'external-status.json').read_text())['previous_external_settings_match'])
            with patch.object(capture.subprocess, 'run', side_effect=self.runner([], config_value='https://changed.invalid')):
                with self.assertRaisesRegex(capture.CaptureFailure, 'external_settings_changed_review_required'):
                    capture.run_capture(root, first.name)

    def test_changed_archive_stops_before_cli(self):
        with tempfile.TemporaryDirectory() as folder:
            root = self.prepare(Path(folder))
            (root / capture.DATABASE_CAPTURE / 'database.dump').write_bytes(b'changed')
            with patch.object(capture.subprocess, 'run') as run:
                with self.assertRaisesRegex(capture.CaptureFailure, 'original_database_capture_changed'):
                    capture.run_capture(root)
            run.assert_not_called()

    def test_main_copies_safe_summary(self):
        with patch.object(capture.sys, 'platform', 'darwin'), \
                patch.object(capture.sys, 'argv', ['helper']), \
                patch.object(capture, 'run_capture', return_value=Path('/private/external-config-fixture')), \
                patch.object(capture.subprocess, 'run') as run, \
                contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(capture.main(), 0)
        self.assertEqual(run.call_args.args[0], ['/usr/bin/pbcopy'])
        self.assertIn('同時点整合は未検証', run.call_args.kwargs['input'])


if __name__ == '__main__':
    unittest.main()
