"""New orchestration boundaries only. No database, credentials or Docker calls."""
import contextlib
import importlib.util
import json
import os
from pathlib import Path
import sys
import tempfile
import types
import unittest
from unittest.mock import patch
import owner_stage3 as m

# Reuse the already reviewed real filesystem lock/marker primitives, without DB use.
RUNTIME=Path('/workspace/scratch/0002bbd92cf7/sko-expense-operator/runtime-994342')
spec=importlib.util.spec_from_file_location('review_runner',RUNTIME/'review_runner.py')
runner=importlib.util.module_from_spec(spec);spec.loader.exec_module(runner)
sys.modules['review_runner']=runner

class Owner:
    @staticmethod
    def _write_once(path,raw):
        runner.write_new(path,raw)

class Transport:
    def __init__(self,test,*,unknown=False,read_fail=False,crash=False,bad_identity=False):
        self.test=test;self.config={'PGUSER':'cli_login_fixture.'+m.PROJECT};self.artifacts={};self.reads=0;self.submits=0
        self.unknown=unknown;self.read_fail=read_fail;self.crash=crash;self.bad_identity=bad_identity;self.failed_backend=False
    def capture_readonly(self,sql):
        self.test.assertEqual(m.digest(sql),self.artifacts[runner.FILES[2]])
        self.reads+=1
        if self.reads==1:
            identity={'session_user':'cli_login_fixture','current_user':'postgres','auth_uid':None,'jwt_claims':None,'jwt_sub':None,'jwt_role':None,'failed_backend_present':self.failed_backend}
            if self.bad_identity:identity['auth_uid']='synthetic-uid-must-not-be-used'
            return json.dumps({'read_only':'on','identity':identity}).encode()
        if self.reads==3 and self.read_fail:raise ConnectionError('synthetic-private-error')
        return json.dumps({'read_only':'on','kind':'before' if self.reads==2 else 'after','original_payment_jsonb_text':'{\"numeric\":1.50}'}).encode()
    def execute_install_once(self,sql):
        self.test.assertEqual(m.digest(sql),self.artifacts[runner.FILES[1]])
        state=json.loads((self.test.root/m.MARKER).read_bytes())
        self.test.assertEqual(state['phase'],'submission_pending');self.test.assertFalse(state['retry_allowed'])
        self.submits+=1
        if self.crash:raise SystemExit('synthetic-exit')
        if self.unknown:raise ConnectionError('synthetic-private-error')

