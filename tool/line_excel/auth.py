"""Interactive password login, memory-only session and local-scope logout."""
import getpass
import math
import re
import sys
import time
import uuid

from sync import Client


def identifier_payload(identifier):
    identifier = identifier.strip()
    if '@' in identifier:
        if not re.fullmatch(r'[^\s@]+@[^\s@]+\.[^\s@]+', identifier):
            raise ValueError('登録済みのメールアドレスを入力してください')
        return {'email': identifier}
    # Match the app's Japanese phone normalization; reject malformed input.
    digits = re.sub(r'\D', '', identifier)
    if identifier.startswith('+') or digits.startswith('81'):
        phone = '+' + digits
    elif digits.startswith('0') and len(digits) >= 10:
        phone = '+81' + digits[1:]
    else:
        phone = '+' + digits
    if not re.fullmatch(r'\+[1-9][0-9]{7,14}', phone):
        raise ValueError('登録済みの電話番号を入力してください')
    return {'phone': phone}


class PasswordSession:
    def __init__(self, base, key, *, transport=None, clock=time.time):
        self.endpoint = Client(base, key, key, transport)
        self.clock = clock
        self.actor_id = None
        self._access = self._refresh = None
        self._expires = 0

    def login(self, identifier, password):
        if not password:
            raise ValueError('パスワードが必要です')
        self.clear()
        payload = {**identifier_payload(identifier), 'password': password}
        try:
            providers = self.endpoint.request('/auth/v1/settings').get('external', {})
            kind = 'email' if 'email' in payload else 'phone'
            if providers.get(kind) is not True:
                raise ValueError('指定したログイン方法はこの接続先で無効です')
            result = self.endpoint.request('/auth/v1/token', params={'grant_type': 'password'}, body=payload)
            self._accept(result)
            # Validate the user against the live Auth endpoint before use.
            if self.client().actor() != self.actor_id:
                raise ValueError('本人確認に失敗しました')
        except Exception:
            self.clear()
            raise
        finally:
            payload.clear()

    def _accept(self, result):
        actor = str(uuid.UUID(result['user']['id']))
        if self.actor_id is not None and actor != self.actor_id:
            raise ValueError('認証更新で利用者が変わりました')
        access, refresh = result.get('access_token'), result.get('refresh_token')
        lifetime = result.get('expires_in')
        if not isinstance(access, str) or not access or not isinstance(refresh, str) or not refresh or not isinstance(lifetime, (int, float)) or not math.isfinite(lifetime) or lifetime <= 30:
            raise ValueError('有効な本人セッションを取得できませんでした')
        Client(self.endpoint.base, self.endpoint.key, access)
        self.actor_id, self._access, self._refresh = actor, access, refresh
        self._expires = self.clock() + lifetime

    def access_token(self):
        if self._access is None:
            raise ValueError('この端末で再ログインしてください')
        if self.clock() >= self._expires - 30:
            try:
                result = self.endpoint.request('/auth/v1/token', params={'grant_type': 'refresh_token'}, body={'refresh_token': self._refresh})
                self._accept(result)
            except Exception:
                self.clear()
                raise
        return self._access

    def client(self):
        session = self
        class SessionClient(Client):
            def request(self, path, params=None, body=None):
                self.token = session.access_token()
                return super().request(path, params, body)
        return SessionClient(self.endpoint.base, self.endpoint.key, self.access_token(), self.endpoint.transport)

    def close(self):
        # Revoke only this new session. Never revoke the user's iPhone session.
        try:
            if self._access:
                client = Client(self.endpoint.base, self.endpoint.key, self._access, self.endpoint.transport)
                client.request('/auth/v1/logout', params={'scope': 'local'}, body={})
        except Exception:
            # A logout outage does not erase a successful local archive.
            print('この取得用セッションの終了をサーバーで確認できませんでした。', file=sys.stderr)
        finally:
            self.clear()

    def clear(self):
        self.actor_id = self._access = self._refresh = None
        self._expires = 0


def interactive_login(base, key):
    if not sys.stdin.isatty() or not sys.stderr.isatty():
        raise ValueError('本人の端末のターミナルで起動してください')
    session = PasswordSession(base, key)
    providers = session.endpoint.request('/auth/v1/settings').get('external', {})
    if providers.get('phone') is True and providers.get('email') is True:
        label = '電話番号またはメールアドレス'
    elif providers.get('email') is True:
        label = '登録済みメールアドレス'
    elif providers.get('phone') is True:
        label = '登録済み電話番号'
    else:
        raise ValueError('この接続先のパスワードログインを利用できません')
    identifier = input('SKOの' + label + ': ')
    password = getpass.getpass('SKOのパスワード（表示・保存しません）: ')
    try:
        session.login(identifier, password)
    finally:
        password = None
        identifier = None
    return session
