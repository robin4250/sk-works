import contextlib
import io
import json
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'tool' / 'line_excel'))
from auth import PasswordSession, identifier_payload, interactive_login
from sync import Client

ACTOR = '00000000-0000-4000-8000-000000000001'
OTHER = '00000000-0000-4000-8000-000000000002'


class AuthTest(unittest.TestCase):
    def fixture(self):
        now = [1000]
        calls = []
        state = {'actor': ACTOR, 'refresh_actor': ACTOR}
        def transport(path, params, body):
            calls.append((path, params, json.loads(json.dumps(body))))
            if path.endswith('/settings'):
                return {'external': {'phone': True, 'email': True}}
            if path.endswith('/token'):
                refreshed = params['grant_type'] == 'refresh_token'
                return {'user': {'id': state['refresh_actor'] if refreshed else ACTOR}, 'access_token': 'new-token' if refreshed else 'first-token', 'refresh_token': 'new-refresh' if refreshed else 'first-refresh', 'expires_in': 3600}
            if path.endswith('/user'):
                return {'id': state['actor']}
            return None
        return PasswordSession('https://example.supabase.co', 'sb_publishable_test', transport=transport, clock=lambda: now[0]), now, calls, state

    def test_phone_matches_app_and_email(self):
        for raw in ['090-1234-5678', '+81 90 1234 5678', '819012345678']:
            self.assertEqual(identifier_payload(raw), {'phone': '+819012345678'})
        self.assertEqual(identifier_payload(' user@example.com '), {'email': 'user@example.com'})
        for value in ['', 'abc', '0', 'user@@example.com']:
            with self.assertRaises(ValueError):
                identifier_payload(value)

    def test_login_refresh_and_local_logout(self):
        session, now, calls, state = self.fixture()
        session.login('09012345678', 'private-password')
        self.assertEqual(session.access_token(), 'first-token')
        self.assertEqual(calls[1][2], {'phone': '+819012345678', 'password': 'private-password'})
        self.assertEqual(calls[2][0], '/auth/v1/user')
        now[0] += 3580
        self.assertEqual(session.access_token(), 'new-token')
        refresh = [c for c in calls if c[1] == {'grant_type': 'refresh_token'}]
        self.assertEqual(len(refresh), 1)
        self.assertEqual(refresh[0][2], {'refresh_token': 'first-refresh'})
        session.close()
        self.assertEqual(calls[-1][:2], ('/auth/v1/logout', {'scope': 'local'}))
        self.assertIsNone(session._access)
        self.assertIsNone(session._refresh)

    def test_refresh_rejects_other_actor_and_clears(self):
        session, now, calls, state = self.fixture()
        session.login('user@example.com', 'password')
        state['refresh_actor'] = OTHER
        now[0] += 3580
        with self.assertRaises(ValueError):
            session.access_token()
        self.assertIsNone(session._access)
        self.assertIsNone(session._refresh)

    def test_remote_actor_validation_failure(self):
        session, now, calls, state = self.fixture()
        state['actor'] = OTHER
        with self.assertRaises(ValueError):
            session.login('user@example.com', 'password')
        self.assertIsNone(session._access)

    def test_outage_does_not_log_secrets(self):
        session, now, calls, state = self.fixture()
        session.login('user@example.com', 'password')
        def unavailable(*args):
            raise OSError('sensitive-token-server-error')
        session.endpoint.transport = unavailable
        captured = io.StringIO()
        with contextlib.redirect_stderr(captured):
            session.close()
        self.assertNotIn('sensitive-token', captured.getvalue())
        self.assertIsNone(session._access)

    def test_password_prompt_requires_real_tty(self):
        with patch('sys.stdin.isatty', return_value=False), patch('getpass.getpass') as password:
            with self.assertRaises(ValueError):
                interactive_login('https://example.supabase.co', 'public')
            password.assert_not_called()

    def test_disabled_phone_never_sends_password(self):
        calls = []
        def transport(path, params, body):
            calls.append((path, body))
            return {'external': {'email': True, 'phone': False}}
        session = PasswordSession('https://example.supabase.co', 'public', transport=transport)
        with self.assertRaises(ValueError):
            session.login('09012345678', 'private-password')
        self.assertEqual(calls, [('/auth/v1/settings', None)])
        self.assertIsNone(session._access)

    def test_http_204_and_no_auth_header_for_password_exchange(self):
        captured = []
        class Response:
            status = 204
            def __enter__(self): return self
            def __exit__(self, *args): pass
        class Opener:
            def open(self, request, timeout):
                captured.append(request)
                return Response()
        with patch('urllib.request.build_opener', return_value=Opener()):
            client = Client('https://example.supabase.co', 'public', 'token')
            self.assertIsNone(client.request('/auth/v1/logout', params={'scope': 'local'}, body={}))
            client.request('/auth/v1/token', params={'grant_type': 'password'}, body={'email': 'test@example.com', 'password': 'password'})
            client.request('/auth/v1/settings')
        self.assertEqual(captured[0].get_header('Authorization'), 'Bearer token')
        self.assertIsNone(captured[1].get_header('Authorization'))
        self.assertEqual(captured[1].get_header('Apikey'), 'public')
        self.assertIsNone(captured[2].get_header('Authorization'))


if __name__ == '__main__':
    unittest.main()
