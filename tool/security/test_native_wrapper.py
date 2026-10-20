import contextlib
import io
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import owner_common_production_wrapper_rehearsal as probe

class NativeWrapperTests(unittest.TestCase):
    def test_reuses_exact_reviewed_install(self):
        sql=probe.reviewed_install(Path(__file__).parent)
        self.assertIn('COMMIT;',sql);self.assertIn('sko_common_install_checkpoints',sql)
    def test_modified_install_refuses_without_database_operation(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);(root/'company_common_default_off_install.sql.review-only').write_text('BEGIN;COMMIT;')
            with self.assertRaisesRegex(RuntimeError,'hash_mismatch'):probe.reviewed_install(root)
    def test_transport_is_offline_and_no_host_backup_mount(self):
        args=probe.transport.clone_command('sko-common-'+'a'*12,'sha256:'+'b'*64)
        self.assertIn('--network=none',args);self.assertIn('cron.launch_active_jobs=off',args)
        for forbidden in ('--publish','-p','--mount','-v','--network=host'):self.assertNotIn(forbidden,args)
    def test_preclone_failure_keeps_original_and_writes_only_safe_result(self):
        with tempfile.TemporaryDirectory() as folder:
            home=Path(folder);root=home/'SKO-source-backups';root.mkdir(mode=0o700)
            src=root/probe.transport.SOURCE;src.mkdir();(src/'rehearsal-status.json').write_text(json.dumps({'archive_restore_verified':True,'container_stopped':True,'container':'sko-restore-'+'b'*12}))
            calls=[]
            def run(args,**kwargs):
                calls.append(args)
                if args[:3]==['docker','context','inspect']:raise subprocess.CalledProcessError(1,args)
                return subprocess.CompletedProcess(args,0,b'',b'')
            with patch.object(probe.sys,'platform','darwin'),patch.object(probe.Path,'home',return_value=home),patch.dict(probe.os.environ,{},clear=True),patch.object(probe.subprocess,'run',side_effect=run),contextlib.redirect_stdout(io.StringIO()) as output:
                self.assertEqual(probe.main(),1)
            self.assertFalse(any(args[:2] in (['docker','start'],['docker','stop']) for args in calls))
            self.assertNotIn('private-errors',output.getvalue())
            self.assertTrue(any(args==['/usr/bin/pbcopy'] for args in calls))
    def test_install_failure_stops_only_created_clone_id(self):
        with tempfile.TemporaryDirectory() as folder:
            home=Path(folder);root=home/'SKO-source-backups';root.mkdir(mode=0o700);src=root/probe.transport.SOURCE;src.mkdir()
            original='sko-restore-'+'b'*12;created='c'*64
            (src/'rehearsal-status.json').write_text(json.dumps({'archive_restore_verified':True,'container_stopped':True,'container':original}))
            calls=[]
            def run(args,**kwargs):
                calls.append(args);value=b''
                if args[:3]==['docker','context','inspect']:value=json.dumps([{'Endpoints':{'docker':{'Host':'unix:///fixture'}}}]).encode()
                elif args[:2]==['docker','inspect']:
                    info={'State':{'Running':False},'HostConfig':{'NetworkMode':'none','PortBindings':{}},'Config':{'Image':probe.transport.BASE_IMAGE,'Labels':{'sko-purpose':'offline-restore'}}};value=json.dumps([info]).encode()
                elif args[:2]==['docker','commit']:value=('sha256:'+'a'*64).encode()
                elif args[:2]==['docker','create']:value=created.encode()
                elif args[:3]==['docker','exec','-i']:
                    sql=kwargs['input'].decode()
                    if '-- REVIEW ONLY.' in sql:raise subprocess.CalledProcessError(1,args)
                    if sql.endswith('SHOW cron.launch_active_jobs;'):value=b'off'
                    elif sql.endswith(probe.undo.CATALOG_SNAPSHOT_SQL):value=json.dumps({'hash':'a'*32,'catalog':{}}).encode()
                    elif sql.endswith(probe.undo.FUNCTIONS_SQL):value=b'[]'
                    elif 'common_data_fingerprints' in sql:value=b'a'*32
                return subprocess.CompletedProcess(args,0,value,b'')
            with patch.object(probe.sys,'platform','darwin'),patch.object(probe.Path,'home',return_value=home),patch.dict(probe.os.environ,{},clear=True),patch.object(probe.subprocess,'run',side_effect=run),contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(probe.main(),1)
            self.assertIn(['docker','stop','-t','10',created],calls)
            self.assertFalse(any(args[:2] in (['docker','start'],['docker','stop']) and original in args for args in calls))
            status=json.loads(next(root.glob('common-production-wrapper-*/wrapper-rehearsal-status.json')).read_text())
            self.assertEqual(status['phase'],'reviewed_wrapper_install_commit');self.assertTrue(status['container_stopped']);self.assertFalse(status['verified'])

    def test_runner_does_not_repeat_legal_flow_or_jwt(self):
        source=(Path(__file__).parent/'owner_common_production_wrapper_rehearsal.py').read_text()
        for forbidden in ('common_flow_scenario','gotrue','password_grant','GOTRUE','db-url','PGPASSWORD'):self.assertNotIn(forbidden,source)

if __name__=='__main__':unittest.main()
