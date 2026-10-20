import contextlib
import io
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import owner_attendance_day13_rehearsal as attendance


class AttendanceCloneTests(unittest.TestCase):
    def test_clone_has_no_ip_ports_host_mounts_or_cron(self):
        command = attendance.clone_command('fixture', 'sha256:' + 'a' * 64)
        self.assertIn('--network=none', command)
        self.assertIn('listen_addresses=', command)
        self.assertIn('cron.launch_active_jobs=off', command)
        for forbidden in ('--mount', '--publish', '--privileged', 'PGPASSWORD'):
            self.assertNotIn(forbidden, command)

    def lifecycle(self, fail_rpc=False, drift=False, source_running=False, stop_failure=None):
        with tempfile.TemporaryDirectory() as folder:
            home = Path(folder)
            root = home / 'SKO-source-backups'
            root.mkdir(mode=0o700)
            source = root / attendance.SOURCE
            source.mkdir(mode=0o700)
            original_name = 'sko-restore-' + 'b' * 12
            (source / 'rehearsal-status.json').write_text(json.dumps({
                'archive_restore_verified': True, 'container_stopped': True,
                'container': original_name,
            }))
            calls = []
            inventory_reads = 0

            def run(command, **kwargs):
                nonlocal inventory_reads
                calls.append(command)
                self.assertNotIn('shell', kwargs)
                output = b''
                if command[:3] == ['docker', 'context', 'inspect']:
                    output = json.dumps([{'Endpoints': {'docker': {'Host': 'unix:///synthetic'}}}]).encode()
                elif command[:2] == ['docker', 'inspect']:
                    output = json.dumps([{
                        'State': {'Running': source_running if command[-1] == original_name else False},
                        'HostConfig': {'NetworkMode': 'none', 'PortBindings': {}},
                        'Config': {'Image': attendance.BASE_IMAGE, 'Labels': {'sko-purpose': 'offline-restore'}},
                    }]).encode()
                elif command[:2] == ['docker', 'commit']:
                    output = ('sha256:' + 'a' * 64).encode()
                elif command[:2] == ['docker', 'stop']:
                    if stop_failure == 'timeout':
                        raise subprocess.TimeoutExpired(command, 30)
                    if stop_failure == 'nonzero':
                        return subprocess.CompletedProcess(command, 1, output)
                elif command == ['/usr/bin/pbcopy'] and stop_failure:
                    self.assertIn('停止を確認できません', kwargs['input'])
                    self.assertNotIn('rollback成功', kwargs['input'])
                elif 'psql' in command:
                    sql = kwargs['input'].decode()
                    if 'SHOW cron.launch_active_jobs' in sql:
                        output = b'off\n'
                    elif "SELECT to_regprocedure('private.payroll_draft_source_fingerprint(uuid,uuid,date)') IS NULL;" in sql:
                        output = b't\n'
                    elif 'CREATE TEMP TABLE attendance_clone_inventory' in sql:
                        inventory_reads += 1
                        output = json.dumps([{'table': 'synthetic', 'hash': 2 if drift and inventory_reads == 2 else 1}]).encode()
                    elif 'DO $preflight$' in sql:
                        self.assertIn('BEGIN;', sql)
                        self.assertIn('ROLLBACK;', sql)
                        self.assertIn('SET LOCAL ROLE authenticated', sql)
                        self.assertNotIn('COMMIT;', sql)
                        if fail_rpc:
                            raise subprocess.CalledProcessError(1, command)
                return subprocess.CompletedProcess(command, 0, output)

            with patch.object(attendance.sys, 'platform', 'darwin'), \
                    patch.object(attendance.Path, 'home', return_value=home), \
                    patch.dict(attendance.os.environ, {}, clear=True), \
                    patch.object(attendance.subprocess, 'run', side_effect=run), \
                    contextlib.redirect_stdout(io.StringIO()):
                code = attendance.main()
            stage = next(root.glob('attendance-day13-rehearsal-*'))
            status = json.loads((stage / 'attendance-rehearsal-status.json').read_text())
            self.assertFalse(any(c[:2] in (['docker', 'start'], ['docker', 'stop']) and original_name in c for c in calls))
            self.assertTrue(any(c == ['/usr/bin/pbcopy'] for c in calls))
            return code, status

    def test_success_rolls_back_and_only_stops_clone(self):
        code, status = self.lifecycle()
        self.assertEqual(code, 0)
        self.assertTrue(status['verified'])
        self.assertTrue(status['all_table_rows_rollback_verified'])
        self.assertTrue(status['container_stopped'])
        self.assertFalse(status['real_jwt_verified'])
        self.assertFalse(status['production_connected'])
        self.assertFalse(status['production_rows_repaired'])

    def test_rpc_failure_never_claims_success_and_stops_clone(self):
        code, status = self.lifecycle(fail_rpc=True)
        self.assertEqual(code, 1)
        self.assertFalse(status['verified'])
        self.assertEqual(status['phase'], 'actual_attendance')
        self.assertTrue(status['container_stopped'])

    def test_row_drift_refuses_success(self):
        code, status = self.lifecycle(drift=True)
        self.assertEqual(code, 1)
        self.assertFalse(status['verified'])
        self.assertEqual(status['phase'], 'full_table_rollback')

    def test_running_original_is_not_cloned_or_stopped(self):
        code, status = self.lifecycle(source_running=True)
        self.assertEqual(code, 1)
        self.assertFalse(status['verified'])
        self.assertNotIn('container', status)

    def test_nonzero_clone_stop_refuses_success(self):
        code, status = self.lifecycle(stop_failure='nonzero')
        self.assertEqual(code, 1)
        self.assertFalse(status['verified'])
        self.assertFalse(status['container_stopped'])
        self.assertEqual(status['phase'], 'clone_stop')

    def test_clone_stop_timeout_refuses_success(self):
        code, status = self.lifecycle(stop_failure='timeout')
        self.assertEqual(code, 1)
        self.assertFalse(status['verified'])
        self.assertFalse(status['container_stopped'])
        self.assertEqual(status['phase'], 'clone_stop')


if __name__ == '__main__':
    unittest.main()