class OwnerStage3Test(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.root=Path(self.temp.name);self.root.chmod(0o700)
        self.package=self.root/'package';self.package.mkdir(mode=0o700)
        path=self.package/'maintenance.sql.review-only';path.write_bytes(b'synthetic fixed source');path.chmod(0o600)
        self.pins={path.name:m.digest(path.read_bytes())};self.binding={'authorization_reference':'a'*64}
        prior=self.root/m.PRIOR_MARKER;prior.write_bytes(b'previous immutable marker');prior.chmod(0o600)
        self.prior={'marker_sha256':m.digest(prior.read_bytes()),'install_sha256':'b'*64}
        self.classification=m.SUCCESS;self.unstable=False;self.install_generations=0
    def tearDown(self):self.temp.cleanup()
    def offline(self,package,stage,mode,data):
        if mode=='capture-sql':return b'{"sql":"synthetic fixed read-only query"}'
        if mode=='install':
            self.assertEqual(data['before']['original_payment_jsonb_text'],'{\"numeric\":1.50}')
            self.install_generations+=1
            sql='synthetic fixed install '+str(self.install_generations) if self.unstable else 'synthetic fixed install'
            return json.dumps({'sql':sql}).encode()
        if mode=='classify':return json.dumps({'state':self.classification,'retry_allowed':False}).encode()
        raise AssertionError('unexpected plan mode')
    def execute(self,transport):return m.execute_bound(self.root,self.package,self.binding,transport,self.offline,Owner,runner,self.pins,self.prior)
    def test_source_change_refused_before_marker_or_submission(self):
        (self.package/'maintenance.sql.review-only').write_bytes(b'changed source')
        t=Transport(self)
        with self.assertRaisesRegex(RuntimeError,'source_pin_differs'):self.execute(t)
        self.assertFalse((self.root/m.MARKER).exists());self.assertEqual(t.submits,0)
    def test_identity_or_exact_login_mismatch_refused_before_plan(self):
        for t in (Transport(self,bad_identity=True),Transport(self)):
            if not t.bad_identity:t.config['PGUSER']='cli_login_another'
            with self.assertRaisesRegex(RuntimeError,'identity_refused|login_binding_differs'):self.execute(t)
            self.assertEqual(t.submits,0)
        self.assertEqual(self.install_generations,0);self.assertFalse((self.root/m.MARKER).exists())
    def test_generated_sql_cas_refused_before_marker_or_submission(self):
        self.unstable=True;t=Transport(self)
        with self.assertRaisesRegex(RuntimeError,'not_reproducible'):self.execute(t)
        self.assertEqual(t.submits,0);self.assertFalse((self.root/m.MARKER).exists())
    def test_commit_unknown_can_be_verified_only_by_fresh_read_and_never_resent(self):
        t=Transport(self,unknown=True);state=self.execute(t)
        self.assertEqual(state['phase'],m.SUCCESS);self.assertFalse(state['commit_acknowledged']);self.assertTrue(state['conversion_verified'])
        self.assertEqual((t.submits,t.reads),(1,3))
        with self.assertRaisesRegex(RuntimeError,'previous_stage3'):self.execute(t)
        self.assertEqual((t.submits,t.reads),(1,3))
        self.assertNotIn('synthetic-private-error',(self.root/m.MARKER).read_text())
    def test_before_state_after_unknown_keeps_marker_and_blocks_resend(self):
        self.classification='before_state_observed';t=Transport(self,unknown=True);state=self.execute(t)
        self.assertFalse(state['conversion_verified']);self.assertFalse(state['retry_allowed'])
        with self.assertRaisesRegex(RuntimeError,'previous_stage3'):self.execute(t)
        self.assertEqual(t.submits,1)
    def test_read_failure_after_ack_is_review_required_without_undo_or_resend(self):
        t=Transport(self,read_fail=True);state=self.execute(t)
        self.assertTrue(state['commit_acknowledged']);self.assertEqual(state['phase'],'state_requires_review')
        marker=json.loads((self.root/m.MARKER).read_bytes());self.assertNotIn('unused_undo',marker)
        with self.assertRaisesRegex(RuntimeError,'previous_stage3'):self.execute(t)
        self.assertEqual(t.submits,1)
    def test_process_exit_leaves_durable_pending_marker_and_refuses_resend(self):
        t=Transport(self,crash=True)
        with self.assertRaises(SystemExit):self.execute(t)
        self.assertEqual(json.loads((self.root/m.MARKER).read_bytes())['phase'],'submission_pending')
        with self.assertRaisesRegex(RuntimeError,'previous_stage3'):self.execute(t)
        self.assertEqual(t.submits,1)
    def test_concurrent_operator_refused_without_identity_or_submission(self):
        t=Transport(self)
        with runner.operation_lock(self.root):
            with self.assertRaisesRegex(runner.Refused,'operation_in_progress'):self.execute(t)
        self.assertEqual((t.reads,t.submits),(0,0));self.assertFalse((self.root/m.MARKER).exists())
    def test_generated_transport_binding_is_checked_as_bytes_before_import(self):
        runtime=self.root/'runtime';runtime.mkdir(mode=0o700)
        p=runtime/'production_transport_binding.py'
        expected=("from pathlib import Path\nAPPROVED_DURABLE_ROOT = Path("+repr(str(self.root))+")\nAPPROVED_MANIFEST_SHA256 = "+repr(m.STAGE1_APPROVAL)+"\n").encode()
        p.write_bytes(expected);p.chmod(0o600);m.verify_transport_binding(self.root,runtime)
        p.write_bytes(expected+b"raise RuntimeError('must never import')\n")
        with self.assertRaisesRegex(RuntimeError,'compiled_transport_binding_differs'):m.verify_transport_binding(self.root,runtime)
    def test_original_failed_backend_present_refuses_before_capture_or_submission(self):
        t=Transport(self);t.failed_backend=True
        with self.assertRaisesRegex(RuntimeError,'previous_backend_still_present'):self.execute(t)
        self.assertEqual((t.reads,t.submits),(1,0));self.assertFalse((self.root/m.MARKER).exists())
        self.assertIn(b'pg_stat_activity where pid=3584894',m.IDENTITY_SQL)
    def test_raw_jsonb_string_survives_capture_save_and_plan_inputs(self):
        t=Transport(self);self.execute(t)
        state=json.loads((self.root/m.MARKER).read_bytes())
        before=json.loads((Path(state['stage'])/'before.private.json').read_bytes())
        self.assertEqual(before['original_payment_jsonb_text'],'{"numeric":1.50}')
    def prior_fixture(self):
        package=self.root/'stage3-runtime';package.mkdir(mode=0o700)
        maintenance=package/'maintenance.sql.review-only';maintenance.write_bytes(b'old immutable source');maintenance.chmod(0o600)
        pins={maintenance.name:m.digest(maintenance.read_bytes())}
        stage=self.root/'expense-stage3-attempt-old';stage.mkdir(mode=0o700)
        before={'schema':3,'read_only':'on','business':'synthetic-original'}
        data={'before.private.json':json.dumps(before).encode(),'after.private.json':json.dumps(before).encode(),'install.sql.review-only':b'old reproduced SQL','binding.private.json':json.dumps({'authorization_reference':'a'*64}).encode(),'capture.sql.read-only':b'old fixed capture'}
        fields={'before.private.json':'before_sha256','after.private.json':'after_sha256','install.sql.review-only':'install_sha256','binding.private.json':'bound_binding_sha256','capture.sql.read-only':'read_sql_sha256'}
        marker={'schema':3,'project':m.PROJECT,'phase':'before_state_observed','commit_acknowledged':False,'retry_allowed':False,'authorization_reference':'a'*64,'stage':str(stage)}
        for name,raw in data.items():
            p=stage/name;p.write_bytes(raw);p.chmod(0o600);marker[fields[name]]=m.digest(raw)
        p=self.root/m.PRIOR_MARKER;p.write_text(json.dumps(marker));p.chmod(0o600)
        def offline(package,temp,mode,request):
            self.assertEqual(package.name,'stage3-runtime');self.assertNotEqual(temp,stage)
            if mode=='install':return b'{"sql":"old reproduced SQL"}'
            if mode=='classify':return b'{"state":"before_state_observed","retry_allowed":false}'
            raise AssertionError('unexpected old plan mode')
        return pins,stage,marker,data,offline
    def test_old_receipt_sources_hashes_and_sql_are_verified_without_modification(self):
        pins,stage,marker,data,offline=self.prior_fixture()
        oldmarker=(self.root/m.PRIOR_MARKER).read_bytes()
        with patch.object(m,'OLD_STAGE3_SOURCES',pins):proof=m.verify_previous(self.root,offline)
        self.assertEqual(proof['marker_sha256'],m.digest(oldmarker));self.assertEqual((self.root/m.PRIOR_MARKER).read_bytes(),oldmarker)
        for name,raw in data.items():self.assertEqual((stage/name).read_bytes(),raw)
    def test_old_receipt_ack_or_observation_drift_refused(self):
        pins,stage,marker,data,offline=self.prior_fixture()
        marker['commit_acknowledged']=True;(self.root/m.PRIOR_MARKER).write_text(json.dumps(marker))
        with patch.object(m,'OLD_STAGE3_SOURCES',pins),self.assertRaisesRegex(RuntimeError,'receipt_not_verified'):m.verify_previous(self.root,offline)
        marker['commit_acknowledged']=False
        changed=json.dumps({'schema':3,'read_only':'on','business':'drift'}).encode();(stage/'after.private.json').write_bytes(changed);marker['after_sha256']=m.digest(changed);(self.root/m.PRIOR_MARKER).write_text(json.dumps(marker))
        with patch.object(m,'OLD_STAGE3_SOURCES',pins),self.assertRaisesRegex(RuntimeError,'before_after_differ'):m.verify_previous(self.root,offline)
    def test_old_evidence_or_source_tamper_refused(self):
        pins,stage,marker,data,offline=self.prior_fixture()
        (stage/'install.sql.review-only').write_bytes(b'changed old SQL')
        with patch.object(m,'OLD_STAGE3_SOURCES',pins),self.assertRaisesRegex(RuntimeError,'evidence_hash_differs'):m.verify_previous(self.root,offline)
        (stage/'install.sql.review-only').write_bytes(data['install.sql.review-only'])
        (self.root/'stage3-runtime'/'maintenance.sql.review-only').write_bytes(b'changed old source')
        with patch.object(m,'OLD_STAGE3_SOURCES',pins),self.assertRaisesRegex(RuntimeError,'source_pin_differs'):m.verify_previous(self.root,offline)
    def test_private_input_hash_and_symlink_refused(self):
        p=self.root/'private.json';p.write_bytes(b'{}');p.chmod(0o600)
        with self.assertRaisesRegex(RuntimeError,'hash_differs'):m.verified_input(self.root,p,'0'*64)
        link=self.root/'link';link.symlink_to(p)
        with self.assertRaises(OSError):m.verified_input(self.root,link,m.digest(b'{}'))

if __name__=='__main__':unittest.main()
