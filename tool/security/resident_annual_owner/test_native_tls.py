"""Actual PG17/verify-full psql; dedicated synthetic loopback CI only."""
import importlib.util
import copy
import json
import os
from pathlib import Path
import select
import shutil
import socket
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import runner as r

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
RUN = subprocess.run


class FixtureProof:
    def __init__(self, generator, before):
        self.generator, self.before = generator, before
        self.install = generator.prepare_install(before, REPO).encode()
        envelope = "begin isolation level repeatable read read only;set local statement_timeout='30s';set local TimeZone='UTC';set local DateStyle='ISO, YMD';\n"
        self.read_sql = (envelope + generator.observer() + "select current_setting('sko.resident_annual_observation')::jsonb;rollback;\n").encode()
        _, expected = generator.sources(REPO)
        self.after_sql = (envelope + generator.postflight(before, expected) + "select current_setting('sko.resident_annual_observation')::jsonb;rollback;\n").encode()

    def before_ok(self, value):
        if value != self.before:
            raise ValueError('fixture_before_changed')

    def after_ok(self, value):
        return self.generator.prepare_restore(self.before, value, REPO).encode()


class NativeTlsTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if os.environ.get('CI') != 'true' or os.environ.get('SKO_ANNUAL_OWNER_NATIVE_FIXTURE') != 'isolated-loopback-only' or os.sys.platform != 'linux':
            raise RuntimeError('dedicated_linux_ci_fixture_required')
        if any(k in os.environ for k in ('SUPABASE_ACCESS_TOKEN','SUPABASE_DB_PASSWORD','SUPABASE_URL','SUPABASE_SERVICE_ROLE_KEY','SUPABASE_SECRET_KEY','SUPABASE_PROJECT_REF')):
            raise RuntimeError('hosted_configuration_refused')
        if {x[4][0] for x in socket.getaddrinfo('127.0.0.1',5432,type=socket.SOCK_STREAM)} != {'127.0.0.1'}:
            raise RuntimeError('loopback_only_required')
        cls.psql=Path(os.environ['SKO_ANNUAL_FIXTURE_PSQL'])
        cls.ca=Path(os.environ['SKO_ANNUAL_FIXTURE_CA'])
        cls.wrongca=Path(os.environ['SKO_ANNUAL_FIXTURE_WRONG_CA'])
        cls.binding={key:{'path':str(p),'sha256':r.sha(p.read_bytes())}
            for key,p in [('psql',cls.psql),('cli',cls.psql),('certificate',cls.ca)]}
        cls.config={'PGHOST':'127.0.0.1','PGPORT':'5432','PGUSER':'cli_login_annual_native','PGDATABASE':'postgres'}
        cls.controlenv={'PGHOST':'127.0.0.1','PGPORT':'5432','PGUSER':'postgres','PGDATABASE':'postgres',
            'PGPASSWORD':'fixture-only','PGSSLMODE':'verify-full','PGSSLROOTCERT':str(cls.ca),'PGPASSFILE':'/dev/null',
            'PGSERVICEFILE':'/dev/null','PGCONNECT_TIMEOUT':'5','LC_ALL':'C'}
        driver=REPO/'tool/security/fixture_dependencies/node_modules/pg/lib/index.js'
        result=RUN([shutil.which('node'),str(HERE/'prepare_native_fixture.mjs'),str(driver)],cwd=REPO,
            env={k:v for k,v in os.environ.items() if not k.startswith('PG')},capture_output=True,timeout=90)
        if result.returncode:
            try:
                phase=json.loads(result.stdout.splitlines()[-1]).get('phase')
            except Exception:
                phase='unknown'
            allowed={'empty-pg17-tls-check','existing-payroll-scope-fixture','existing-lock-order-migration',
                'fixture-login-roles','fixture-server-default-role','wrong-role-readonly-identity-grants'}
            raise RuntimeError('native_fixture_preparation_failed:'+str(phase if phase in allowed else 'unknown'))
        spec=importlib.util.spec_from_file_location('annual_fixture_generator',REPO/'tool/security/prepare_resident_annual_deployment_review.py')
        cls.generator=importlib.util.module_from_spec(spec);spec.loader.exec_module(cls.generator)
        probe=("begin isolation level repeatable read read only;set local TimeZone='UTC';set local DateStyle='ISO, YMD';\n"
            +cls.generator.observer()+"select current_setting('sko.resident_annual_observation')::jsonb;rollback;\n").encode()
        cls.before=json.loads(cls.control(probe))
        cls.proof=FixtureProof(cls.generator,cls.before)
        if cls.control(b'select ssl from pg_stat_ssl where pid=pg_backend_pid();').strip()!=b't':
            raise RuntimeError('real_tls_required')

    @classmethod
    def control(cls,sql):
        result=RUN([str(cls.psql),'-X','-w','-q','-A','-t','-v','ON_ERROR_STOP=1'],input=sql,
            capture_output=True,env=cls.controlenv,timeout=45)
        if result.returncode:
            raise RuntimeError('fixture_control_failed')
        return result.stdout

    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(prefix='annual-owner-native-case-')
        self.root=Path(self.temp.name);self.root.chmod(0o700)
        self.transport=r.PsqlTransport(self.binding,self.config,'fixture-only')
        self.sha_patch=patch.object(r,'INSTALL_SHA',r.sha(self.proof.install));self.sha_patch.start()
        r.verify_identity(self.config,self.transport.read(r.IDENTITY_SQL))

    def tearDown(self):
        try:
            actual=self.transport.read(self.proof.read_sql)
            if actual!=self.before:
                # Fixture teardown only; production operate never executes this.
                self.control(self.proof.after_ok(actual))
                self.assertEqual(self.transport.read(self.proof.read_sql),self.before)
        finally:
            self.sha_patch.stop();self.transport.password=None;self.temp.cleanup()

    def exercise(self,mode):
        calls=[]
        def run(args,**kw):
            is_install=args[0]==str(self.psql) and kw.get('input')==self.proof.install
            if is_install:
                calls.append(1)
                self.assertTrue((self.root/r.MARKER).exists())
                if mode=='before-commit-disconnect':
                    original=self.proof.install.rstrip();self.assertTrue(original.endswith(b'commit;'))
                    process=subprocess.Popen(args,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,env=kw['env'],close_fds=True)
                    try:
                        process.stdin.write(original[:-len(b'commit;')]+b'\n\\echo native_body_finished\n');process.stdin.flush()
                        self.assertTrue(select.select([process.stdout],[],[],30)[0])
                        self.assertEqual(process.stdout.readline().strip(),b'native_body_finished')
                        pids=self.control(b"select pid from pg_stat_activity where usename='cli_login_annual_native' and state='idle in transaction';").strip().splitlines()
                        self.assertEqual(len(pids),1)
                        self.assertEqual(self.control(b'select pg_terminate_backend('+pids[0]+b');').strip(),b't')
                        process.stdin.close();process.stdin=None;process.communicate(timeout=10)
                    finally:
                        if process.poll() is None:process.kill();process.communicate(timeout=5)
                    return subprocess.CompletedProcess(args,3,b'',b'fixture_disconnect_before_commit')
            result=RUN(args,**kw)
            if is_install and mode=='after-commit-disconnect':
                self.assertEqual(result.returncode,0)
                return subprocess.CompletedProcess(args,3,b'',b'fixture_ack_withheld_after_commit')
            return result
        with patch.object(r.subprocess,'run',side_effect=run):
            state=r.operate(self.root,self.proof,self.transport,'install')
            self.assertEqual(len(calls),1)
            self.assertEqual(state['complete'],mode!='before-commit-disconnect')
            self.assertEqual(state['commit_acknowledged'],mode=='ack')
            with self.assertRaises(ValueError):r.operate(self.root,self.proof,self.transport,'install')
            recovered=r.operate(self.root,self.proof,self.transport,'recover')
            self.assertEqual(recovered['phase'],state['phase']);self.assertEqual(len(calls),1)
            if state['complete']:
                after=self.transport.read(self.proof.after_sql)
                for name in self.generator.NEW_TABLES:self.assertEqual(after['data'][name]['count'],0)
                for name,value in self.before['data'].items():self.assertEqual(after['data'][name],value)

    def test_real_tls_psql_exact_install_and_originals_unchanged(self):self.exercise('ack')
    def test_real_tls_disconnect_before_commit_never_resends(self):self.exercise('before-commit-disconnect')
    def test_real_tls_commit_ack_lost_recovers_readonly(self):self.exercise('after-commit-disconnect')

    def test_wrong_ca_fails_before_marker_or_delivery(self):
        binding=dict(self.binding,certificate={'path':str(self.wrongca),'sha256':r.sha(self.wrongca.read_bytes())})
        wrong=r.PsqlTransport(binding,self.config,'fixture-only')
        with self.assertRaisesRegex(RuntimeError,'transport_result_unknown'):
            wrong.read(r.IDENTITY_SQL)
        self.assertFalse((self.root/r.MARKER).exists())

    def test_wrong_current_role_rejected_before_marker_or_delivery(self):
        config=dict(self.config,PGUSER='cli_login_annual_wrong')
        wrong=r.PsqlTransport(self.binding,config,'fixture-only')
        identity=wrong.read(r.IDENTITY_SQL)
        self.assertEqual(identity['current_user'],'cli_login_annual_wrong')
        with self.assertRaisesRegex(ValueError,'maintenance_identity_refused'):
            r.verify_identity(config,identity)
        self.assertFalse((self.root/r.MARKER).exists())

    def test_real_readonly_preflight_zero_delivery(self):
        state=r.operate(self.root,self.proof,self.transport,'preflight')
        self.assertFalse(state['deployment_performed']);self.assertFalse((self.root/r.MARKER).exists())
        self.assertEqual(self.transport.read(self.proof.read_sql),self.before)

    def test_stale_fixture_checkpoint_zero_delivery(self):
        stale=copy.copy(self.proof)
        stale.before=copy.deepcopy(self.before)
        stale.before['data']['public.workers']['sha256']='0'*64
        with patch.object(self.transport,'install_once') as delivery:
            with self.assertRaisesRegex(ValueError,'fixture_before_changed'):
                r.operate(self.root,stale,self.transport,'install')
            delivery.assert_not_called()
        self.assertFalse((self.root/r.MARKER).exists())


if __name__=='__main__':unittest.main()
