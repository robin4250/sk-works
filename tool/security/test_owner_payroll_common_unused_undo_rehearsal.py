import contextlib
import io
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import owner_payroll_common_unused_undo_rehearsal as native
import common_payroll_unused_undo as undo
import test_common_payroll_unused_undo as fixtures

class NativeLifecycleTests(unittest.TestCase):
    def lifecycle(self,fail_phase=None):
        before,after=fixtures.UnusedUndoTests().snapshots()
        with tempfile.TemporaryDirectory() as folder:
            home=Path(folder);root=home/'SKO-source-backups';root.mkdir(mode=0o700)
            source=root/native.transport.SOURCE;source.mkdir(mode=0o700)
            source_name='sko-restore-'+'b'*12
            (source/'rehearsal-status.json').write_text(json.dumps({'archive_restore_verified':True,'container_stopped':True,'container':source_name}))
            calls=[];captures=0;active=before
            def run(command,**kw):
                nonlocal captures,active
                calls.append(command);self.assertNotIn('shell',kw);data=b''
                if command[:3]==['docker','context','inspect']:data=b'[{"Endpoints":{"docker":{"Host":"unix:///synthetic"}}}]'
                elif command[:2]==['docker','inspect']:data=json.dumps([{'State':{'Running':False},'HostConfig':{'NetworkMode':'none','PortBindings':{}},'Config':{'Image':native.transport.BASE_IMAGE,'Labels':{'sko-purpose':'offline-restore'}}}]).encode()
                elif command[:2]==['docker','commit']:data=('sha256:'+'a'*64).encode()
                elif 'psql' in command:
                    text=kw['input'].decode()
                    if 'SHOW cron.launch_active_jobs' in text:data=b'off\n'
                    elif undo.CATALOG_SNAPSHOT_SQL in text:
                        captures+=1;active=before if captures in (1,5) else after
                        data=json.dumps(active['catalog']).encode()
                    elif undo.FUNCTIONS_SQL in text:data=json.dumps(active['functions']).encode()
                    elif native.BUSINESS_SQL in text:data=active['business_hash'].encode()
                    elif '-- REVIEW ONLY: exact native checkpoint' in text and fail_phase=='unused_undo_commit':raise subprocess.CalledProcessError(1,command)
                    elif '-- STAGED ONLY.' in text and fail_phase=='dependency_install_commit':raise subprocess.CalledProcessError(1,command)
                    elif 'protected original payroll differs' in text:
                        self.assertIn('unused undo did not reject protected case',text)
                        self.assertTrue(text.rstrip().endswith('ROLLBACK;'))
                return subprocess.CompletedProcess(command,0,data)
            with patch.object(native.sys,'platform','darwin'),patch.object(native.Path,'home',return_value=home),patch.dict(native.os.environ,{},clear=True),patch.object(native.subprocess,'run',side_effect=run),contextlib.redirect_stdout(io.StringIO()):code=native.main()
            stage=next(root.glob('payroll-common-unused-undo-*'))
            status=json.loads((stage/'common-unused-undo-status.json').read_text())
            self.assertFalse(any(c[:2]==['docker','start'] and source_name in c for c in calls))
            self.assertFalse(any(c[:2]==['docker','stop'] and source_name in c for c in calls))
            self.assertTrue(any(c==['/usr/bin/pbcopy'] for c in calls))
            clone=next(c for c in calls if c[:3]==['docker','run','-d']);self.assertIn('--network=none',clone)
            for forbidden in ['--mount','--publish','--privileged']:self.assertNotIn(forbidden,clone)
            return code,status

    def test_committed_install_guarded_undo_and_private_artifacts(self):
        code,status=self.lifecycle();self.assertEqual(code,0)
        for key in ['verified','catalog_restored','business_unchanged','unused_undo_committed','used_undo_refused','unknown_followup_refused','existing_oids_preserved','container_stopped']:self.assertTrue(status[key])
        for key in ['production_connected','activation_written','payroll_recalculated','real_jwt_verified','oid_counter_restored']:self.assertFalse(status[key])
        self.assertEqual(len(status['artifacts']),4)

    def test_install_failure_stops_clone_and_does_not_claim_success(self):
        code,status=self.lifecycle('dependency_install_commit');self.assertEqual(code,1);self.assertFalse(status['verified']);self.assertTrue(status['container_stopped']);self.assertEqual(status['phase'],'dependency_install_commit')

    def test_undo_failure_preserves_private_record_stops_clone(self):
        code,status=self.lifecycle('unused_undo_commit');self.assertEqual(code,1);self.assertFalse(status['verified']);self.assertTrue(status['container_stopped']);self.assertEqual(status['phase'],'unused_undo_commit')

if __name__=='__main__':unittest.main()
