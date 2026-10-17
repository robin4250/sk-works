import base64
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import urllib.error

spec = importlib.util.spec_from_file_location('snapshot', Path(__file__).with_name('entry_snapshot.py'))
snapshot = importlib.util.module_from_spec(spec)
spec.loader.exec_module(snapshot)
TOKEN = 'sbp_' + 'a' * 40


class Response:
    status = 201
    def __init__(self, readonly=True):
        self.data = json.dumps([{'entry_payload': {'read_only': readonly, 'payload': {'synthetic': 1}}}]).encode()
    def __enter__(self): return self
    def __exit__(self, *args): pass
    def read(self, size): return self.data[:size]


class SnapshotTests(unittest.TestCase):
    def test_keychain_timeout_is_classified_before_api_without_fallback(self):
        calls = []
        def run(args, **kwargs):
            calls.append(args)
            self.assertEqual(kwargs['timeout'], 120)
            raise subprocess.TimeoutExpired(args, 120, output=TOKEN, stderr=TOKEN)
        out = io.StringIO()
        with tempfile.TemporaryDirectory() as td, contextlib.redirect_stdout(out):
            with self.assertRaises(snapshot.Stop) as caught:
                snapshot.token_from_store({}, run, Path(td))
        self.assertEqual(caught.exception.category, 'credential_store_timeout_before_api')
        self.assertEqual(len(calls), 1)
        self.assertNotIn(TOKEN, out.getvalue() + str(caught.exception))
        self.assertIn('120', out.getvalue())

    def test_reviewed_fixed_sql_read_only_evidence_and_schema_qualification(self):
        module, invariants, catalog = snapshot.reviewed_queries(Path(__file__).parent)
        for sql in (invariants, catalog):
            self.assertTrue(sql.startswith('SELECT pg_catalog.jsonb_build_object'))
            self.assertIn("pg_catalog.current_setting('transaction_read_only')='on'", sql)
            self.assertNotRegex(sql.lower(), r'\b(insert|update|delete|alter|create|grant|revoke|truncate|set\s+role)\b')
        self.assertIn('FROM private.master_admins', invariants)
        self.assertIn('FROM pg_catalog.pg_auth_members', catalog)
        self.assertIn("'pg_catalog.pg_class'::regclass", catalog)
        self.assertEqual(module.PROJECT, snapshot.PROJECT)

    def test_default_has_zero_secret_or_network_access(self):
        with patch.object(sys, 'argv', ['snapshot']), patch.object(snapshot, 'token_from_store') as token, patch.object(snapshot, 'make_opener') as network, contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(snapshot.main(), 2)
        token.assert_not_called()
        network.assert_not_called()

    def test_env_and_keychain_order_no_value_in_command(self):
        with tempfile.TemporaryDirectory() as td:
            home = Path(td)
            def forbidden(*args, **kwargs): self.fail('keychain must not run')
            self.assertEqual(snapshot.token_from_store({'SUPABASE_ACCESS_TOKEN': TOKEN}, forbidden, home), TOKEN)
            calls = []
            def run(args, **kwargs):
                calls.append(args)
                if '-a' in args and args[args.index('-a') + 1] == 'supabase':
                    return subprocess.CompletedProcess(args, 44, '', '')
                return subprocess.CompletedProcess(args, 0, 'go-keyring-base64:' + base64.b64encode(TOKEN.encode()).decode(), '')
            self.assertEqual(snapshot.token_from_store({}, run, home), TOKEN)
            self.assertEqual([x[x.index('-a')+1] for x in calls], ['supabase', 'access-token'])
            self.assertNotIn(TOKEN, repr(calls))

    def test_profile_and_invalid_secret_do_not_fallback(self):
        for env in ({'SUPABASE_PROFILE': 'custom'}, {'SUPABASE_ACCESS_TOKEN': 'private-invalid'}):
            with self.subTest(env=env), self.assertRaises(snapshot.Stop):
                snapshot.token_from_store(env, lambda *a, **k: self.fail('must not probe'), Path('/tmp/none'))

    def test_keychain_denial_is_not_retried(self):
        calls = []
        def run(args, **kwargs):
            calls.append(args)
            return subprocess.CompletedProcess(args, 1, '', TOKEN)
        with tempfile.TemporaryDirectory() as td, self.assertRaises(snapshot.Stop):
            snapshot.token_from_store({}, run, Path(td))
        self.assertEqual(len(calls), 1)

    def test_fixed_https_read_only_endpoint_and_strict_evidence(self):
        for value in (True, False, 'true', 1, None):
            class Opener:
                def open(self, request, timeout):
                    self_outer.assertEqual(request.full_url, snapshot.URL)
                    self_outer.assertTrue(request.full_url.endswith('/database/query/read-only'))
                    self_outer.assertEqual(request.method, 'POST')
                    self_outer.assertEqual(timeout, 45)
                    self_outer.assertEqual(json.loads(request.data), {'query': 'fixed'})
                    return Response(value)
            self_outer = self
            if value is True:
                self.assertTrue(snapshot.read_query(Opener(), TOKEN, 'fixed')['read_only'])
            else:
                with self.assertRaises(snapshot.Stop): snapshot.read_query(Opener(), TOKEN, 'fixed')

    def test_status_only_no_response_or_secret_reflection_no_retry(self):
        class Opener:
            calls = 0
            def open(self, request, timeout):
                self.calls += 1
                raise urllib.error.HTTPError(snapshot.URL, 403, TOKEN, {}, io.BytesIO(TOKEN.encode()))
        opener = Opener()
        with self.assertRaises(snapshot.Stop) as caught:
            snapshot.read_query(opener, TOKEN, 'fixed')
        self.assertEqual(caught.exception.status, 403)
        self.assertNotIn(TOKEN, str(caught.exception))
        self.assertEqual(opener.calls, 1)

    def test_redirect_refused(self):
        with self.assertRaises(snapshot.Stop):
            snapshot.NoRedirect().redirect_request(None, None, 302, TOKEN, {}, 'https://attacker.invalid')

    def test_unsafe_token_file_rejected(self):
        with tempfile.TemporaryDirectory() as td:
            home = Path(td); state = home / '.supabase'; state.mkdir()
            p = state / 'access-token'; p.write_text(TOKEN); p.chmod(0o644)
            with self.assertRaises(snapshot.Stop): snapshot.token_from_store({'SUPABASE_NO_KEYRING':'1'}, home=home)
            p.chmod(0o600)
            self.assertEqual(snapshot.token_from_store({'SUPABASE_NO_KEYRING':'1'}, home=home), TOKEN)


if __name__ == '__main__':
    unittest.main()
