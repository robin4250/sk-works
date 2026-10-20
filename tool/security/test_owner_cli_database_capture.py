from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import owner_cli_database_capture as cli


def script(**overrides):
    values = dict(PGHOST='aws-0-ap-northeast-1.pooler.supabase.com', PGPORT='6543',
                  PGUSER='cli_login_postgres.' + cli.capture.PROJECT,
                  PGPASSWORD='synthetic-secret', PGDATABASE='postgres')
    values.update(overrides)
    return '\n'.join(f'export {key}="{value}"' for key, value in values.items())


class CliTests(unittest.TestCase):
    def test_session_mode_and_temporary_user_only(self):
        url, password = cli.parse_cli_script(script())
        self.assertIn(':5432/postgres', url)
        self.assertNotIn(password, url)
        self.assertEqual(password, 'synthetic-secret')
        self.assertTrue(cli.capture.endpoint(url, cli_login=True)['PGUSER'].startswith('cli_login_'))
        with self.assertRaises(ValueError):
            cli.capture.endpoint(url)
        for changes in (
            dict(PGUSER='cli_login_postgres.other'),
            dict(PGHOST='aws-0-ap-northeast-1.pooler.supabase.com.evil.invalid'),
            dict(PGPORT='1234'), dict(PGDATABASE='other'),
            dict(PGUSER='postgres.' + cli.capture.PROJECT), dict(PGPASSWORD=''),
        ):
            with self.assertRaises((ValueError, cli.capture.CaptureFailure)):
                cli.parse_cli_script(script(**changes))

    def test_no_shell_evaluation_or_raw_output_and_clean_workdir(self):
        secret = '$(do-not-execute)`do-not-execute`'
        with tempfile.TemporaryDirectory() as folder:
            def run(command, **kwargs):
                self.assertIsInstance(command, list)
                self.assertNotIn('shell', kwargs)
                self.assertNotIn(secret, ' '.join(command))
                self.assertEqual(command[command.index('--project-ref') + 1], cli.capture.PROJECT)
                self.assertEqual(command[command.index('--workdir') + 1], folder)
                self.assertIn('--dry-run', command)
                self.assertEqual(kwargs['stdin'], subprocess.DEVNULL)
                self.assertEqual(kwargs['env']['SUPABASE_DB_PASSWORD'], '')
                self.assertNotIn('PGPASSWORD', kwargs['env'])
                return subprocess.CompletedProcess(command, 0, script(PGPASSWORD=secret), '')
            with patch.dict(cli.os.environ, {'PGPASSWORD':'old', 'SUPABASE_DB_PASSWORD':'old'}), patch.object(cli.subprocess, 'run', side_effect=run):
                url, password = cli.obtain_connection(Path(folder))
            self.assertEqual(password, secret)
            self.assertNotIn(secret, url)

    def test_duplicate_or_missing_exports_fail_closed(self):
        for malformed in (script() + '\nexport PGUSER="other"', 'not a pg dump script'):
            with self.assertRaises(cli.capture.CaptureFailure):
                cli.parse_cli_script(malformed)

    def test_cli_failure_does_not_echo_secret(self):
        result = subprocess.CompletedProcess([], 1, 'secret-value', 'secret-value')
        with patch.object(cli.subprocess, 'run', return_value=result):
            with self.assertRaises(cli.capture.CaptureFailure) as caught:
                cli.obtain_connection(Path('/synthetic'))
        self.assertEqual(str(caught.exception), 'cli_connection_failed')

    def test_temporary_role_dump_records_side_effect_and_steps_down(self):
        url, password = cli.parse_cli_script(script())
        with tempfile.TemporaryDirectory() as folder:
            cert = Path(folder) / 'ca.crt'
            cert.write_text('synthetic')
            def run(command, **kwargs):
                if command[0] in ('pg_dump', 'pg_dumpall'):
                    self.assertIn('--role=postgres', command)
                    Path(command[command.index('--file') + 1]).write_bytes(b'synthetic')
                self.assertEqual(kwargs['env']['PGSSLMODE'], 'verify-full')
                self.assertEqual(kwargs['env']['PGOPTIONS'], '-c default_transaction_read_only=on')
                return subprocess.CompletedProcess(command, 0, b'170006\n')
            with patch.object(cli.capture, 'tool', side_effect=lambda x:x), patch.object(cli.capture.subprocess, 'run', side_effect=run):
                stage = cli.capture.capture(url, password, Path(folder), cert, cli_login=True)
            import json
            status = json.loads((stage/'capture-status.json').read_text())
            self.assertTrue(status['cli_temporary_role_requested'])
            self.assertTrue(status['production_mutations'])
            self.assertFalse(status['application_data_mutations'])
            self.assertFalse(status['restore_verified'])


if __name__ == '__main__':
    unittest.main()
