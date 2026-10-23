"""Actual native psql command boundary with mocked subprocess only; no DB."""
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import cli_psql_transport as adapter
from review_runner import FILES,Refused
HOST='db.'+adapter.PROJECT+'.supabase.co'
CONFIG={'PGHOST':HOST,'PGPORT':'5432','PGUSER':'cli_login_fixture','PGDATABASE':'postgres'}
SECRET='synthetic-password-never-public'
INSTALL=b'BEGIN; fixture; COMMIT;'
READ=b'BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY; fixture; COMMIT;'

class CliPsqlTransportTest(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory();self.root=Path(self.tmp.name)
  self.psql=self.root/'psql';self.psql.write_bytes(b'fixture-binary')
  self.ca=self.root/'ca.crt';self.ca.write_bytes(b'fixture-public-ca')
  self.artifacts={FILES[1]:adapter._sha(INSTALL),FILES[2]:adapter._sha(READ)}
 def tearDown(self):self.tmp.cleanup()
 def transport(self):return adapter.CliPsqlTransport(CONFIG,SECRET,self.psql,self.ca,self.artifacts,HOST)
 def test_unbound_operator_rejects_before_cli_or_database(self):
  with patch.object(adapter,'_operator_transport') as auth:
   for call in (adapter.install_cli_approved_once,adapter.recover_cli_approved_readonly):
    with self.assertRaisesRegex(Refused,'not_approved'):call()
   auth.assert_not_called()
 def test_fixed_pg_environment_immutable_sql_fresh_psql_and_no_shell(self):
  transport=self.transport()
  with patch.object(adapter.subprocess,'run',side_effect=[subprocess.CompletedProcess([],0,b'',b''),subprocess.CompletedProcess([],0,b'{"read_only":"on"}\n',b'')]) as run:
   transport.execute_install_once(INSTALL);self.assertEqual(json.loads(transport.capture_readonly(READ)),{'read_only':'on'})
   self.assertEqual(run.call_count,2)
   for call,sql in zip(run.call_args_list,(INSTALL,READ)):
    args,kw=call.args,call.kwargs
    self.assertEqual(args[0][0],str(self.psql));self.assertIn('-X',args[0]);self.assertIn('-w',args[0]);self.assertEqual(kw['input'],sql)
    self.assertNotIn(SECRET,str(args));self.assertNotIn('shell',kw);self.assertTrue(kw['close_fds'])
    # subprocess.run receives the env then the adapter removes its secret reference.
    self.assertNotIn('PGPASSWORD',kw['env']);self.assertEqual(kw['env']['PGSSLMODE'],'verify-full');self.assertEqual(kw['env']['PGSSLROOTCERT'],str(self.ca));self.assertIn('search_path=public',kw['env']['PGOPTIONS'])
   self.assertIn('default_transaction_read_only=on',run.call_args_list[1].kwargs['env']['PGOPTIONS'])
   with self.assertRaises(Refused):transport.execute_install_once(INSTALL)
 def test_error_and_timeout_never_echo_secret_or_resend(self):
  for failure in [subprocess.CompletedProcess([],1,b'',SECRET.encode()),subprocess.TimeoutExpired('fixture',45,stderr=SECRET.encode())]:
   transport=self.transport()
   with patch.object(adapter.subprocess,'run',side_effect=failure if isinstance(failure,Exception) else None,return_value=failure) as run:
    with self.assertRaises(ConnectionError) as error:transport.execute_install_once(INSTALL)
    self.assertNotIn(SECRET,str(error.exception))
    with self.assertRaises(Refused):transport.execute_install_once(INSTALL)
    self.assertEqual(run.call_count,1)
 def test_unknown_host_role_artifact_or_changed_ca_refused(self):
  with self.assertRaises(Exception):adapter.CliPsqlTransport({**CONFIG,'PGUSER':'postgres'},SECRET,self.psql,self.ca,self.artifacts,HOST)
  with self.assertRaises(Exception):adapter.CliPsqlTransport(CONFIG,SECRET,self.psql,self.ca,self.artifacts,'other.invalid')
  transport=self.transport();self.ca.write_bytes(b'changed')
  with patch.object(adapter.subprocess,'run') as run:
   with self.assertRaises(Refused):transport.execute_install_once(INSTALL)
   run.assert_not_called()

if __name__=='__main__':unittest.main()
