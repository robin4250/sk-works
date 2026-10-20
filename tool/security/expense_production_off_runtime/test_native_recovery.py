"""CI-only native disconnect tests; no mock observations and no production adapter."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from review_runner import MARKER, Refused, install_review_once, recover_review_readonly

RUNTIME = Path(__file__).parent.absolute()
REPO = RUNTIME.parents[2]
FIXTURE_URL = 'postgresql://postgres:fixture-only-password@127.0.0.1:5432/sko_payroll_scope_fixture'


class NativeFixtureTransport:
    def __init__(self, node, env, mode):
        self.node, self.env, self.mode = node, env, mode
        self.install_calls = 0
        self.read_calls = 0

    def request(self, mode, sql):
        result = subprocess.run([self.node, str(RUNTIME / 'native_fixture_transport.mjs'), mode],
            input=sql, capture_output=True, env=self.env, cwd=REPO, timeout=60)
        if result.returncode:
            raise ConnectionError('native_fixture_transport_failed')
        return result.stdout

    def execute_install_once(self, sql):
        self.install_calls += 1
        self.request(self.mode, sql)

    def capture_readonly(self, sql):
        self.read_calls += 1
        return self.request('read-only', sql)


class NativeRecoveryTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # The JS guard independently refuses unknown endpoints before importing pg/connecting.
        if os.environ.get('SKO_PAYROLL_SCOPE_FIXTURE_URL') != FIXTURE_URL:
            raise RuntimeError('exact_disposable_ci_fixture_required')
        cls.node = shutil.which('node')
        if not cls.node:
            raise RuntimeError('node_required')
        cls.env = {'PATH': os.environ.get('PATH', ''), 'SKO_PAYROLL_SCOPE_FIXTURE_URL': FIXTURE_URL}
        cls.fixture_temp = tempfile.TemporaryDirectory(prefix='sko-expense-native-evidence-')
        cls.fixture = Path(cls.fixture_temp.name)
        pg_driver = REPO / 'tool/security/fixture_dependencies/node_modules/pg/lib/index.js'
        adapter = (REPO / 'tool/payroll_scope_native_pg17_runtime.mjs').as_uri()
        result = subprocess.run([cls.node, str(RUNTIME / 'create_test_evidence.mjs'), adapter,
            str(cls.fixture), str(pg_driver)], cwd=REPO, env=cls.env, capture_output=True, timeout=60)
        if result.returncode:
            raise RuntimeError('native_original_plan_fixture_failed')

    @classmethod
    def tearDownClass(cls):
        cls.fixture_temp.cleanup()

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='sko-expense-native-case-')
        self.base = Path(self.temp.name)
        self.source = self.base / 'source'
        shutil.copytree(self.fixture, self.source)
        self.root = self.base / 'private'
        self.root.mkdir(mode=0o700)
        self.transport = None

    def tearDown(self):
        # Isolated fixture only: use exactly the generated actual-OID unused undo.
        marker = self.root / MARKER
        if marker.exists() and self.transport:
            state = json.loads(marker.read_text())
            if state.get('unused_undo'):
                self.transport.request('restore-fixture', Path(state['unused_undo']).read_bytes())
                observation = self.transport.capture_readonly((self.source / 'private-read-actual-after.sql.read-only').read_bytes())
                actual, before = json.loads(observation), json.loads((self.source / 'private-fresh-before.json').read_text())
                self.assertTrue(actual['after'] == before['before'], 'native unused undo must restore original catalog')
                self.assertEqual(actual['business'], before['business'])
        self.temp.cleanup()

    def run_case(self, mode):
        self.transport = NativeFixtureTransport(self.node, self.env, mode)
        return install_review_once(self.source, self.root, self.transport, self.node)

    def assert_never_resubmits(self):
        with self.assertRaisesRegex(Refused, 'previous_attempt'):
            install_review_once(self.source, self.root, self.transport, self.node)
        self.assertEqual(self.transport.install_calls, 1)

    def test_real_disconnect_before_commit_observes_rollback_without_retry(self):
        state = self.run_case('disconnect-before')
        self.assertFalse(state['commit_acknowledged'])
        self.assertEqual(state['phase'], 'before_state_observed')
        self.assert_never_resubmits()
        recovered = recover_review_readonly(self.root, self.transport, self.node)
        self.assertEqual(recovered['phase'], 'before_state_observed')
        self.assertEqual(self.transport.install_calls, 1)

    def test_real_disconnect_after_commit_observes_installed_state_without_retry(self):
        state = self.run_case('disconnect-after')
        self.assertFalse(state['commit_acknowledged'])
        self.assertEqual(state['phase'], 'installed_off_unused_undo_candidate')
        self.assert_never_resubmits()
        recovered = recover_review_readonly(self.root, self.transport, self.node)
        self.assertEqual(recovered['phase'], 'installed_off_unused_undo_candidate')
        self.assertEqual(self.transport.install_calls, 1)

    def test_acknowledged_native_commit_and_fresh_readonly_actual(self):
        state = self.run_case('install-ack')
        self.assertTrue(state['commit_acknowledged'])
        self.assertEqual(state['phase'], 'installed_off_unused_undo_candidate')
        self.assert_never_resubmits()


if __name__ == '__main__':
    unittest.main()
