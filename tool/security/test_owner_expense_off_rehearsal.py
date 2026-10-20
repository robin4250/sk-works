import contextlib
import io
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import owner_expense_off_rehearsal as off


class ExpenseRehearsalTests(unittest.TestCase):
    def test_clone_no_host_mount_network_or_credentials(self):
        command=off.clone_command('fixture','sha256:'+'a'*64)
        self.assertIn('--network=none',command)
        self.assertIn('cron.launch_active_jobs=off',command)
        self.assertIn('listen_addresses=',command)
        for forbidden in ('--mount','--publish','--privileged','PGPASSWORD'):
            self.assertNotIn(forbidden,command)

    def test_database_properties_match_source_without_extra_schema_grant(self):
        self.assertIn('ALTER DATABASE postgres OWNER TO postgres',off.DATABASE_BASELINE_SQL)
        self.assertNotIn('GRANT CREATE ON SCHEMA',off.DATABASE_BASELINE_SQL)
        self.assertIn('actual IS DISTINCT FROM expected',off.DATABASE_BASELINE_SQL)
        self.assertIn('unknown clone database grant',off.DATABASE_BASELINE_SQL)

    def lifecycle(self,fail_install=False):
        with tempfile.TemporaryDirectory() as folder:
            home=Path(folder); root=home/'SKO-source-backups'; root.mkdir(mode=0o700)
            source=root/off.SOURCE; source.mkdir(mode=0o700)
            source_name='sko-restore-'+'b'*12
            (source/'rehearsal-status.json').write_text(json.dumps({'archive_restore_verified':True,'container_stopped':True,'container':source_name}))
            calls=[]; checkpoints=0
            def run(command,**kwargs):
                nonlocal checkpoints
                calls.append(command)
                self.assertNotIn('shell',kwargs)
                data=b''
                if command[:3]==['docker','context','inspect']:
                    data=json.dumps([{'Endpoints':{'docker':{'Host':'unix:///synthetic'}}}]).encode()
                elif command[:2]==['docker','inspect']:
                    data=json.dumps([{'State':{'Running':False},'HostConfig':{'NetworkMode':'none','PortBindings':{}},'Config':{'Image':off.BASE_IMAGE,'Labels':{'sko-purpose':'offline-restore'}}}]).encode()
                elif command[:2]==['docker','commit']: data=('sha256:'+'a'*64).encode()
                elif command[:3]==['docker','image','inspect']: data=json.dumps([{'Id':'sha256:'+'c'*64}]).encode()
                elif command[:2]==['docker','run'] and '--rm' in command:
                    self.assertIn('--network=none',command)
                    self.assertIn('--user',command)
                    stage=next(root.glob('expense-off-rehearsal-*'))
                    payload=json.loads((stage/'input.json').read_text())
                    (stage/'generated.sql').write_text('UNDO FIXTURE' if 'after' in payload else 'INSTALL FIXTURE')
                elif 'psql' in command:
                    text=kwargs['input'].decode()
                    bundle=json.loads((Path(off.__file__).parent/'expense_off_rehearsal_bundle.json').read_text())
                    if 'SHOW cron.launch_active_jobs' in text: data=b'off\n'
                    elif bundle['queries']['catalogSql'] in text:
                        checkpoints+=1
                        data=json.dumps({'fixture':2 if checkpoints==2 else 1}).encode()
                    elif bundle['queries']['defaultOffBusinessHashSql'] in text: data=('d'*32).encode()
                    elif 'INSTALL FIXTURE' in text and fail_install: raise subprocess.CalledProcessError(1,command)
                return subprocess.CompletedProcess(command,0,data)
            with patch.object(off.sys,'platform','darwin'),patch.object(off.Path,'home',return_value=home),patch.dict(off.os.environ,{},clear=True),patch.object(off.subprocess,'run',side_effect=run),contextlib.redirect_stdout(io.StringIO()):
                code=off.main()
            status=json.loads(next(root.glob('expense-off-rehearsal-*/expense-rehearsal-status.json')).read_text())
            self.assertFalse(any(c[:2]==['docker','stop'] and source_name in c for c in calls))
            self.assertFalse(any(c[:2]==['docker','start'] and source_name in c for c in calls))
            self.assertTrue(any(c==['/usr/bin/pbcopy'] for c in calls))
            return code,status

    def test_clone_install_undo_and_unchanged_business(self):
        code,status=self.lifecycle()
        self.assertEqual(code,0)
        self.assertTrue(status['verified'])
        self.assertTrue(status['code_undo_verified'])
        self.assertTrue(status['business_unchanged'])
        self.assertTrue(status['database_owner_acl_matched'])
        self.assertTrue(status['container_stopped'])
        self.assertFalse(status['production_connected'])
        self.assertFalse(status['expense_rows_converted'])

    def test_failed_install_stops_only_clone_and_reports_incomplete(self):
        code,status=self.lifecycle(fail_install=True)
        self.assertEqual(code,1)
        self.assertFalse(status['verified'])
        self.assertTrue(status['container_stopped'])
        self.assertEqual(status['phase'],'off_install')


if __name__=='__main__': unittest.main()
