#!/usr/bin/env python3
"""Use the signed-in Supabase CLI, then native PG17; never execute its rendered script."""
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
from urllib.parse import quote

import owner_database_capture as capture


def parse_cli_script(script):
    values = {}
    for line in script.splitlines():
        match = re.fullmatch(r'export (PGHOST|PGPORT|PGUSER|PGPASSWORD|PGDATABASE)="(.*)"', line)
        if match:
            key, value = match.groups()
            if key in values:
                raise capture.CaptureFailure('cli_output_invalid')
            values[key] = value.replace('\\"', '"')
    if set(values) != {'PGHOST', 'PGPORT', 'PGUSER', 'PGPASSWORD', 'PGDATABASE'}:
        raise capture.CaptureFailure('cli_output_invalid')
    if not values['PGPASSWORD'] or any('\x00' in v for v in values.values()):
        raise capture.CaptureFailure('cli_output_invalid')
    # Supavisor's API URL can name transaction mode. Native pg_dump uses its
    # session listener on the SAME validated shared host, never transaction mode.
    host = values['PGHOST']
    shared = bool(re.fullmatch(r'aws-[0-9]+-[a-z0-9-]+\.pooler\.supabase\.com', host))
    if values['PGPORT'] == '6543' and shared:
        values['PGPORT'] = '5432'
    if values['PGDATABASE'] != 'postgres':
        raise capture.CaptureFailure('cli_output_invalid')
    url = f"postgresql://{quote(values['PGUSER'], safe='')}@{host}:{values['PGPORT']}/postgres"
    config = capture.endpoint(url, cli_login=True)
    if not config['PGUSER'].startswith('cli_login_'):
        raise capture.CaptureFailure('cli_output_invalid')
    return url, values['PGPASSWORD']


def obtain_connection(workdir):
    env = {k: v for k, v in os.environ.items()
           if not k.startswith('PG') and k not in ('SUPABASE_DB_PASSWORD', 'DB_PASSWORD')}
    env['SUPABASE_DB_PASSWORD'] = ''
    # No project .env/config/cache is read or changed. CLI handles its existing
    # account authentication; we never open token files or the OS keychain.
    result = subprocess.run(
        ['supabase', 'db', 'dump', '--linked', '--project-ref', capture.PROJECT,
         '--dry-run', '--workdir', str(workdir)],
        stdin=subprocess.DEVNULL, capture_output=True, text=True, env=env, timeout=120,
    )
    if result.returncode:
        raise capture.CaptureFailure('cli_connection_failed')
    return parse_cli_script(result.stdout)


def main():
    os.umask(0o077)
    try:
        if sys.platform != 'darwin':
            raise capture.CaptureFailure('mac_required')
        certificate = Path.home() / 'Downloads' / 'prod-ca-2021.crt'
        if not certificate.is_file() or certificate.is_symlink():
            raise capture.CaptureFailure('certificate_file_invalid')
        for name in ('psql', 'pg_dump', 'pg_dumpall', 'pg_restore'):
            capture.tool(name)
        version = subprocess.run(['supabase', '--version'], capture_output=True, text=True, check=True, timeout=15)
        if version.stdout.strip() != '2.120.0':
            raise capture.CaptureFailure('cli_version_changed')
        print('CLIの既存ログインで一時接続を準備しています。DBパスワード入力は不要です。', flush=True)
        # The official CLI may create a temporary DB login role and clear its
        # own network ban during setup. It does not reset the postgres password.
        with tempfile.TemporaryDirectory(prefix='sko-cli-capture-') as folder:
            workdir = Path(folder)
            (workdir / 'supabase').mkdir(mode=0o700)
            (workdir / 'supabase' / 'config.toml').write_text('project_id = "sko-private-capture"\n[db]\nmajor_version = 17\n')
            url, password = obtain_connection(workdir)
            print('一時接続情報を取得しました。証明書を検証してDBを読み取り保存します。', flush=True)
            try:
                stage = capture.capture(url, password, Path.home() / 'SKO-source-backups', certificate, cli_login=True)
            finally:
                password = None
        result = f'DB取得・アーカイブ読取成功: {stage.name}。隔離復元・Auth設定・Storage実ファイル保全は未実施。一時DB接続ロールを使用。アプリデータ変更なし。'
        code = 0
    except (Exception, KeyboardInterrupt) as error:
        reason = error.code if isinstance(error, capture.CaptureFailure) else 'capture_failed'
        result = f'DB取得未完了（{reason}）。パスワード再設定・アプリデータ変更は行っていません。'
        code = 1
    print(result, flush=True)
    if sys.platform == 'darwin':
        subprocess.run(['/usr/bin/pbcopy'], input=result, text=True, check=False)
    return code


if __name__ == '__main__':
    raise SystemExit(main())
