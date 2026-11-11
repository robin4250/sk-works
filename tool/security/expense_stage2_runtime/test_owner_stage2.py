import contextlib
import hashlib
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import owner_stage2 as operator


class SubmissionBoundaryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.home = Path(self.temp.name)
        self.root = self.home / 'SKO-source-backups' / ('expense-default-off-production-' + operator.PROJECT)
        self.stage = self.root / 'expense-stage2-prepare-fixture'
        self.stage.mkdir(parents=True)
        self.package = self.root / 'package'
        (self.package / 'source').mkdir(parents=True)
        (self.package / 'source' / 'converter.sql.review-only').write_text('converter')
        (self.package / 'source' / 'negotiation.sql.review-only').write_text('negotiation')
        self.sql = b'BEGIN; fixture_only; COMMIT;'
        (self.stage / 'install.sql.review-only').write_bytes(self.sql)
        (self.stage / 'before.private.json').write_text('{}')
        self.hash = hashlib.sha256(self.sql).hexdigest()
        self.phase = 'installed_off_unused_undo_candidate'
        self.fail_submission = False
        self.calls = []
        def write_once(path, raw):
            with path.open('xb') as stream:
                stream.write(raw)
        owner = SimpleNamespace(_read=lambda p:p.read_bytes(), _write_once=write_once, _private_directory=lambda p:None)
        def execute(sql):
            self.calls.append(('submit', sql))
            if self.fail_submission:
                raise ConnectionError('unknown')
        transport = SimpleNamespace(execute_install_once=execute, capture_readonly=lambda q:b'{}')
        module = SimpleNamespace(_approved_binding=lambda:{}, _operator_transport=lambda b:self.obtain(transport))
        runner = SimpleNamespace(FILES=('before','install','read'), operation_lock=lambda r:contextlib.nullcontext(),
                                 atomic_state=lambda p,v:p.write_text(json.dumps(v)))
        modules = {'owner_install_bound_default_off':owner,'cli_psql_transport':module,'review_runner':runner}
        self.stack = contextlib.ExitStack()
        self.stack.enter_context(patch.object(operator.Path,'home',return_value=self.home))
        self.stack.enter_context(patch.object(operator.importlib,'import_module',side_effect=lambda n:modules[n]))

    def obtain(self, transport):
        self.calls.append(('connect',None))
        return transport

    def offline(self,pkg,stage,mode,data=None):
        if mode=='install':return json.dumps({'sql':self.sql.decode()})
        if mode=='capture-sql':return json.dumps({'sql':'BEGIN READ ONLY; SELECT fixture; COMMIT;'})
        if mode=='classify':return json.dumps({'state':self.phase})
        if mode=='undo':return json.dumps({'sql':'review_only_unused_undo'})
        raise AssertionError(mode)

    def run_install(self):
        return operator.install_prepared(self.root,self.package,self.stage,self.offline,self.hash)

    def tearDown(self):
        self.stack.close()
        self.temp.cleanup()

    def test_changed_sql_stops_before_connection(self):
        (self.stage/'install.sql.review-only').write_bytes(b'changed')
        with self.assertRaisesRegex(RuntimeError,'approved_stage2_sql_changed'):self.run_install()
        self.assertEqual(self.calls,[])

    def test_plan_mismatch_stops_before_connection(self):
        self.sql=b'changed generated plan'
        with self.assertRaisesRegex(RuntimeError,'stage2_plan_not_reproducible'):self.run_install()
        self.assertEqual(self.calls,[])

    def test_previous_marker_stops_before_connection(self):
        (self.root/'expense-stage2-install-attempt.json').write_text('unknown')
        with self.assertRaisesRegex(RuntimeError,'previous_stage2_attempt'):self.run_install()
        self.assertEqual(self.calls,[])

    def test_success_does_not_convert_or_run_undo(self):
        result=self.run_install()
        self.assertTrue(result['deployment_performed'])
        self.assertFalse(result['conversion_performed'])
        self.assertFalse(result['complete'])
        self.assertEqual([x[0] for x in self.calls],['connect','submit'])
        self.assertTrue((self.stage/'unused-undo.sql.review-only').exists())

    def test_unknown_before_state_never_authorizes_retry(self):
        self.fail_submission=True
        self.phase='before_state_observed'
        result=self.run_install()
        self.assertIsNone(result['deployment_performed'])
        self.assertFalse(result['retry_allowed'])
        with self.assertRaisesRegex(RuntimeError,'previous_stage2_attempt'):self.run_install()
        self.assertEqual([x[0] for x in self.calls],['connect','submit'])

    def test_failed_classification_does_not_generate_undo(self):
        self.phase='state_requires_review'
        result=self.run_install()
        self.assertIsNone(result['deployment_performed'])
        self.assertFalse((self.stage/'unused-undo.sql.review-only').exists())


if __name__=='__main__':unittest.main()
