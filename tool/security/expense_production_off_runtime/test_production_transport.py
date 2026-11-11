"""Actual Python adapter boundaries; subprocess faults are isolated fakes, no DB."""
import json
import subprocess
import unittest
import os
from pathlib import Path
import tempfile
from unittest.mock import patch
import production_transport as adapter
from review_runner import FILES, MARKER, Refused, install_review_once, recover_review_readonly

INSTALL=b'BEGIN; immutable fixture; COMMIT;'
READ=b'BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY; fixture; COMMIT;'
SECRET=b'synthetic-only-never-log'

class ProductionAdapterBoundaryTest(unittest.TestCase):
    def make_transport(self):
        return adapter._DedicatedTransport({'artifacts':{FILES[1]:adapter._sha(INSTALL),FILES[2]:adapter._sha(READ)}},SECRET)

    def test_unbound_install_and_recovery_refuse_before_secret_or_process(self):
        with patch.object(adapter,'_read_password') as credential,patch.object(adapter.subprocess,'run') as process:
            for action in (adapter.install_approved_once,adapter.recover_approved_readonly):
                with self.assertRaisesRegex(Refused,'not_approved'):action(99)
            credential.assert_not_called();process.assert_not_called()

    def test_single_immutable_submission_clean_env_and_fresh_process_observation(self):
        transport=self.make_transport()
        with patch.object(adapter.subprocess,'run',side_effect=[subprocess.CompletedProcess([],0,b'{"acknowledged":true}',b''),subprocess.CompletedProcess([],0,b'{"read_only":"on"}',b'')]) as process:
            transport.execute_install_once(INSTALL)
            self.assertEqual(transport.capture_readonly(READ),b'{"read_only":"on"}')
            with self.assertRaises(Refused):transport.execute_install_once(INSTALL)
            self.assertEqual(process.call_count,2)
            for call in process.call_args_list:
                args,kw=call.args,call.kwargs
                self.assertEqual(len(args[0]),2);self.assertNotIn(SECRET.decode(),str(args))
                self.assertEqual(kw['env'],{'LANG':'C.UTF-8'});self.assertTrue(kw['close_fds']);self.assertEqual(kw['timeout'],45)
            self.assertEqual(json.loads(process.call_args_list[0].kwargs['input'])['sql'].encode(),INSTALL)
            self.assertEqual(json.loads(process.call_args_list[1].kwargs['input'])['mode'],'read-only')

    def test_timeout_disconnect_or_bad_ack_are_unknown_and_never_resend(self):
        for failure in (subprocess.TimeoutExpired('synthetic',45,output=SECRET),subprocess.CompletedProcess([],3,SECRET,SECRET),subprocess.CompletedProcess([],0,b'not-ack',b'')):
            with self.subTest(failure=type(failure).__name__):
                transport=self.make_transport()
                side_effect=failure if isinstance(failure,Exception) else None
                with patch.object(adapter.subprocess,'run',side_effect=side_effect,return_value=failure) as process:
                    with self.assertRaises(ConnectionError) as caught:transport.execute_install_once(INSTALL)
                    self.assertNotIn(SECRET.decode(),str(caught.exception))
                    with self.assertRaises(Refused):transport.execute_install_once(INSTALL)
                    self.assertEqual(process.call_count,1)

    def test_changed_sql_refused_before_process_and_consumes_attempt(self):
        transport=self.make_transport()
        with patch.object(adapter.subprocess,'run') as process:
            with self.assertRaises(Refused):transport.execute_install_once(INSTALL+b' changed')
            with self.assertRaises(Refused):transport.execute_install_once(INSTALL)
            process.assert_not_called()

    def test_explicit_private_descriptor_only_and_no_environment_discovery(self):
        with tempfile.TemporaryDirectory() as temporary:
            path=Path(temporary)/'secret';path.write_bytes(SECRET);path.chmod(0o600)
            fd=os.open(path,os.O_RDONLY)
            try:
                self.assertEqual(adapter._read_password(fd),SECRET)
                path.chmod(0o644)
                with self.assertRaises(Refused):adapter._read_password(fd)
            finally:os.close(fd)
        for fd in (0,1,2):
            with self.assertRaises(Refused):adapter._read_password(fd)

    def test_permanent_runner_marker_precedes_adapter_send_and_recovery_is_readonly(self):
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary);root.chmod(0o700)
            stage=root/'prepared-copy';stage.mkdir(mode=0o700)
            for name,value in zip(FILES,(b'{}',INSTALL,READ)):
                path=stage/name;path.write_bytes(value);path.chmod(0o600)
            transport=self.make_transport();modes=[]
            def process(*args,**kw):
                self.assertTrue((root/MARKER).is_file(),'durable permanent marker before subprocess')
                body=json.loads(kw['input']);modes.append(body['mode'])
                if body['mode']=='install':raise subprocess.TimeoutExpired('synthetic',45,output=SECRET)
                return subprocess.CompletedProcess([],0,b'{"read_only":"on"}',b'')
            def generator(node,observation,mode):
                if mode=='classify':
                    path=observation/'classification.json';path.write_text('{"state":"before_state_observed"}');path.chmod(0o600)
            with patch('review_runner.validated_copy',return_value=stage),patch('review_runner.generator',side_effect=generator),patch.object(adapter.subprocess,'run',side_effect=process):
                state=install_review_once(stage,root,transport,str(adapter.NODE))
                self.assertEqual(state['phase'],'before_state_observed');self.assertFalse(state['commit_acknowledged'])
                with self.assertRaises(Refused):install_review_once(stage,root,self.make_transport(),str(adapter.NODE))
                recover_review_readonly(root,self.make_transport(),str(adapter.NODE))
                self.assertEqual(modes,['install','read-only','read-only']);self.assertTrue((root/MARKER).exists())

    def test_approved_manifest_binds_root_original_artifacts_code_and_dependencies(self):
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary);root.chmod(0o700)
            prepared=root/'prepared';prepared.mkdir(mode=0o700)
            artifacts={}
            for name in (*FILES,'prepare-status.json'):
                path=prepared/name;path.write_bytes(b'synthetic-private-evidence');path.chmod(0o600)
                artifacts[name]=adapter._sha(path.read_bytes())
            runtime=root/'code';runtime.mkdir(mode=0o700)
            code={}
            for name in adapter.TRANSPORT_FILES:
                path=runtime/name;path.write_bytes(b'synthetic-reviewed-code');code[name]=adapter._sha(path.read_bytes())
            deps=root/'fixture_dependencies'/'node_modules';deps.mkdir(parents=True,mode=0o700)
            (deps/'pg.js').write_bytes(b'pinned-fixture-driver')
            node=root/'node';node.write_bytes(b'fixture-node-binary')
            manifest={'schema':1,'project':adapter.PROJECT,'host':adapter.HOST,'role':'postgres','database':'postgres','root':str(root),'artifacts':artifacts,'transport_files':code,'node_sha256':adapter._sha(node.read_bytes()),'pg_dependency_tree_sha256':adapter.dependency_tree_sha256(deps)}
            approval=root/'production-approval.json';approval.write_text(json.dumps(manifest));approval.chmod(0o600)
            with patch.object(adapter,'APPROVED_DURABLE_ROOT',root),patch.object(adapter,'APPROVED_MANIFEST_SHA256',adapter._sha(approval.read_bytes())),patch.object(adapter,'RUNTIME',runtime),patch.object(adapter,'NODE',node):
                self.assertEqual(adapter._binding(),manifest)
                for changed in [prepared/FILES[0],runtime/adapter.TRANSPORT_FILES[0],node,deps/'pg.js',approval]:
                    before=changed.read_bytes();changed.write_bytes(before+b'tamper')
                    with self.assertRaises(Refused):adapter._binding()
                    changed.write_bytes(before)
                self.assertEqual(adapter._binding(),manifest)

if __name__=='__main__':unittest.main()
