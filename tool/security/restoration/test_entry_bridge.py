import importlib.util
from pathlib import Path
import types
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('bridge', Path(__file__).with_name('entry_bridge.py'))
bridge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bridge)


class EntryTests(unittest.TestCase):
    def test_source_mismatch_rejected_before_import(self):
        with tempfile.TemporaryDirectory() as td:
            path = Path(td) / 'collect_private_capsule.py'
            marker = Path(td) / 'executed'
            path.write_text('from pathlib import Path\nPath(' + repr(str(marker)) + ').touch()\n')
            with self.assertRaisesRegex(ValueError, '^reviewed collection source mismatch$'):
                bridge.load_collector(path)
            self.assertFalse(marker.exists())

    def module(self, host):
        return types.SimpleNamespace(PROJECT='example', parse_plan=lambda text:
            dict(PGHOST=host, PGUSER='cli_login_postgres.example', PGPASSWORD='old',
                 PGDATABASE='postgres', PGPORT='5432'))

    def test_direct_and_pool_use_existing_postgres_only(self):
        for host, user in [('db.example.supabase.co', 'postgres'),
                           ('aws-0-region.pooler.supabase.com', 'postgres.example')]:
            module = self.module(host)
            bridge.bind_entry(module, lambda _: 'local-only-secret', True)
            result = module.parse_plan('ignored')
            self.assertEqual(result['PGUSER'], user)
            self.assertEqual(result['PGPASSWORD'], 'local-only-secret')
            self.assertEqual(result['PGHOST'], host)

    def test_validation_before_prompt(self):
        module = self.module('untrusted')
        def deny(_):
            raise ValueError('project mismatch')
        module.parse_plan = deny
        bridge.bind_entry(module, lambda _: self.fail('secret requested'), True)
        with self.assertRaises(ValueError):
            module.parse_plan('invalid')

    def test_no_redirected_secret_entry(self):
        module = self.module('db.example.supabase.co')
        bridge.bind_entry(module, lambda _: self.fail('prompt used'), False)
        with self.assertRaises(ValueError):
            module.parse_plan('valid')

    def test_bad_secret_not_reflected_in_exception(self):
        for secret in ['', 'private\nvalue', '\x00']:
            module = self.module('db.example.supabase.co')
            bridge.bind_entry(module, lambda _: secret, True)
            with self.assertRaisesRegex(ValueError, '^invalid secret input$'):
                module.parse_plan('valid')


if __name__ == '__main__':
    unittest.main()
