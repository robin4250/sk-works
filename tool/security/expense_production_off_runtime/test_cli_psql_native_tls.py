"""Real PG17+TLS+native psql+original runner/SQL, dedicated loopback fixture only."""
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import tempfile
import threading
import time
import unittest
from unittest.mock import patch
import cli_psql_transport as adapter
from review_runner import FILES,MARKER,Refused,install_review_once,recover_review_readonly

RUNTIME=Path(__file__).absolute().parent
REPO=RUNTIME.parents[2]
HOST='aws-0-ap-northeast-1.pooler.supabase.com'
LOGIN='cli_login_fixture.'+adapter.PROJECT
SECRET='fixture-only-password'
RUN=subprocess.run

class NativeCliTlsTest(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  if os.environ.get('SKO_EXPENSE_NATIVE_TLS_FIXTURE')!='isolated-loopback-only':raise RuntimeError('native_fixture_required')
  if {item[4][0] for item in socket.getaddrinfo(HOST,5432,type=socket.SOCK_STREAM)}!={'127.0.0.1'}:raise RuntimeError('loopback_alias_required')
  cls.psql=Path(os.environ['SKO_EXPENSE_FIXTURE_PSQL']);cls.ca=Path(os.environ['SKO_EXPENSE_FIXTURE_CA']);cls.node=shutil.which('node')
  if not cls.psql.is_absolute() or not cls.ca.is_absolute() or not cls.node:raise RuntimeError('fixture_runtime_required')
  cls.control_env={'PGHOST':HOST,'PGPORT':'5432','PGUSER':'postgres','PGDATABASE':'postgres','PGPASSWORD':SECRET,'PGSSLMODE':'verify-full','PGSSLROOTCERT':str(cls.ca),'PGPASSFILE':'/dev/null','PGSERVICEFILE':'/dev/null','PGCONNECT_TIMEOUT':'5','PGOPTIONS':'-c search_path=public'}
  if cls.control(b"select ssl from pg_stat_ssl where pid=pg_backend_pid();").strip()!=b't':raise RuntimeError('actual_postgres_tls_required')
  if cls.control(b'show server_version_num;').strip()[:2]!=b'17':raise RuntimeError('pg17_required')
  cls.fixture_temp=tempfile.TemporaryDirectory(prefix='sko-cli-native-prepared-');cls.fixture=Path(cls.fixture_temp.name)
  driver=REPO/'tool/security/fixture_dependencies/node_modules/pg/lib/index.js'
  result=RUN([cls.node,str(RUNTIME/'create_test_evidence.mjs'),(RUNTIME/'native_cli_tls_fixture_runtime.mjs').as_uri(),str(cls.fixture),str(driver)],cwd=REPO,env={'PATH':os.environ.get('PATH',''),'SKO_EXPENSE_NATIVE_TLS_FIXTURE':'isolated-loopback-only'},capture_output=True,timeout=90)
  if result.returncode:raise RuntimeError('original_fixture_prepare_failed')
  cls.control(('CREATE ROLE "'+LOGIN+'" LOGIN SUPERUSER PASSWORD \'fixture-only-password\';').encode())
 @classmethod
 def control(cls,sql):
  result=RUN([str(cls.psql),'-X','-w','-q','-A','-t','-v','ON_ERROR_STOP=1'],input=sql,capture_output=True,env=cls.control_env,timeout=15)
  if result.returncode:raise RuntimeError('fixture_control_failed')
  return result.stdout
 @classmethod
 def tearDownClass(cls):cls.fixture_temp.cleanup()
 def setUp(self):
  self.temp=tempfile.TemporaryDirectory(prefix='sko-cli-native-case-');self.root=Path(self.temp.name);self.root.chmod(0o700)
  self.source=self.root/'prepared';shutil.copytree(self.fixture,self.source)
  self.artifacts={name:adapter._sha((self.source/name).read_bytes()) for name in FILES}
  # Use the original CLI parser, including session-port normalization.
  cli=adapter.owner_helpers()
  script='\n'.join(f'export {k}="{v}"' for k,v in {'PGHOST':HOST,'PGPORT':'6543','PGUSER':LOGIN,'PGPASSWORD':SECRET,'PGDATABASE':'postgres'}.items())
  url,password=cli.parse_cli_script(script);config=cli.capture.endpoint(url,cli_login=True)
  self.transport=adapter.CliPsqlTransport(config,password,self.psql,self.ca,self.artifacts,HOST)
 def tearDown(self):
  self.control(b'DROP EVENT TRIGGER IF EXISTS fixture_delay_ddl;DROP FUNCTION IF EXISTS private.fixture_delay_ddl();')
  marker=self.root/MARKER
  if marker.exists():
   state=json.loads(marker.read_text())
   if state.get('unused_undo'):
    self.control(Path(state['unused_undo']).read_bytes())
    actual=json.loads(self.transport.capture_readonly((self.source/FILES[2]).read_bytes()))
    before=json.loads((self.source/FILES[0]).read_bytes())
    self.assertEqual(actual['after'],before['before']);self.assertEqual(actual['business'],before['business'])
  self.temp.cleanup()
 def run_case(self,mode):
  original=(self.source/FILES[1]).read_bytes();calls=[];failures=[];thread=None
  if mode=='disconnect-before':
   self.control(b"CREATE FUNCTION private.fixture_delay_ddl() RETURNS event_trigger LANGUAGE plpgsql AS $$BEGIN PERFORM pg_sleep(60);END$$;CREATE EVENT TRIGGER fixture_delay_ddl ON ddl_command_start WHEN TAG IN ('CREATE FUNCTION') EXECUTE FUNCTION private.fixture_delay_ddl();")
   def terminate():
    try:
     for _ in range(100):
      rows=self.control(("select pid from pg_stat_activity where usename='"+LOGIN+"' and wait_event='PgSleep'").encode()).strip()
      if rows:
       self.control(b'select pg_terminate_backend('+rows+b');');return
      time.sleep(.05)
     failures.append('fixture_backend_not_observed')
    except Exception:failures.append('fixture_kill_failed')
   thread=threading.Thread(target=terminate);thread.start()
  def run(args,**kw):
   result=RUN(args,**kw)
   if args[0]==str(self.psql) and kw.get('input')==original:
    calls.append(1)
    if mode=='disconnect-after':
     self.assertEqual(result.returncode,0,'real server COMMIT must complete before withholding caller acknowledgment')
     return subprocess.CompletedProcess(args,3,b'',b'fixture_acknowledgment_withheld')
   return result
  with patch.object(adapter.subprocess,'run',side_effect=run):
   state=install_review_once(self.source,self.root,self.transport,self.node)
   if thread:thread.join(timeout=10)
   self.assertEqual(failures,[])
   self.assertEqual(len(calls),1)
   self.assertEqual(state['phase'],'before_state_observed' if mode=='disconnect-before' else 'installed_off_unused_undo_candidate')
   self.assertEqual(state['commit_acknowledged'],mode=='ack')
   with self.assertRaises(Refused):install_review_once(self.source,self.root,self.transport,self.node)
   recovered=recover_review_readonly(self.root,self.transport,self.node)
   self.assertEqual(recovered['phase'],state['phase']);self.assertEqual(len(calls),1)
   self.assertTrue((self.root/MARKER).exists());self.assertFalse(recovered['retry_allowed'])
  return state
 def test_actual_pg17_tls_native_psql_ack_and_fresh_readonly(self):self.run_case('ack')
 def test_actual_pg17_tls_backend_termination_before_commit(self):self.run_case('disconnect-before')
 def test_actual_pg17_tls_commit_then_caller_acknowledgment_lost(self):self.run_case('disconnect-after')

if __name__=='__main__':unittest.main()
