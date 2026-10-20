import contextlib
import io
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import owner_database_restore as restore


class RestoreTests(unittest.TestCase):
    def test_bootstrap_role_keeps_original_grantors_and_attributes(self):
        original = 'CREATE ROLE supabase_admin;\nALTER ROLE supabase_admin SUPERUSER;\nCREATE ROLE test;\nGRANT test TO postgres GRANTED BY supabase_admin;\n'
        result = restore.restore_roles_sql(original)
        self.assertNotIn('CREATE ROLE supabase_admin;', result)
        self.assertIn('ALTER ROLE supabase_admin SUPERUSER;', result)
        self.assertIn('GRANT test TO postgres GRANTED BY supabase_admin;', result)
        self.assertEqual(original.count('CREATE ROLE supabase_admin;'), 1)
        for invalid in ('CREATE ROLE other;', original + 'CREATE ROLE supabase_admin;\n'):
            with self.assertRaises(RuntimeError): restore.restore_roles_sql(invalid)

    def test_copy_counts_empty_quoted_and_escaped_rows(self):
        sql = 'COPY public.test (id) FROM stdin;\nfirst\\nsecond\n\\\\.\n\\.\nCOPY "odd.schema"."table" (id) FROM stdin;\n\\.\n'
        self.assertEqual(restore.expected_rows(sql), {'public.test':2, '"odd.schema"."table"':0})
        for invalid in ('COPY broken;\n', 'COPY public.test (id) FROM stdin;\n1\n', 'no data'):
            with self.assertRaises(RuntimeError):
                restore.expected_rows(invalid)

    def test_container_no_network_ports_credentials_or_writable_backup(self):
        command = restore.container_command('fixture', Path('/private/backup'), 'synthetic_admin')
        self.assertIn('--network=none', command)
        self.assertIn('--user=postgres', command)
        self.assertIn('type=bind,source=/private/backup,target=/backup,readonly', command)
        self.assertIn(restore.IMAGE, command)
        self.assertIn('cron.launch_active_jobs=off', ' '.join(command))
        for forbidden in ('--publish', '--privileged', '--network=host', 'PGPASSWORD', 'SUPABASE_ACCESS_TOKEN'):
            self.assertNotIn(forbidden, ' '.join(command))

    def lifecycle(self, fail_restore=False, corrupt=False):
        with tempfile.TemporaryDirectory() as folder:
            home = Path(folder)
            root = home/'SKO-source-backups'; root.mkdir(mode=0o700)
            backup = root/restore.CAPTURE; backup.mkdir(mode=0o700)
            files = {}
            for name in ('database.dump','roles.sql','archive-list.txt'):
                path=backup/name; path.write_text('CREATE ROLE supabase_admin;\n' if name=='roles.sql' else 'synthetic fixture')
                files[name]={'bytes':path.stat().st_size,'sha256':restore.digest(path)}
            (backup/'capture-status.json').write_text(json.dumps({'capture_completed':True,'files':files}))
            if corrupt: (backup/'database.dump').write_text('changed')
            calls=[]
            def run(command, **kwargs):
                if command==['/usr/bin/pbcopy']:
                    self.assertIsInstance(kwargs['input'],str)
                    return subprocess.CompletedProcess(command,0,b'')
                calls.append(command)
                self.assertIsInstance(command,list)
                self.assertNotIn('shell',kwargs)
                output=b''
                if command[:3]==['docker','context','inspect']:
                    output=json.dumps([{'Endpoints':{'docker':{'Host':'unix:///synthetic.sock'}}}]).encode()
                if command[:2]==['docker','inspect']:
                    output=json.dumps([{'HostConfig':{'NetworkMode':'none','PortBindings':{}},'Mounts':[{'Destination':'/backup','RW':False}]}]).encode()
                if 'psql' in command and kwargs.get('input')==b'SHOW cron.launch_active_jobs;': output=b'off\n'
                if 'pg_restore' in command:
                    if '--exit-on-error' in command:
                        self.assertIn('--single-transaction',command)
                        if fail_restore: raise subprocess.CalledProcessError(1,command)
                    else: output=b'COPY public.test (id) FROM stdin;\n1\n\\.\n'
                if 'psql' in command and (kwargs.get('input') or b'').startswith(b'SELECT count'):
                    output=b'1\n'
                return subprocess.CompletedProcess(command,0,output)
            with patch.object(restore.sys,'platform','darwin'),patch.object(restore.Path,'home',return_value=home),patch.dict(restore.os.environ,{},clear=True),patch.object(restore.subprocess,'run',side_effect=run),contextlib.redirect_stdout(io.StringIO()):
                code=restore.main()
            statuses=list(root.glob('database-restore-*/rehearsal-status.json'))
            status=json.loads(statuses[0].read_text()) if statuses else None
            return code,status,calls

    def test_success_verifies_rows_and_stops_without_touching_capture(self):
        code,status,calls=self.lifecycle()
        self.assertEqual(code,0)
        self.assertTrue(status['archive_restore_verified'])
        self.assertTrue(status['source_backup_unchanged'])
        self.assertTrue(status['container_stopped'])
        self.assertFalse(status['production_connected'])
        self.assertEqual(status['verified_tables'],1)
        self.assertFalse(status['auth_login_verified'])

    def test_restore_error_never_marked_success_and_stops_container(self):
        code,status,calls=self.lifecycle(fail_restore=True)
        self.assertEqual(code,1)
        self.assertFalse(status['archive_restore_verified'])
        self.assertTrue(status['container_stopped'])
        self.assertEqual(status['phase'],'archive')

    def test_hash_mismatch_prevents_all_docker_calls(self):
        code,status,calls=self.lifecycle(corrupt=True)
        self.assertEqual(code,1)
        self.assertIsNone(status)
        self.assertEqual(calls,[])


if __name__=='__main__': unittest.main()
