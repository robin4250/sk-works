import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SOURCE = Path(__file__).with_name('collect_private_capsule.py')
spec = importlib.util.spec_from_file_location('collector', SOURCE)
collector = importlib.util.module_from_spec(spec)
spec.loader.exec_module(collector)


class ReadOnlyCollectionTests(unittest.TestCase):
    def plan(self):
        return ('export PGHOST=db.ztktgquxvcxcjxtluspu.supabase.co\n'
                'export PGPORT=5432\nexport PGDATABASE=postgres\n'
                'export PGUSER=postgres\nexport PGPASSWORD=SYNTHETIC-PRIVATE\n')

    def test_no_evaluation_or_wrong_project(self):
        self.assertEqual(len(collector.parse_plan(self.plan())), 5)
        with self.assertRaises(ValueError):
            collector.parse_plan(self.plan().replace('SYNTHETIC-PRIVATE', '$(evil)'))
        with self.assertRaises(ValueError):
            collector.parse_plan(self.plan().replace('ztktgquxvcxcjxtluspu', 'other'))

    def test_libpq_database_expansion_and_unreviewed_users_denied(self):
        for database in ('postgresql://user@attacker/db', 'host=attacker dbname=postgres',
                         'postgres sslmode=disable', ' postgres', 'postgres\t'):
            with self.subTest(database=database):
                plan = self.plan().replace('PGDATABASE=postgres', 'PGDATABASE=' + repr(database))
                with self.assertRaises(ValueError):
                    collector.parse_plan(plan)
        for user in ('other', 'postgres.admin', 'postgres host=attacker', 'cli_login_arbitrary'):
            with self.subTest(user=user), self.assertRaises(ValueError):
                collector.parse_plan(self.plan().replace('PGUSER=postgres', 'PGUSER=' + repr(user)))
        pool = self.plan().replace('db.ztktgquxvcxcjxtluspu.supabase.co',
                                   'aws-0-ap-northeast-1.pooler.supabase.com')
        for user in ('postgres.ztktgquxvcxcjxtluspu', 'cli_login_postgres.ztktgquxvcxcjxtluspu'):
            self.assertEqual(collector.parse_plan(pool.replace('PGUSER=postgres', 'PGUSER=' + user))['PGUSER'], user)
        with self.assertRaises(ValueError):
            collector.parse_plan(pool.replace('PGUSER=postgres', 'PGUSER=evil.ztktgquxvcxcjxtluspu'))

    def test_read_only_and_no_public_private_values(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            plan = root / 'plan'
            plan.write_text(self.plan())
            plan.chmod(0o600)
            for name in ('psql', 'pg_dump'):
                tool = root / name
                tool.write_text('#!' + sys.executable + '''
import os, pathlib, sys, json
a=sys.argv
assert os.environ['PGSSLMODE']=='require'
assert 'default_transaction_read_only=on' in os.environ['PGOPTIONS']
assert os.environ['PGPASSWORD']=='SYNTHETIC-PRIVATE'
if '--version' in a:
 print('PostgreSQL 17.11')
elif pathlib.Path(a[0]).name=='psql':
 assert '-w' in a and '-X' in a and 'ON_ERROR_STOP=1' in a
 sql=a[a.index('-c')+1]
 assert sql.startswith('BEGIN READ ONLY;') and sql.endswith('COMMIT;')
 assert "SET LOCAL statement_timeout='45s'" in sql
 print('t');print(json.dumps({'private':'SYNTHETIC-PRIVATE'}))
else:
 assert '--schema-only' in a and '--no-password' in a
 pathlib.Path(a[a.index('--file')+1]).write_bytes(b'SYNTHETIC-PRIVATE')
''')
                tool.chmod(0o700)
            result = subprocess.run([sys.executable, str(SOURCE), '--plan', str(plan),
                                     '--pg-bin', str(root), '--output-parent', str(root / 'backups')], capture_output=True, text=True)
            self.assertEqual(result.returncode, 2)
            self.assertNotIn('SYNTHETIC-PRIVATE', result.stdout + result.stderr)
            evidence = Path(result.stdout.split('Private evidence: ')[1].strip())
            manifest = json.loads((evidence / 'private-manifest.json').read_text())
            self.assertTrue(manifest['read_only_identity_membership_comparison'])
            self.assertFalse(manifest['restoration_verified'])
            self.assertFalse(manifest['same_database_snapshot_across_files'])
            self.assertEqual(plan.read_text(), self.plan())

    def test_output_parent_permissions_and_symlink_preserved(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            unsafe = root / 'unsafe'
            unsafe.mkdir(mode=0o777)
            unsafe.chmod(0o777)
            with self.assertRaises(ValueError):
                collector.new_capsule_directory(unsafe)
            self.assertEqual(unsafe.stat().st_mode & 0o777, 0o777)
            link = root / 'link'
            link.symlink_to(unsafe, target_is_directory=True)
            with self.assertRaises(ValueError):
                collector.new_capsule_directory(link)
            parent = root / 'backups'
            first = collector.new_capsule_directory(parent)
            second = collector.new_capsule_directory(parent)
            self.assertNotEqual(first, second)
            self.assertEqual(first.stat().st_mode & 0o777, 0o700)


if __name__ == '__main__':
    unittest.main()
