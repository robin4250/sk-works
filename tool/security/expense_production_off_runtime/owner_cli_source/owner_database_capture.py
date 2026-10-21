#!/usr/bin/env python3
"""Mac-only database capture. No restore, migration, upload, or source edits."""
import getpass
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
from urllib.parse import parse_qsl, unquote, urlsplit

PROJECT = 'ztktgquxvcxcjxtluspu'


class CaptureFailure(RuntimeError):
    def __init__(self, code):
        self.code = code
        super().__init__(code)


def failure_code(raw):
    value = raw.lower()
    for phrase, code in (
        ('password authentication failed', 'db_password_rejected'),
        ('certificate', 'tls_certificate_failed'),
        ('permission denied', 'database_read_permission_denied'),
        ('tenant or user not found', 'endpoint_user_mismatch'),
        ('could not translate host', 'dns_failed'),
        ('connection refused', 'connection_refused'),
        ('timeout', 'timeout'),
    ):
        if phrase in value:
            return code
    return 'capture_failed'


def endpoint(raw, cli_login=False):
    """Accept only this project's direct endpoint or session pooler."""
    u = urlsplit(raw.strip().replace(':[YOUR-PASSWORD]@', ':@'))
    if u.scheme not in ('postgres', 'postgresql') or u.fragment or u.path != '/postgres':
        raise ValueError('接続形式を確認してください')
    user = unquote(u.username or '')
    direct_user = user == 'postgres' or (cli_login and bool(re.fullmatch(r'cli_login_[a-z0-9_]+', user)))
    pool_user = user == f'postgres.{PROJECT}' or (cli_login and bool(re.fullmatch(r'cli_login_[a-z0-9_]+\.' + PROJECT, user)))
    direct = u.hostname == f'db.{PROJECT}.supabase.co' and direct_user
    pool = bool(re.fullmatch(r'aws-[0-9]+-[a-z0-9-]+\.pooler\.supabase\.com', u.hostname or '')) and pool_user
    if not (direct or pool) or u.port != 5432:
        raise ValueError('対象プロジェクトのDirectまたはSession pooler（5432）を使ってください')
    if any(k != 'sslmode' or v not in ('require', 'verify-full') for k, v in parse_qsl(u.query, keep_blank_values=True)):
        raise ValueError('接続オプションを確認してください')
    return {'PGHOST': u.hostname, 'PGPORT': '5432', 'PGUSER': unquote(u.username), 'PGDATABASE': 'postgres'}


def tool(name):
    executable = shutil.which(name)
    if not executable:
        raise RuntimeError(f'{name}が見つかりません')
    result = subprocess.run([executable, '--version'], capture_output=True, text=True, timeout=10, check=True)
    if not re.search(r'\(PostgreSQL\) 17\.', result.stdout):
        raise RuntimeError(f'{name}はPostgreSQL 17版が必要です')
    return executable


def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


