import contextlib
import io
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import owner_payroll_common_flow_rehearsal as common


class CommonFlowTests(unittest.TestCase):
    def bundle(self):
        return json.loads((Path(common.__file__).parent/'common_payroll_sources.json').read_text())

    def scenario(self):
        return json.loads((Path(common.__file__).parent/'common_flow_scenario.json').read_text())

    def test_exact_four_artifacts_keep_guards_and_one_transaction(self):
        sql=common.build_flow(self.bundle(),self.scenario())
        self.assertTrue(sql.startswith('BEGIN;'))
        self.assertTrue(sql.endswith('ROLLBACK;'))
        self.assertNotIn('20261013175452_payroll_unit_conditions.sql',common.dependencies.EXPECTED)
        self.assertIn("'5c51172a6169beb90a7ddbb6ae443cd6'",sql)
        self.assertIn('legacy allowance source baseline drift',sql)
        self.assertIn('dated company common payroll prerequisite differs',sql)
        self.assertNotIn('COMMIT;',sql.upper())
        self.assertIn('tables<>11',sql)

    def test_reject_changed_missing_or_extra_source(self):
        for mutate in [lambda b:b['files'].__setitem__(next(iter(b['files'])),'modified'),lambda b:b['files'].pop(next(iter(b['files']))),lambda b:b['files'].__setitem__('unexpected.sql','select 1')]:
            b=self.bundle();mutate(b)
            with self.assertRaises(RuntimeError):common.build_flow(b,self.scenario())

    def lifecycle(self,fail=False,fail_stop=False,incomplete=False):
        with tempfile.TemporaryDirectory() as folder:
            home=Path(folder);root=home/'SKO-source-backups';root.mkdir(mode=0o700)
            source=root/common.transport.SOURCE;source.mkdir(mode=0o700)
            source_name='sko-restore-'+'b'*12
            (source/'rehearsal-status.json').write_text(json.dumps({'archive_restore_verified':True,'container_stopped':True,'container':source_name}))
            calls=[]
            def run(command,**kw):
                calls.append(command);self.assertNotIn('shell',kw);data=b''
                if command[:3]==['docker','context','inspect']:data=b'[{"Endpoints":{"docker":{"Host":"unix:///synthetic"}}}]'
                elif command[:2]==['docker','inspect']:data=json.dumps([{'State':{'Running':False},'HostConfig':{'NetworkMode':'none','PortBindings':{}},'Config':{'Image':common.transport.BASE_IMAGE,'Labels':{'sko-purpose':'offline-restore'}}}]).encode()
                elif command[:2]==['docker','commit']:data=('sha256:'+'a'*64).encode()
                elif 'psql' in command:
                    text=kw['input'].decode()
                    if 'SHOW cron.launch_active_jobs' in text:data=b'off\n'
                    elif common.CATALOG_SQL in text:data=b'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n'
                    elif common.BUSINESS_SQL in text:data=b'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\n'
                    elif 'BEGIN;' in text and '-- STAGED ONLY.' in text:
                        if fail:raise subprocess.CalledProcessError(1,command)
                        result={k:True for k in ['saved','published','payroll_totals_verified','public_detail_verified','tax_insurance_conditions_preserved','resident_tax_preserved','save_retry_verified','publish_retry_verified','cas_verified']}
                        if incomplete:result['tax_insurance_conditions_preserved']=False
                        result.update(protected_existing_statement_count=0,recalculated_scopes=1)
                        data=json.dumps(result).encode()
                return subprocess.CompletedProcess(command,1 if fail_stop and command[:2]==['docker','stop'] else 0,data)
            with patch.object(common.sys,'platform','darwin'),patch.object(common.Path,'home',return_value=home),patch.dict(common.os.environ,{},clear=True),patch.object(common.subprocess,'run',side_effect=run),contextlib.redirect_stdout(io.StringIO()):code=common.main()
            status=json.loads(next(root.glob('payroll-common-flow-*/common-rehearsal-status.json')).read_text())
            self.assertFalse(any(c[:2]==['docker','start'] and source_name in c for c in calls))
            self.assertFalse(any(c[:2]==['docker','stop'] and source_name in c for c in calls))
            self.assertTrue(any(c==['/usr/bin/pbcopy'] for c in calls))
            clone=next(c for c in calls if c[:3]==['docker','run','-d'])
            self.assertIn('--network=none',clone)
            for x in ['--mount','--publish','--privileged']:self.assertNotIn(x,clone)
            return code,status

    def test_install_rollback_and_preservation(self):
        code,status=self.lifecycle()
        self.assertEqual(code,0);self.assertTrue(status['verified']);self.assertTrue(status['catalog_restored']);self.assertTrue(status['business_unchanged']);self.assertTrue(status['container_stopped'])
        for k in ['production_connected','production_activation_written','production_payroll_recalculated','real_jwt_verified']:self.assertFalse(status[k])

    def test_stop_failure_is_not_reported_as_success(self):
        code,status=self.lifecycle(fail_stop=True)
        self.assertEqual(code,1);self.assertFalse(status['verified']);self.assertFalse(status['container_stopped']);self.assertEqual(status['phase'],'clone_stop')

    def test_failure_stops_only_clone(self):
        code,status=self.lifecycle(True)
        self.assertEqual(code,1);self.assertFalse(status['verified']);self.assertTrue(status['container_stopped']);self.assertEqual(status['phase'],'common_save_publish_rollback')

    def test_changed_scenario_refused(self):
        s=self.scenario();s['sql']+='select 1;'
        with self.assertRaisesRegex(RuntimeError,'scenario_hash_mismatch'):common.build_flow(self.bundle(),s)

    def test_incomplete_tax_result_refuses_success(self):
        code,status=self.lifecycle(incomplete=True)
        self.assertEqual(code,1);self.assertFalse(status['verified']);self.assertTrue(status['container_stopped'])

if __name__=='__main__':unittest.main()
