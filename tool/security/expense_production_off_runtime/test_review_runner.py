import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from review_runner import (FILES, MARKER, Refused, install_review_once,
    operation_lock, recover_review_readonly, sha)

RUNTIME = Path(__file__).parent.absolute()
REPO = RUNTIME.parents[2]


class FakeTransport:
    def __init__(self, test, observation, *, crash=None, read_failure=False):
        self.test = test
        self.observation = observation
        self.crash = crash
        self.read_failure = read_failure
        self.install_calls = 0
        self.read_calls = 0

    def execute_install_once(self, sql):
        self.install_calls += 1
        marker = json.loads((self.test.root / MARKER).read_text())
        self.test.assertEqual(marker['phase'], 'install_submission_pending')
        self.test.assertFalse(marker['retry_allowed'])
        self.test.assertEqual(sha(sql), marker['artifacts'][FILES[1]])
        self.test.assertEqual(sql.count(b'\nCOMMIT;'), 1)
        if self.crash:
            raise self.crash('simulated_sensitive_error_never_logged')

    def capture_readonly(self, sql):
        self.read_calls += 1
        self.test.assertTrue(sql.startswith(b'BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;'))
        self.test.assertIn(b'SET LOCAL ROLE postgres;', sql)
        if self.read_failure:
            raise ConnectionError('simulated_sensitive_error_never_logged')
        return self.observation


class ReviewRunnerTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.node = shutil.which('node')
        module = os.environ.get('SKO_EXPENSE_PGLITE_MODULE')
        if not cls.node or not module:
            raise RuntimeError('node and SKO_EXPENSE_PGLITE_MODULE are required; tests must not silently skip')
        cls.fixture_temp = tempfile.TemporaryDirectory(prefix='sko-expense-off-synthetic-')
        cls.fixture = Path(cls.fixture_temp.name)
        result = subprocess.run([cls.node, str(RUNTIME / 'create_test_evidence.mjs'), module, str(cls.fixture)],
            cwd=REPO, env={'PATH': os.environ.get('PATH', '')},
            capture_output=True, text=True, timeout=60)
        if result.returncode:
            raise RuntimeError('synthetic_pglite_fixture_failed')
        cls.pg_result = result.stdout.strip()

    @classmethod
    def tearDownClass(cls):
        cls.fixture_temp.cleanup()

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='sko-expense-off-test-')
        self.base = Path(self.temp.name)
        self.source = self.base / 'source'
        shutil.copytree(self.fixture, self.source)
        self.root = self.base / 'private'
        self.root.mkdir(mode=0o700)
        self.after = (self.source / 'synthetic-after-observation.json').read_bytes()
        self.before = (self.source / 'synthetic-before-observation.json').read_bytes()

    def tearDown(self):
        self.temp.cleanup()

    def run_install(self, transport):
        return install_review_once(self.source, self.root, transport, self.node)

    def test_acknowledged_commit_prepares_actual_oid_undo_once(self):
        transport = FakeTransport(self, self.after)
        state = self.run_install(transport)
        self.assertTrue(state['commit_acknowledged'])
        self.assertEqual(state['phase'], 'installed_off_unused_undo_candidate')
        undo = Path(state['unused_undo'])
        self.assertEqual(sha(undo.read_bytes()), state['unused_undo_sha256'])
        actual = json.loads(self.after)
        guard = undo.read_text()
        embedded_after = json.loads(guard.split('$expected_expense_after$')[1])
        self.assertTrue(embedded_after == actual['after'], 'undo must embed the exact observed metadata and OIDs')
        self.assertEqual((transport.install_calls, transport.read_calls), (1, 1))
        with self.assertRaisesRegex(Refused, 'previous_attempt'):
            self.run_install(transport)
        alternate = self.base / 'alternate-prepared'
        shutil.copytree(self.source, alternate)
        with self.assertRaisesRegex(Refused, 'previous_attempt'):
            install_review_once(alternate, self.root, transport, self.node)
        self.assertEqual(transport.install_calls, 1)

    def test_commit_disconnect_after_commit_is_observed_not_resubmitted(self):
        transport = FakeTransport(self, self.after, crash=ConnectionError)
        state = self.run_install(transport)
        self.assertFalse(state['commit_acknowledged'])
        self.assertEqual(state['phase'], 'installed_off_unused_undo_candidate')
        self.assertEqual(transport.install_calls, 1)
        self.assertFalse(state['retry_allowed'])
        self.assertNotIn('simulated_sensitive', (self.root / MARKER).read_text())

    def test_disconnect_before_commit_still_never_rearms(self):
        transport = FakeTransport(self, self.before, crash=ConnectionError)
        state = self.run_install(transport)
        self.assertEqual(state['phase'], 'before_state_observed')
        self.assertFalse(state['retry_allowed'])
        self.assertNotIn('unused_undo', state)
        with self.assertRaisesRegex(Refused, 'previous_attempt'):
            self.run_install(transport)
        self.assertEqual(transport.install_calls, 1)

    def test_read_failure_remains_unknown_then_readonly_recovery(self):
        transport = FakeTransport(self, self.after, crash=ConnectionError, read_failure=True)
        state = self.run_install(transport)
        self.assertEqual(state['phase'], 'state_requires_review')
        transport.read_failure = False
        recovered = recover_review_readonly(self.root, transport, self.node)
        self.assertEqual(recovered['phase'], 'installed_off_unused_undo_candidate')
        self.assertEqual((transport.install_calls, transport.read_calls), (1, 2))

    def test_process_exit_after_fsynced_marker_requires_readonly_recovery(self):
        transport = FakeTransport(self, self.after, crash=SystemExit)
        with self.assertRaises(SystemExit):
            self.run_install(transport)
        self.assertEqual(json.loads((self.root / MARKER).read_text())['phase'], 'install_submission_pending')
        with self.assertRaisesRegex(Refused, 'previous_attempt'):
            self.run_install(transport)
        recovered = recover_review_readonly(self.root, transport, self.node)
        self.assertEqual(recovered['phase'], 'installed_off_unused_undo_candidate')
        self.assertEqual(transport.install_calls, 1)

    def test_status_hash_tamper_stops_before_marker_and_transport(self):
        (self.source / FILES[1]).write_bytes(b'changed')
        transport = FakeTransport(self, self.after)
        with self.assertRaisesRegex(Refused, 'prepared_hash'):
            self.run_install(transport)
        self.assertFalse((self.root / MARKER).exists())
        self.assertEqual(transport.install_calls, 0)

    def test_forged_hash_cannot_replace_immutable_generated_sql(self):
        file = self.source / FILES[1]
        file.write_bytes(file.read_bytes() + b'\nSELECT 1;')
        status_file = self.source / 'prepare-status.json'
        status = json.loads(status_file.read_text())
        status['artifacts'][FILES[1]] = {'sha256': sha(file.read_bytes()), 'bytes': file.stat().st_size}
        status_file.write_text(json.dumps(status))
        with self.assertRaisesRegex(Refused, 'offline_generator'):
            self.run_install(FakeTransport(self, self.after))
        self.assertFalse((self.root / MARKER).exists())

    def test_symlink_and_public_file_refused(self):
        file = self.source / FILES[1]
        original = self.source / 'original.sql'
        file.rename(original)
        file.symlink_to(original)
        with self.assertRaises(OSError):
            self.run_install(FakeTransport(self, self.after))
        file.unlink()
        original.rename(file)
        file.chmod(0o644)
        with self.assertRaisesRegex(Refused, 'private_file'):
            self.run_install(FakeTransport(self, self.after))
        self.assertFalse((self.root / MARKER).exists())

    def test_unknown_actual_or_used_financial_state_never_generates_undo(self):
        actual = json.loads(self.after)
        actual['v2_or_basis_count'] = 1
        state = self.run_install(FakeTransport(self, json.dumps(actual).encode()))
        self.assertEqual(state['phase'], 'state_requires_review')
        self.assertNotIn('unused_undo', state)
        self.assertFalse(state['retry_allowed'])

    def test_drifted_actual_evidence_always_stays_review_only(self):
        changes = [
            lambda a: a.update(business='0' * 32),
            lambda a: a.update(read_only='off'),
            lambda a: a.update(rollout_installed=True),
            lambda a: a['after']['functions'][0].update(source_md5='0' * 32),
            lambda a: a['after']['functions'][0].update(owner='unexpected'),
            lambda a: next(f for f in a['after']['functions']
                if f['signature']=='private.expense_cost_finalize()').update(oid='9999999'),
        ]
        for number, change in enumerate(changes):
            with self.subTest(case=number):
                self.root = self.base / ('private-drift-' + str(number))
                self.root.mkdir(mode=0o700)
                actual = json.loads(self.after)
                change(actual)
                transport = FakeTransport(self, json.dumps(actual).encode())
                state = self.run_install(transport)
                self.assertEqual(state['phase'], 'state_requires_review')
                self.assertFalse(state['retry_allowed'])
                self.assertNotIn('unused_undo', state)
                self.assertEqual(transport.install_calls, 1)

    def test_concurrent_attempt_is_refused_before_submission(self):
        transport = FakeTransport(self, self.after)
        with operation_lock(self.root):
            with self.assertRaisesRegex(Refused, 'operation_in_progress'):
                self.run_install(transport)
        self.assertEqual(transport.install_calls, 0)
        self.assertFalse((self.root / MARKER).exists())

    def test_recovery_artifact_change_is_refused_without_install(self):
        transport = FakeTransport(self, self.after)
        state = self.run_install(transport)
        attempt = Path(state['stage']) / FILES[1]
        attempt.write_bytes(b'changed')
        with self.assertRaisesRegex(Refused, 'attempt_artifact'):
            recover_review_readonly(self.root, transport, self.node)
        self.assertEqual(transport.install_calls, 1)

    def test_cli_is_non_executable_and_never_requests_credentials(self):
        result = subprocess.run(['python', str(RUNTIME / 'review_runner.py')], capture_output=True, text=True)
        self.assertEqual(result.returncode, 2)
        self.assertIn('実行不可', result.stdout)


if __name__ == '__main__':
    unittest.main()
