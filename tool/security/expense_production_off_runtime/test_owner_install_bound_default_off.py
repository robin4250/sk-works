import contextlib
import hashlib
import io
import json
import os
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import owner_install_bound_default_off as owner


class OwnerBoundaryTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.home = Path(self.temp.name)
        self.parent = self.home / 'SKO-source-backups'
        self.parent.mkdir(mode=0o700)
        self.root = self.parent / ('expense-default-off-production-' + owner.PROJECT)
        self.root.mkdir(mode=0o700)
        self.runtime = self.root / 'runtime'
        self.runtime.mkdir(mode=0o700)
        self.source = self.parent / 'original'
        self.source.mkdir(mode=0o700)
        self.originals = {name: ('fixture:' + name).encode() for name in owner.ARTIFACTS}
        self.pins = {name: hashlib.sha256(raw).hexdigest() for name, raw in self.originals.items()}
        for name, raw in self.originals.items():
            self.write(self.source / name, raw)
        raw = json.dumps({'project': owner.PROJECT, 'artifacts': self.pins}).encode()
        self.write(self.root / 'production-approval.json', raw)
        self.approval_sha = hashlib.sha256(raw).hexdigest()
        self.stack = contextlib.ExitStack()
        self.stack.enter_context(patch.object(owner, 'ARTIFACTS', self.pins))
        self.stack.enter_context(patch.object(owner.sys, 'platform', 'darwin'))
        self.stack.enter_context(patch.object(owner.sys, 'flags', SimpleNamespace(isolated=1)))
        self.stack.enter_context(patch.object(owner.Path, 'home', return_value=self.home))
        self.state = {'phase': 'installed_off_unused_undo_candidate', 'commit_acknowledged': True, 'unused_undo_sha256': 'fixture'}
        self.calls = []
        binding = SimpleNamespace(APPROVED_DURABLE_ROOT=self.root, APPROVED_MANIFEST_SHA256=self.approval_sha)
        def install():
            self.calls.append('install')
            return self.state.copy()
        transport = SimpleNamespace(install_cli_approved_once=install)
        self.modules = {'production_transport_binding': binding, 'cli_psql_transport': transport}
        self.importer = self.stack.enter_context(patch.object(owner.importlib, 'import_module', side_effect=lambda name: self.modules[name]))
        self.original_path = owner.sys.path.copy()
        self.old_umask = os.umask(0o077)

    def tearDown(self):
        owner.sys.path[:] = self.original_path
        os.umask(self.old_umask)
        self.stack.close()
        self.temp.cleanup()

    @staticmethod
    def write(path, raw):
        path.write_bytes(raw)
        path.chmod(0o600)

    def run_entry(self):
        return owner.stage_and_install(self.source, self.root, self.runtime, self.approval_sha)

    def test_all_originals_checked_before_staging_or_transport(self):
        name = list(self.originals)[-1]
        self.write(self.source / name, b'changed')
        with self.assertRaisesRegex(owner.OwnerRefused, 'original_prepared_artifact_changed'):
            self.run_entry()
        self.assertFalse((self.root / 'prepared').exists())
        self.assertEqual(self.calls, [])
        self.importer.assert_not_called()

    def test_permanent_attempt_stops_before_cli_or_original_reads(self):
        self.write(self.root / owner.MARKER, b'prior outcome unknown')
        with patch.object(owner, '_read', side_effect=AssertionError('must stop first')):
            with self.assertRaisesRegex(owner.OwnerRefused, 'previous_attempt_requires_readonly_recovery'):
                self.run_entry()
        self.assertEqual((self.root / owner.MARKER).read_bytes(), b'prior outcome unknown')
        self.assertEqual(self.calls, [])

    def test_existing_prepared_artifact_is_never_overwritten(self):
        prepared = self.root / 'prepared'
        prepared.mkdir(mode=0o700)
        name = next(iter(self.originals))
        self.write(prepared / name, b'historical private file')
        with self.assertRaisesRegex(owner.OwnerRefused, 'existing_artifact_differs'):
            self.run_entry()
        self.assertEqual((prepared / name).read_bytes(), b'historical private file')
        self.assertEqual((self.source / name).read_bytes(), self.originals[name])
        self.assertEqual(self.calls, [])

    def test_verified_install_preserves_originals_and_reports_no_conversion(self):
        result = self.run_entry()
        self.assertIs(result['deployment_performed'], True)
        self.assertIs(result['conversion_performed'], False)
        self.assertIs(result['complete'], False)
        self.assertEqual(self.calls, ['install'])
        for name, raw in self.originals.items():
            self.assertEqual((self.source / name).read_bytes(), raw)
            self.assertEqual((self.root / 'prepared' / name).read_bytes(), raw)

    def test_before_observation_does_not_assert_no_late_commit_or_allow_retry(self):
        self.state = {'phase': 'before_state_observed', 'commit_acknowledged': False}
        result = self.run_entry()
        self.assertIsNone(result['deployment_performed'])
        self.assertTrue(result['observed_before'])
        self.assertFalse(result['retry_allowed'])

    def test_unknown_outcome_remains_unknown(self):
        self.state = {'phase': 'state_requires_review', 'commit_acknowledged': False}
        result = self.run_entry()
        self.assertIsNone(result['deployment_performed'])
        self.assertFalse(result['observed_before'])
        self.assertFalse(result['retry_allowed'])

    def test_raw_errors_never_enter_receipt_clipboard_or_stdout(self):
        out = io.StringIO()
        with patch.object(owner, 'stage_and_install', side_effect=ConnectionError('PASSWORD=private-fixture-secret')):
            with patch.object(owner.subprocess, 'run') as clipboard, contextlib.redirect_stdout(out):
                self.assertEqual(owner.run_owner(self.source, self.root, self.runtime, self.approval_sha), 1)
        self.assertNotIn('private-fixture-secret', out.getvalue())
        self.assertNotIn('private-fixture-secret', clipboard.call_args.kwargs['input'])
        receipts = list(self.root.glob('operator-result-*.json'))
        self.assertEqual(len(receipts), 1)
        self.assertNotIn('private-fixture-secret', receipts[0].read_text())
        self.assertIsNone(json.loads(receipts[0].read_text())['deployment_performed'])


if __name__ == '__main__':
    unittest.main()
