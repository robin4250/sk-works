import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('annual_owner', Path(__file__).with_name('runner.py'))
r = importlib.util.module_from_spec(spec)
spec.loader.exec_module(r)


class ProofFixture:
    before = {'schema': 1, 'original': 'unchanged'}
    install = b'exact reviewed fixture SQL'
    read_sql = b'read only checkpoint fixture'
    after_sql = b'read only reviewed postflight fixture'

    def before_ok(self, value):
        if value != self.before:
            raise ValueError('stale')

    def after_ok(self, value):
        if value != {'schema': 1, 'original': 'unchanged', 'new': 'empty'}:
            raise ValueError('used or changed')
        return b'unused removal fixture; review only'


class TransportFixture:
    def __init__(self, root, observations, install_error=False):
        self.root, self.observations = root, iter(observations)
        self.install_error, self.installs, self.reads = install_error, [], []

    def read(self, sql):
        self.reads.append(sql)
        value = next(self.observations)
        if isinstance(value, BaseException):
            raise value
        return value

    def install_once(self, sql):
        # The receipt must already be durably created before delivery.
        state = json.loads((self.root / r.MARKER).read_bytes())
        assert state['phase'] == 'attempt_recorded'
        assert state['retry_allowed'] is False
        self.installs.append(sql)
        if self.install_error:
            raise RuntimeError('synthetic transport disconnect')


class LifecycleTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.root.chmod(0o700)
        self.p = ProofFixture()
        self.after = {'schema': 1, 'original': 'unchanged', 'new': 'empty'}

    def tearDown(self):
        self.temp.cleanup()

    def test_normal_ack_exact_before_and_after_and_removal_not_executed(self):
        t = TransportFixture(self.root, [self.p.before, self.after, self.after])
        state = r.operate(self.root, self.p, t, 'install')
        self.assertTrue(state['complete'])
        self.assertTrue(state['commit_acknowledged'])
        self.assertEqual(t.installs, [self.p.install])
        self.assertEqual(len(list(self.root.glob('unused-removal-*.sql.review-only'))), 1)
        self.assertFalse(state['retry_allowed'])

    def test_preflight_is_readonly_and_never_creates_install_marker_or_undo(self):
        t = TransportFixture(self.root, [self.p.before])
        state = r.operate(self.root, self.p, t, 'preflight')
        self.assertEqual(state['phase'], 'preflight_before_verified_no_install')
        self.assertFalse(state['deployment_performed'])
        self.assertEqual(t.installs, [])
        self.assertFalse((self.root / r.MARKER).exists())
        self.assertEqual(list(self.root.glob('unused-removal-*')), [])

    def test_stale_before_refuses_without_marker_or_delivery(self):
        t = TransportFixture(self.root, [{'schema': 1, 'original': 'changed'}])
        with self.assertRaisesRegex(ValueError, 'stale'):
            r.operate(self.root, self.p, t, 'install')
        self.assertEqual(t.installs, [])
        self.assertFalse((self.root / r.MARKER).exists())

    def test_unknown_commit_is_recovered_without_resend(self):
        t = TransportFixture(self.root, [self.p.before, self.after, self.after], install_error=True)
        state = r.operate(self.root, self.p, t, 'install')
        self.assertTrue(state['complete'])
        self.assertFalse(state['commit_acknowledged'])
        with self.assertRaisesRegex(ValueError, 'recovery_only'):
            r.operate(self.root, self.p, t, 'install')
        self.assertEqual(len(t.installs), 1)

    def test_unknown_no_change_cannot_retry(self):
        t = TransportFixture(self.root, [self.p.before, self.p.before], install_error=True)
        state = r.operate(self.root, self.p, t, 'install')
        self.assertEqual(state['phase'], 'not_installed_observed_no_resend')
        with self.assertRaises(ValueError):
            r.operate(self.root, self.p, t, 'install')
        self.assertEqual(len(t.installs), 1)

    def test_disconnect_readonly_recovery_later_never_delivers_install(self):
        first = TransportFixture(self.root, [self.p.before, RuntimeError('disconnect')], True)
        state = r.operate(self.root, self.p, first, 'install')
        self.assertFalse(state['complete'])
        later = TransportFixture(self.root, [self.after, self.after])
        state = r.operate(self.root, self.p, later, 'recover')
        self.assertTrue(state['complete'])
        self.assertEqual(later.installs, [])

    def test_used_or_drifted_after_produces_no_removal(self):
        used = dict(self.after, new='used')
        t = TransportFixture(self.root, [self.p.before, used, used])
        state = r.operate(self.root, self.p, t, 'install')
        self.assertFalse(state['complete'])
        self.assertEqual(list(self.root.glob('unused-removal-*')), [])

    def test_changing_after_between_queries_never_claims_verified(self):
        t = TransportFixture(self.root, [self.p.before, self.after, dict(self.after, new='used')])
        self.assertFalse(r.operate(self.root, self.p, t, 'install')['complete'])

    def test_marker_before_sql_and_private_permissions(self):
        t = TransportFixture(self.root, [self.p.before, self.p.before])
        r.operate(self.root, self.p, t, 'install')
        for f in self.root.iterdir():
            self.assertEqual(f.stat().st_mode & 0o077, 0)

    def test_symlink_marker_rejected_before_read_or_write(self):
        (self.root / r.MARKER).symlink_to(self.root / 'missing')
        t = TransportFixture(self.root, [])
        with self.assertRaises(ValueError):
            r.operate(self.root, self.p, t, 'install')
        self.assertEqual(t.reads, [])

    def test_existing_after_evidence_tamper_blocks_recovery_claim(self):
        first = TransportFixture(self.root, [self.p.before, self.after, self.after])
        self.assertTrue(r.operate(self.root, self.p, first, 'install')['complete'])
        output = next(self.root.glob('after-*.private.json'))
        output.write_bytes(b'tampered')
        later = TransportFixture(self.root, [self.after, self.after])
        self.assertFalse(r.operate(self.root, self.p, later, 'recover')['complete'])
        self.assertEqual(later.installs, [])

    def test_existing_removal_tamper_blocks_recovery_claim(self):
        first = TransportFixture(self.root, [self.p.before, self.after, self.after])
        self.assertTrue(r.operate(self.root, self.p, first, 'install')['complete'])
        output = next(self.root.glob('unused-removal-*.sql.review-only'))
        output.write_bytes(b'tampered')
        later = TransportFixture(self.root, [self.after, self.after])
        self.assertFalse(r.operate(self.root, self.p, later, 'recover')['complete'])


class CommandBoundaryTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.binding = {}
        for key in ('psql', 'cli', 'certificate'):
            p = self.root / key
            p.write_bytes(('fixture-' + key).encode())
            self.binding[key] = {'path': str(p), 'sha256': r.sha(p.read_bytes())}
        self.config = {'PGHOST': 'fixture.invalid', 'PGPORT': '5432',
            'PGUSER': 'cli_login_fixture', 'PGDATABASE': 'postgres'}

    def tearDown(self):
        self.temp.cleanup()

    def test_exact_command_tls_clean_environment_and_no_shell(self):
        t = r.PsqlTransport(self.binding, self.config, 'never-output-fixture-secret')
        with patch.object(r.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0, b'{"schema":1}', b'')) as call:
            self.assertEqual(t.read(b'readonly fixture'), {'schema': 1})
        args, kw = call.call_args
        self.assertEqual(args[0][1:6], ['-X', '-w', '-q', '-A', '-t'])
        self.assertNotIn('shell', kw)
        self.assertNotIn('PGPASSWORD', kw['env'])
        self.assertEqual(kw['env']['PGSSLMODE'], 'verify-full')
        self.assertIn('default_transaction_read_only=on', kw['env']['PGOPTIONS'])
        self.assertNotIn('SUPABASE_ACCESS_TOKEN', kw['env'])

    def test_source_changed_or_second_delivery_refused(self):
        t = r.PsqlTransport(self.binding, self.config, 'fixture')
        with patch.object(r.subprocess, 'run') as call:
            with self.assertRaises(ValueError):
                t.install_once(b'not the reviewed SQL')
            call.assert_not_called()
        with patch.object(r, 'INSTALL_SHA', r.sha(b'fixture SQL')):
            with patch.object(r.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0, b'', b'')) as call:
                t.install_once(b'fixture SQL')
                with self.assertRaises(ValueError):
                    t.install_once(b'fixture SQL')
                self.assertEqual(call.call_count, 1)

    def test_runtime_change_refused_and_secret_error_suppressed(self):
        t = r.PsqlTransport(self.binding, self.config, 'fixture-secret')
        Path(self.binding['certificate']['path']).write_bytes(b'changed')
        with patch.object(r.subprocess, 'run') as call:
            with self.assertRaises(ValueError):
                t.read(b'fixture')
            call.assert_not_called()
        self.binding['certificate']['sha256'] = r.sha(b'changed')
        with patch.object(r.subprocess, 'run', return_value=subprocess.CompletedProcess([], 1, b'', b'fixture-secret')):
            with self.assertRaisesRegex(RuntimeError, '^transport_result_unknown$'):
                t.read(b'fixture')

    def test_maintenance_identity_fails_closed_for_wrong_role_or_actor(self):
        identity = {'read_only': 'on', 'current_user': 'postgres', 'session_user': 'cli_login_fixture',
            'database': 'postgres', 'server_version_num': '170011', 'auth_uid': None,
            'jwt_claims': None, 'jwt_sub': None, 'jwt_role': None}
        r.verify_identity(self.config, identity)
        for change in ({'current_user': 'cli_login_fixture'}, {'auth_uid': 'fixture-actor'},
                {'read_only': 'off'}, {'database': 'other'}, {'session_user': 'other'}, {'server_version_num': '160000'}):
            with self.assertRaises(ValueError):
                r.verify_identity(self.config, dict(identity, **change))


if __name__ == '__main__':
    unittest.main()