def capture(connection, password, root, certificate=None, cli_login=False):
    config = endpoint(connection, cli_login=cli_login)
    if not password or '\x00' in password:
        raise ValueError('DBパスワードが必要です')
    executables = {name: tool(name) for name in ('pg_dump', 'pg_dumpall', 'pg_restore', 'psql')}
    # Do not inherit libpq service/options/password files or a caller's endpoint.
    env = {k: v for k, v in os.environ.items() if not k.startswith('PG')}
    env.update(config, PGPASSWORD=password, PGSSLMODE='verify-full', PGSSLROOTCERT='system',
               PGCONNECT_TIMEOUT='10', PGOPTIONS='-c default_transaction_read_only=on',
               PGPASSFILE='/dev/null', PGSERVICEFILE='/dev/null')
    if certificate is not None:
        certificate = Path(certificate).expanduser().absolute()
        if certificate.is_symlink() or not certificate.is_file() or certificate.stat().st_size > 1048576:
            raise CaptureFailure('certificate_file_invalid')
        env['PGSSLROOTCERT'] = str(certificate)
    root = root.expanduser()
    if any(p.is_symlink() for p in (root, *root.parents)):
        raise ValueError('保存先のシンボリックリンクは使用できません')
    root.mkdir(mode=0o700, parents=True, exist_ok=True)
    if root.stat().st_mode & 0o077:
        raise ValueError('保存先は本人のみアクセス可能な権限が必要です')
    stage = Path(tempfile.mkdtemp(prefix='database-capture-', dir=root))
    status = {'schema': 1, 'capture_completed': False, 'restore_verified': False,
              'production_mutations': cli_login, 'application_data_mutations': False,
              'cli_temporary_role_requested': cli_login, 'role_passwords_included': False,
              'external_auth_settings_included': False, 'storage_bytes_included': False}
    try:
        with (stage / 'private-errors.log').open('xb') as errors:
            def run(name, arguments, output=subprocess.DEVNULL):
                status['phase'] = name
                return subprocess.run([executables[name], *arguments], env=env, stdin=subprocess.DEVNULL,
                                      stdout=output, stderr=errors, timeout=1800, check=True)
            # The only explicit SQL is a fixed read-only server version query.
            version = run('psql', ['-X', '-w', '-A', '-t', '-v', 'ON_ERROR_STOP=1',
                                  '-c', 'SHOW server_version_num'], subprocess.PIPE).stdout.strip()
            if not version.isdigit() or not 170000 <= int(version) < 180000:
                raise RuntimeError('本番DBのPostgreSQLバージョンが想定と異なります')
            role_flags = ['--role=postgres'] if cli_login else []
            run('pg_dump', [*role_flags, '--no-password', '--format=custom', '--lock-wait-timeout=5s',
                            '--file', str(stage / 'database.dump')])
            run('pg_dumpall', [*role_flags, '--no-password', '--roles-only', '--no-role-passwords',
                               '--file', str(stage / 'roles.sql')])
            # Decode the entire archive to a file sink; never execute its SQL.
            run('pg_restore', ['--file', os.devnull, str(stage / 'database.dump')])
            with (stage / 'archive-list.txt').open('xb') as listing:
                run('pg_restore', ['--list', str(stage / 'database.dump')], listing)
        status.update(capture_completed=True, server_version_num=int(version),
                      files={name: {'bytes': (stage / name).stat().st_size, 'sha256': digest(stage / name)}
                             for name in ('database.dump', 'roles.sql', 'archive-list.txt')})
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
        raw = (stage / 'private-errors.log').read_text(errors='replace')
        code = 'timeout' if isinstance(error, subprocess.TimeoutExpired) else failure_code(raw)
        status['failure_code'] = code
        raise CaptureFailure(code) from None
    finally:
        (stage / 'capture-status.json').write_text(json.dumps(status, ensure_ascii=False, indent=2))
        env.pop('PGPASSWORD', None)
    return stage


def main():
    os.umask(0o077)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--certificate', type=Path, help='Supabase Dashboardから取得したCA証明書')
    args = parser.parse_args()
    stage = None
    try:
        if sys.platform != 'darwin':
            raise RuntimeError('Mac専用です')
        connection = getpass.getpass('接続文字列を貼り付けてEnter（画面非表示）: ')
        endpoint(connection)  # Reject another project before asking for its password.
        password = getpass.getpass('既存のDBパスワード（画面非表示）: ')
        stage = capture(connection, password, Path.home() / 'SKO-source-backups', args.certificate)
        result = f'DB取得・アーカイブ読取成功: {stage.name}。復元検証・Auth設定/Storage実ファイル保全・本番適用は未実施。'
        code = 0
    except (Exception, KeyboardInterrupt) as error:
        # Never echo raw exception text: a driver error may contain connection data.
        result = 'DB取得は完了確認できません。本番変更は行っていません。保存済みファイルを保持しています。'
        if isinstance(error, CaptureFailure):
            messages = {
                'db_password_rejected': 'DBパスワード認証失敗。パスワード不明の場合は再試行せず停止してください。',
                'tls_certificate_failed': 'SSL証明書の検証失敗。DashboardのCA証明書を--certificateで指定してください。',
                'certificate_file_invalid': '証明書ファイルを確認してください。',
                'database_read_permission_denied': 'DBの読取権限不足。',
                'endpoint_user_mismatch': '接続先またはDBユーザーの不一致。',
                'dns_failed': '接続先の名前解決失敗。',
                'connection_refused': '接続拒否。',
                'timeout': '接続または取得のタイムアウト。',
                'capture_failed': 'DB取得処理で失敗。',
            }
            result += ' 原因: ' + messages.get(error.code, '取得失敗。')
        code = 1
    print(result, flush=True)
    if sys.platform == 'darwin':
        subprocess.run(['/usr/bin/pbcopy'], input=result, text=True, check=False)
    return code


if __name__ == '__main__':
    raise SystemExit(main())
