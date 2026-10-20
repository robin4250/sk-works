import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import owner_database_capture as capture


URL = f'postgresql://postgres.{capture.PROJECT}:[YOUR-PASSWORD]@aws-0-ap-northeast-1.pooler.supabase.com:5432/postgres'


class CaptureTests(unittest.TestCase):
    def test_only_expected_project_session_or_direct_endpoint(self):
        self.assertEqual(capture.endpoint(URL)['PGUSER'], f'postgres.{capture.PROJECT}')
        direct = f'postgresql://postgres@db.{capture.PROJECT}.supabase.co:5432/postgres'
        self.assertEqual(capture.endpoint(direct)['PGHOST'], f'db.{capture.PROJECT}.supabase.co')
        for invalid in (URL.replace(capture.PROJECT, 'other'), URL.replace(':5432/', ':6543/'),
                        URL.replace('.pooler.supabase.com', '.pooler.supabase.com.attacker.invalid'),
                        URL + '?options=unsafe', URL + '#fragment', URL.replace('/postgres', '/other')):
            with self.assertRaises(ValueError):
                capture.endpoint(invalid)

    def test_secret_only_in_child_environment_and_archive_never_executed(self):
        calls = []
        def run(command, **kwargs):
            calls.append(command)
            self.assertNotIn('fixture-secret', ' '.join(command))
            self.assertEqual(kwargs['env']['PGPASSWORD'], 'fixture-secret')
            self.assertEqual(kwargs['env']['PGSSLMODE'], 'verify-full')
            self.assertEqual(kwargs['env']['PGOPTIONS'], '-c default_transaction_read_only=on')
            if command[0] in ('pg_dump', 'pg_dumpall'):
                Path(command[command.index('--file') + 1]).write_bytes(b'synthetic-fixture')
            if command[0] == 'pg_restore':
                self.assertTrue('--list' in command or command[command.index('--file') + 1] == '/dev/null')
                self.assertNotIn('--dbname', command)
            return subprocess.CompletedProcess(command, 0, stdout=b'170006\n')
        with tempfile.TemporaryDirectory() as folder, patch.object(capture, 'tool', side_effect=lambda n: n), patch.object(capture.subprocess, 'run', side_effect=run):
            stage = capture.capture(URL, 'fixture-secret', Path(folder))
            status = json.loads((stage / 'capture-status.json').read_text())
            self.assertTrue(status['capture_completed'])
            self.assertFalse(status['restore_verified'])
            self.assertFalse(status['production_mutations'])
            self.assertEqual(len(status['files']), 3)
            self.assertEqual([c[0] for c in calls], ['psql', 'pg_dump', 'pg_dumpall', 'pg_restore', 'pg_restore'])

    def test_failed_dump_never_becomes_completed_or_retried(self):
        def run(command, **kwargs):
            if command[0] == 'pg_dump':
                raise subprocess.CalledProcessError(1, command)
            return subprocess.CompletedProcess(command, 0, stdout=b'170006\n')
        with tempfile.TemporaryDirectory() as folder, patch.object(capture, 'tool', side_effect=lambda n: n), patch.object(capture.subprocess, 'run', side_effect=run) as runner:
            with self.assertRaises(subprocess.CalledProcessError):
                capture.capture(URL, 'fixture-secret', Path(folder))
            stages = list(Path(folder).glob('database-capture-*'))
            self.assertEqual(len(stages), 1)
            self.assertFalse(json.loads((stages[0] / 'capture-status.json').read_text())['capture_completed'])
            self.assertEqual(runner.call_count, 2)


if __name__ == '__main__':
    unittest.main()
