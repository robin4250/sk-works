"""Pinned original parser + mocked official CLI only. No authentication/DB/socket."""
import contextlib
import io
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import owner_cli_preflight as preflight

PROJECT=preflight.PROJECT
SECRET='synthetic-$()-password-never-public'
USER='cli_login_syntheticsecret.'+PROJECT
HOST='aws-0-ap-northeast-1.pooler.supabase.com'
def script(host=HOST,port='6543',user=USER):
    return '\n'.join(f'export {k}="{v}"' for k,v in {'PGHOST':host,'PGPORT':port,'PGUSER':user,'PGPASSWORD':SECRET,'PGDATABASE':'postgres'}.items())

class OwnerCliPreflightTest(unittest.TestCase):
    def test_original_parser_fixed_project_session_port_no_rendered_script_execution(self):
        cli=preflight.owner_helpers()
        url,password=cli.parse_cli_script(script())
        self.assertEqual(password,SECRET)
        self.assertEqual(cli.capture.endpoint(url,cli_login=True)['PGPORT'],'5432')
        self.assertNotIn(password,url)
        for bad in [script(host='attacker.invalid'),script(user='cli_login_synthetic.otherproject'),script(port='6544'),script()+'\nexport PGHOST="duplicate"',script(user='postgres.'+PROJECT)]:
            with self.assertRaises(Exception):cli.parse_cli_script(bad)

    def test_main_copies_only_sanitized_runtime_and_connection_shape(self):
        with tempfile.TemporaryDirectory() as folder:
            home=Path(folder);backup=home/'SKO-source-backups';backup.mkdir(mode=0o700)
            downloads=home/'Downloads';downloads.mkdir();(downloads/'prod-ca-2021.crt').write_text('synthetic public certificate')
            binaries={}
            for name in ('psql','supabase'):
                path=home/name;path.write_text('synthetic executable '+name);path.chmod(0o700);binaries[name]=str(path)
            calls=[];copied=[]
            def run(args,**kw):
                calls.append((args,kw))
                if args[0]=='/usr/bin/pbcopy':copied.append(kw['input']);return subprocess.CompletedProcess(args,0,'','')
                if '--version' in args:
                    return subprocess.CompletedProcess(args,0,'psql (PostgreSQL) 17.6\n' if Path(args[0]).name=='psql' else '2.120.0\n','')
                if args[0]=='/usr/bin/openssl':return subprocess.CompletedProcess(args,0,b'',b'')
                self.assertEqual(args[:3],['supabase','db','dump']);self.assertIn('--dry-run',args);self.assertIn(PROJECT,args)
                self.assertEqual(kw['stdin'],subprocess.DEVNULL)
                return subprocess.CompletedProcess(args,0,script(),'')
            output=io.StringIO()
            with patch.object(preflight.sys,'platform','darwin'),patch.object(Path,'home',return_value=home),patch.object(preflight.shutil,'which',side_effect=lambda n:binaries.get(n)),patch.object(preflight.subprocess,'run',side_effect=run),contextlib.redirect_stdout(output):
                self.assertEqual(preflight.main(),0)
            public=output.getvalue().strip();self.assertEqual(copied,[public]);value=json.loads(public)
            self.assertTrue(value['verified']);self.assertEqual(value['host'],HOST);self.assertEqual(value['port'],5432)
            self.assertEqual(value['role_kind'],'cli_login_project');self.assertEqual(value['endpoint_kind'],'session_pooler')
            self.assertTrue(value['cli_temporary_role_requested']);self.assertFalse(value['application_data_mutations']);self.assertFalse(value['psql_connected'])
            for secret in (SECRET,USER,'export PG','PGPASSWORD','postgresql://'):self.assertNotIn(secret,public)
            self.assertEqual(value['psql']['sha256'],preflight.digest(Path(binaries['psql'])))
            self.assertTrue(Path(value['durable_root']).is_dir());self.assertEqual(Path(value['durable_root']).stat().st_mode&0o077,0)
            self.assertFalse(any('-c' in args or '-f' in args for args,kw in calls),'No application SQL or script is executed')

    def test_failure_redacts_cli_exception_and_preserves_role_requested_fact(self):
        state={'verified':False}
        output=io.StringIO()
        def fail(value):value.update(cli_temporary_role_requested=True);raise RuntimeError(SECRET)
        with patch.object(preflight,'preflight',side_effect=fail),patch.object(preflight.sys,'platform','darwin'),patch.object(preflight.subprocess,'run') as process,contextlib.redirect_stdout(output):
            self.assertEqual(preflight.main(),1)
        public=output.getvalue();self.assertNotIn(SECRET,public)
        value=json.loads(public);self.assertFalse(value['verified']);self.assertTrue(value['cli_temporary_role_requested'])
        self.assertEqual(process.call_args.args[0],['/usr/bin/pbcopy'])

    def test_changed_original_helper_hash_refuses_before_import(self):
        with tempfile.TemporaryDirectory() as folder:
            source=Path(folder)
            for name in preflight.HELPER_HASHES:(source/(name+'.py')).write_text('changed')
            with patch.object(preflight,'SOURCE',source):
                with self.assertRaisesRegex(preflight.PreflightFailure,'hash_changed'):preflight.owner_helpers()

if __name__=='__main__':unittest.main()
