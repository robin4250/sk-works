import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SOURCE = Path(__file__).with_name('verify_local_capsule.py')
spec = importlib.util.spec_from_file_location('capsule', SOURCE)
capsule = importlib.util.module_from_spec(spec)
spec.loader.exec_module(capsule)


class OfflineBoundaryTests(unittest.TestCase):
    def test_table_data_is_not_a_table_definition(self):
        text = ('1; 1259 42 TABLE public company_members postgres\n'
                '2; 3079 43 EXTENSION - pgcrypto postgres\n'
                '3; 0 42 TABLE DATA public company_members postgres')
        self.assertEqual(capsule.inventory(text),
                         ({('public', 'company_members')}, {'pgcrypto'}))

    def test_ambiguous_table_records_stop_before_presence_claim(self):
        for suffix in ('users backup postgres', 'users  postgres',
                       'users postgres ', 'users role name', 'users "postgres"'):
            with self.subTest(suffix=suffix), self.assertRaises(ValueError):
                capsule.inventory('1; 1259 42 TABLE auth ' + suffix)

    def test_duplicate_ids_and_table_roots_stop(self):
        records = ('1; 1259 42 TABLE auth users postgres',
                   '1; 1259 43 TABLE auth identities postgres')
        for duplicate in (records[1], records[1].replace('1;', '01;', 1)):
            with self.subTest(record=duplicate), self.assertRaises(ValueError):
                capsule.inventory(records[0] + '\n' + duplicate)
        with self.assertRaises(ValueError):
            capsule.inventory(records[0] + '\n2; 1259 42 TABLE auth users postgres')

    def test_all_protected_roots_and_extensions_preserve_inventory_api(self):
        text = '\n'.join(f'{i}; 1259 {i+100} TABLE {schema} {name} postgres'
                         for i, (schema, name) in enumerate(sorted(capsule.REQUIRED), 1))
        tables, extensions = capsule.inventory(text + '\n99; 3079 44 EXTENSION - pgcrypto postgres')
        self.assertEqual(tables, capsule.REQUIRED)
        self.assertEqual(extensions, {'pgcrypto'})

    def test_private_inventory_never_connects_or_changes_archive(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            archive = root / 'database.dump'
            archive.write_bytes(b'PGDMPsynthetic-only')
            tools = root / 'bin'
            tools.mkdir()
            binary = tools / 'pg_restore'
            binary.write_text('#!' + sys.executable + '''
import os, pathlib, sys
assert not any(k.upper().startswith('PG') for k in os.environ)
a=sys.argv
if '--version' in a:
    print('pg_restore (PostgreSQL) 17.11')
elif '--list' in a:
    print('1; 1259 42 TABLE public company_members postgres')
elif '--schema-only' in a and '--file' in a:
    pathlib.Path(a[a.index('--file')+1]).write_text('SYNTHETIC-PRIVATE-SENTINEL')
else:
    raise SystemExit('unexpected command')
''')
            binary.chmod(0o700)
            environment = dict(os.environ, PGHOST='must-not-survive',
                               PGPASSWORD='SYNTHETIC-PRIVATE-SENTINEL')
            result = subprocess.run([sys.executable, str(SOURCE), '--archive',
                                     str(archive), '--pg-bin', str(tools)],
                                    env=environment, capture_output=True, text=True)
            self.assertEqual(result.returncode, 2)
            self.assertNotIn('SYNTHETIC-PRIVATE-SENTINEL', result.stdout + result.stderr)
            self.assertEqual(archive.read_bytes(), b'PGDMPsynthetic-only')
            evidence = Path(result.stdout.split('Private evidence: ')[1].strip())
            self.assertEqual(evidence.stat().st_mode & 0o777, 0o700)
            self.assertEqual((evidence / 'private-schema.sql').read_text(),
                             'SYNTHETIC-PRIVATE-SENTINEL')
            self.assertIn('NOT performed', result.stdout)
            link = root / 'linked.dump'
            link.symlink_to(archive)
            refused = subprocess.run([sys.executable, str(SOURCE), '--archive',
                                      str(link), '--pg-bin', str(tools)],
                                     capture_output=True, text=True)
            self.assertEqual(refused.returncode, 1)


if __name__ == '__main__':
    unittest.main()
