import contextlib
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
# Local development layout only; deployed tool/security files are siblings.
sys.path.append(str(Path(__file__).parents[1]/'backup-capture-preparation-20261020'))
import owner_collector_restored_rehearsal as collector


class CollectorRestoredTests(unittest.TestCase):
    def test_existing_candidate_exact_hash_and_one_rollback(self):
        bundle=json.loads((Path(collector.__file__).parent/'collector_restored_bundle.json').read_text())
        sql=collector.transaction_sql(bundle)
        self.assertEqual(sql.count('ROLLBACK;'),1)
        self.assertNotIn('commit;',sql)
        self.assertNotIn('CREATE OR REPLACE FUNCTION private.consume_reauthentication_proof',sql)
        bundle['candidate']+='-- unknown change\n'
        with self.assertRaisesRegex(RuntimeError,'candidate_mismatch'): collector.transaction_sql(bundle)

    def test_clone_uses_no_network_ports_mount_or_credentials(self):
        args=collector.clone_command('fixture','sha256:'+'a'*64)
        self.assertIn('--network=none',args)
        self.assertIn('listen_addresses=',args)
        self.assertIn('cron.launch_active_jobs=off',args)
        for value in ('--mount','--publish','--privileged','PGPASSWORD'):
            self.assertNotIn(value,args)

    def lifecycle(self,missing_dependency=False,fail_transaction=False,fail_stop=False):
        with tempfile.TemporaryDirectory() as folder:
            home=Path(folder); root=home/'SKO-source-backups'; root.mkdir(mode=0o700)
            source=root/collector.base.SOURCE; source.mkdir(mode=0o700)
            name='sko-restore-'+'b'*12
            (source/'rehearsal-status.json').write_text(json.dumps({'archive_restore_verified':True,'container_stopped':True,'container':name}))
            calls=[]
            def run(args,**kwargs):
                calls.append((args,kwargs.get('input')))
                self.assertNotIn('shell',kwargs)
                data=b''; code=0
                if args[:3]==['docker','context','inspect']:
                    data=json.dumps([{'Endpoints':{'docker':{'Host':'unix:///synthetic'}}}]).encode()
                elif args[:2]==['docker','inspect']:
                    source_check=args[-1]==name
                    data=json.dumps([{'State':{'Running':False},'HostConfig':{'NetworkMode':'none','PortBindings':{}},'Config':{'Image':collector.base.BASE_IMAGE,'Labels':{'sko-purpose':'offline-restore' if source_check else 'collector-restored-rehearsal'}}}]).encode()
                elif args[:2]==['docker','commit']: data=('sha256:'+'a'*64).encode()
                elif args[:2]==['docker','stop'] and fail_stop: code=1
                elif 'psql' in args:
                    sql=kwargs['input'].decode()
                    if 'SHOW cron.launch_active_jobs' in sql: data=b'off\n'
                    elif 'CREATE ROLE sko_security_collector_ingest' in sql:
                        if fail_transaction: raise subprocess.CalledProcessError(1,args)
                    elif collector.CATALOG_SQL in sql: data=b'{"fixture":true}\n'
                    elif collector.SEQUENCE_QUERIES_SQL in sql: data=b'[]\n'
                    elif "SELECT '[]';" in sql: data=b'[]\n'
                    elif collector.ROW_QUERIES_SQL in sql: data=b'["select synthetic fixture"]\n'
                    elif 'SELECT jsonb_agg(to_jsonb(t)' in sql: data=b'[{"relation":"public.fixture","digest":"synthetic"}]\n'
                    elif "SELECT to_regprocedure('private.consume_reauthentication_proof" in sql:
                        data=b'f\n' if missing_dependency else b't\n'
                    elif "select to_regrole('sko_security_collector_ingest')" in sql: data=b't\n'
                return subprocess.CompletedProcess(args,code,data)
            with patch.object(collector.sys,'platform','darwin'),patch.object(collector.Path,'home',return_value=home),patch.dict(collector.os.environ,{},clear=True),patch.object(collector.subprocess,'run',side_effect=run),contextlib.redirect_stdout(io.StringIO()):
                code=collector.main()
            status=json.loads(next(root.glob('collector-restored-rehearsal-*/collector-rehearsal-status.json')).read_text())
            self.assertFalse(any(args[:2] in (['docker','stop'],['docker','start']) and name in args for args,_ in calls))
            self.assertTrue(any(args==['/usr/bin/pbcopy'] for args,_ in calls))
            return code,status,calls

    def test_lifecycle_rollback_and_original_source_untouched(self):
        code,status,_=self.lifecycle()
        self.assertEqual(code,0)
        self.assertTrue(status['verified'])
        self.assertTrue(status['container_stopped'])
        self.assertTrue(status['existing_tables_unchanged'])
        self.assertTrue(status['existing_sequences_unchanged'])
        self.assertFalse(status['production_connected'])
        self.assertFalse(status['real_signature_verified'])
        self.assertFalse(status['real_master_proof_verified'])

    def test_missing_dependency_stops_without_install_or_fake_proof(self):
        code,status,calls=self.lifecycle(missing_dependency=True)
        self.assertEqual(code,1)
        self.assertFalse(status['verified'])
        self.assertEqual(status['required_dependency'],'existing_reauthentication_consumer')
        self.assertTrue(status['container_stopped'])
        self.assertFalse(any(isinstance(data,bytes) and b'CREATE ROLE sko_security_collector_ingest' in data for _,data in calls))

    def test_sql_failure_stops_only_clone_and_never_reports_verified(self):
        code,status,_=self.lifecycle(fail_transaction=True)
        self.assertEqual(code,1)
        self.assertFalse(status['verified'])
        self.assertTrue(status['container_stopped'])
        self.assertEqual(status['phase'],'collector_transaction')

    def test_cleanup_failure_not_reported_as_success(self):
        code,status,_=self.lifecycle(fail_stop=True)
        self.assertEqual(code,1)
        self.assertFalse(status['verified'])
        self.assertFalse(status['container_stopped'])


if __name__=='__main__': unittest.main()
