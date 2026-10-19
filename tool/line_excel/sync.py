"""Manual user-scoped read-only export. Credentials are never written to disk."""
import argparse
import datetime as dt
import json
import os
from pathlib import Path
import urllib.parse
import urllib.request
import uuid

from core import SourceStore


class Client:
    def __init__(self, base, key, token, transport=None):
        parsed = urllib.parse.urlsplit(base)
        if parsed.scheme != 'https' or not parsed.hostname or parsed.username or parsed.query or parsed.fragment or parsed.path not in ('', '/'):
            raise ValueError('HTTPSのSKO接続先を指定してください')
        if not key or not token:
            raise ValueError('本人のSKO認証が必要です。認証情報をチャットやExcelに貼らないでください')
        if key.startswith('sb_secret_'):
            raise ValueError('公開キーのみ使用できます')
        # Reject privileged legacy keys as well. Authorization is validated by server.
        import base64
        for credential in (key, token):
            if credential.count('.') == 2:
                try:
                    role = json.loads(base64.urlsafe_b64decode(credential.split('.')[1] + '===')) .get('role')
                except (ValueError, UnicodeError):
                    raise ValueError('認証情報の形式が不正です') from None
                if role in ('service_role', 'supabase_admin', 'postgres'):
                    raise ValueError('管理用秘密キーは使用できません')
        self.base, self.key, self.token = base.rstrip('/'), key, token
        self.transport = transport

    def request(self, path, params=None, body=None):
        if self.transport:
            return self.transport(path, params, body)
        url = self.base + path + ('?' + urllib.parse.urlencode(params) if params else '')
        headers = {'apikey': self.key, 'Content-Type': 'application/json'}
        if path != '/auth/v1/token':
            headers['Authorization'] = 'Bearer ' + self.token
        req = urllib.request.Request(url, data=json.dumps(body).encode() if body is not None else None, headers=headers)
        # Redirects must never forward credentials to a different endpoint.
        class NoRedirect(urllib.request.HTTPRedirectHandler):
            def redirect_request(self, *args, **kwargs):
                return None
        with urllib.request.build_opener(NoRedirect).open(req, timeout=30) as response:
            if response.status == 204:
                return None
            return json.load(response)

    def actor(self):
        user = self.request('/auth/v1/user')
        return str(uuid.UUID(user['id']))

    def groups(self, name):
        groups = self.request('/rest/v1/rpc/line_shared_chat_groups', body={})
        if not isinstance(groups, list):
            raise ValueError('グループ一覧を取得できませんでした')
        return [group for group in groups if name.casefold() in group['name'].casefold()]

    def messages(self, group_id, start, end, page_size=500):
        group_id = str(uuid.UUID(group_id))
        first, last = dt.date.fromisoformat(start), dt.date.fromisoformat(end)
        if first > last or not 1 <= page_size <= 500:
            raise ValueError('取得期間を確認してください')
        actor = self.actor()
        result, offset = [], 0
        while True:
            params = [('select', 'id,communication_group_id,sender_display_name,body,origin,external_message_id,sent_at'),
                      ('communication_group_id', 'eq.' + group_id), ('origin', 'eq.line'),
                      ('sent_at', 'gte.' + first.isoformat() + 'T00:00:00+09:00'),
                      ('sent_at', 'lt.' + (last + dt.timedelta(days=1)).isoformat() + 'T00:00:00+09:00'),
                      ('order', 'sent_at.asc,id.asc'), ('limit', page_size), ('offset', offset)]
            batch = self.request('/rest/v1/chat_messages', params=params)
            if not isinstance(batch, list):
                raise ValueError('メッセージ取得結果が不正です')
            result.extend(batch)
            # Server max_rows may be lower than requested. Continue until empty.
            if not batch:
                break
            offset += len(batch)
            if offset > 100000:
                raise ValueError('件数上限です。期間を狭めてください')
        if self.actor() != actor:
            raise ValueError('ログインが変わりました。保存せず再認証してください')
        return result


def main():
    os.umask(0o077)
    parser = argparse.ArgumentParser()
    parser.add_argument('--url', required=True)
    parser.add_argument('--group', required=True)
    parser.add_argument('--group-id')
    parser.add_argument('--from-date', default='2026-10-16')
    parser.add_argument('--to-date', default=dt.datetime.now(dt.timezone(dt.timedelta(hours=9))).date().isoformat())
    parser.add_argument('--output', default='原文')
    parser.add_argument('--login', action='store_true', help='この端末で本人ログイン（認証情報は保存しない）')
    args = parser.parse_args()
    session = None
    if args.login:
        from auth import interactive_login
        session = interactive_login(args.url, os.getenv('SKO_ANON_KEY'))
        client = session.client()
    else:
        client = Client(args.url, os.getenv('SKO_ANON_KEY'), os.getenv('SKO_ACCESS_TOKEN'))
    try:
        return perform_sync(client, args)
    finally:
        if session is not None:
            session.close()


def perform_sync(client, args):
    # A selected ID can have a different SKO display name from its LINE source.
    # Still resolve it through the user-scoped RPC, never through an admin read.
    groups = client.groups('' if args.group_id else args.group)
    if args.group_id:
        groups = [group for group in groups if group['group_id'] == args.group_id]
    if len(groups) != 1:
        print(json.dumps({'status': 'グループを選択してください', 'groups': groups}, ensure_ascii=False))
        return 2
    group = groups[0]
    messages = client.messages(group['group_id'], args.from_date, args.to_date)
    output = Path(args.output)
    output.mkdir(parents=True, exist_ok=True)
    output.chmod(0o700)
    db_path = output / 'sources.sqlite3'
    store = SourceStore(db_path)
    report = store.import_messages(group['group_id'], messages)
    store.db.close()
    db_path.chmod(0o600)
    print(json.dumps({**report, 'status': '原文保存・集計未確定', 'updated_at': dt.datetime.now(dt.timezone.utc).isoformat()}, ensure_ascii=False))
    return 0


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except (ValueError, KeyError, urllib.error.URLError):
        raise SystemExit('更新できませんでした。取得期間・本人認証・閲覧権限を確認してください。原文の取得完了とは扱いません。') from None
