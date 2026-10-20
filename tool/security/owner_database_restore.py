#!/usr/bin/env python3
"""Restore a captured archive into a new offline container; never connect to production."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time
import uuid

IMAGE = 'supabase/postgres@sha256:b3bfedb107413abb3b8cb0d0874b0414a1dceb3d55bc0c778de6ad22d1f7dc86'
CAPTURE = 'database-capture-4b6w8i_n'
IDENT = r'(?:"(?:[^"]|"")*"|[A-Za-z_][A-Za-z_0-9$]*)'
COPY = re.compile(r'^COPY (' + IDENT + r'\.' + IDENT + r') \(.*\) FROM stdin;$')


def digest(path):
    value = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            value.update(block)
    return value.hexdigest()


def expected_rows(sql):
    counts = {}
    current = None
    for line in sql.splitlines():
        if current is not None:
            if line == r'\.':
                current = None
            else:
                counts[current] += 1
        elif line.startswith('COPY '):
            match = COPY.fullmatch(line)
            if not match or match[1] in counts:
                raise RuntimeError('unsupported_copy_format')
            current = match[1]
            counts[current] = 0
    if current is not None or not counts:
        raise RuntimeError('incomplete_copy_data')
    return counts


def container_command(name, backup, admin):
    # Bypass image bootstrap: restore roles/schemas from the archive into a
    # clean cluster. Network disabled, no ports, no credentials, backup RO.
    boot = 'set -eu; initdb -D /tmp/sko-pg -U "$1" --auth-local=trust --auth-host=reject --encoding=UTF8 --locale=C >/tmp/init.log 2>&1; exec postgres -D /tmp/sko-pg -c listen_addresses= -c unix_socket_directories=/tmp -c shared_preload_libraries=pg_cron,pg_stat_statements -c cron.database_name=postgres -c cron.launch_active_jobs=off -c wal_level=logical'
    return ['docker', 'run', '-d', '--name', name, '--label', 'sko-purpose=offline-restore',
            '--network=none', '--user=postgres', '--no-healthcheck',
            '--mount', f'type=bind,source={backup},target=/backup,readonly',
            '--entrypoint', 'bash', IMAGE, '-c', boot, 'sko-restore', admin]


def main():
    os.umask(0o077)
    stage = None
    name = None
    started = False
    status = {'schema': 1, 'archive_restore_verified': False, 'production_connected': False,
              'auth_login_verified': False, 'storage_bytes_restored': False,
              'vault_decryption_verified': False, 'network_mode': 'none'}
    try:
        if sys.platform != 'darwin':
            raise RuntimeError('mac_required')
        root = Path.home() / 'SKO-source-backups'
        backup = root / CAPTURE
        if any(p.is_symlink() for p in (backup, *backup.parents)):
            raise RuntimeError('unsafe_backup_path')
        if not backup.is_dir() or root.stat().st_mode & 0o077:
            raise RuntimeError('private_backup_required')
        manifest = backup / 'capture-status.json'
        if manifest.is_symlink() or manifest.stat().st_size > 1048576:
            raise RuntimeError('invalid_capture_manifest')
        capture = json.loads(manifest.read_text())
        if capture.get('capture_completed') is not True:
            raise RuntimeError('capture_incomplete')
        originals = {}
        for file in ('database.dump', 'roles.sql', 'archive-list.txt'):
            path = backup / file
            if path.is_symlink() or not path.is_file():
                raise RuntimeError('invalid_capture_file')
            metadata = capture['files'][file]
            originals[file] = digest(path)
            if originals[file] != metadata['sha256'] or path.stat().st_size != metadata['bytes']:
                raise RuntimeError('backup_hash_mismatch')
        stage = Path(tempfile.mkdtemp(prefix='database-restore-', dir=root))
        status['source_sha256'] = originals
        name = 'sko-restore-' + uuid.uuid4().hex[:12]
        admin = 'sko_recovery_' + uuid.uuid4().hex[:12]
        status['container'] = name
        env = {k:v for k,v in os.environ.items() if not k.startswith('PG')}
        # Refuse remote Docker contexts/hosts; the backup must stay on this Mac.
        if env.get('DOCKER_HOST') or env.get('DOCKER_CONTEXT'):
            raise RuntimeError('explicit_docker_endpoint_refused')
        with (stage / 'private-errors.log').open('xb') as errors:
            def run(args, *, data=None, timeout=120):
                return subprocess.run(args, env=env, input=data, stdin=subprocess.DEVNULL if data is None else None,
                                      stdout=subprocess.PIPE, stderr=errors, timeout=timeout, check=True).stdout
            context = json.loads(run(['docker', 'context', 'inspect']).decode())
            endpoint = context[0]['Endpoints']['docker']['Host']
            if not endpoint.startswith('unix://'):
                raise RuntimeError('remote_docker_refused')
            run(['docker', 'image', 'inspect', IMAGE])
            print('バックアップのハッシュ一致。通信を切った専用DBを起動します。', flush=True)
            run(container_command(name, backup, admin))
            started = True
            def local(command, data=None, timeout=120):
                return run(['docker', 'exec', '--user', 'root', '-i', name, *command], data=data, timeout=timeout)
            def query(sql):
                return local(['psql', '-X', '-w', '-h', '/tmp', '-U', admin, '-d', 'postgres',
                              '-A', '-t', '-v', 'ON_ERROR_STOP=1'], sql.encode()).decode().strip()
            ready = False
            for _ in range(60):
                probe = subprocess.run(['docker', 'exec', name, 'pg_isready', '-h', '/tmp', '-U', admin],
                                       env=env, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                                       stderr=errors, timeout=5)
                if probe.returncode == 0:
                    ready = True
                    break
                time.sleep(1)
            if not ready:
                raise RuntimeError('isolated_database_not_ready')
            info = json.loads(run(['docker', 'inspect', name]).decode())[0]
            if info['HostConfig']['NetworkMode'] != 'none' or info['HostConfig'].get('PortBindings'):
                raise RuntimeError('container_isolation_failed')
            if any(m.get('RW') for m in info['Mounts'] if m['Destination'] == '/backup'):
                raise RuntimeError('backup_mount_not_readonly')
            if query("SHOW cron.launch_active_jobs;") != 'off':
                raise RuntimeError('cron_not_disabled')
            print('ロール・DBを復元しています。', flush=True)
            status['phase'] = 'roles'
            local(['psql', '-X', '-w', '-h', '/tmp', '-U', admin, '-d', 'postgres',
                   '-v', 'ON_ERROR_STOP=1', '-f', '/backup/roles.sql'])
            listing = (backup / 'archive-list.txt').read_text()
            if re.search(r' SCHEMA - public ', listing):
                query('DROP SCHEMA public;')
            status['phase'] = 'archive'
            local(['pg_restore', '--exit-on-error', '--single-transaction', '-h', '/tmp',
                   '-U', admin, '-d', 'postgres', '/backup/database.dump'], timeout=1800)
            status['phase'] = 'row_verification'
            sql = local(['pg_restore', '--data-only', '--file', '-', '/backup/database.dump'], timeout=300).decode()
            rows = expected_rows(sql)
            for relation, expected in rows.items():
                if int(query('SELECT count(*) FROM ONLY ' + relation + ';')) != expected:
                    raise RuntimeError('restored_row_count_mismatch')
            for file, expected in originals.items():
                if digest(backup / file) != expected:
                    raise RuntimeError('backup_changed_during_restore')
            status.update(archive_restore_verified=True, verified_tables=len(rows), verified_rows=sum(rows.values()),
                          source_backup_unchanged=True, phase='verified')
        result = f'隔離DBのアーカイブ復元・全COPYテーブル件数照合成功: {stage.name}。本番接続なし。Authログイン/Storage実ファイル/Vault復号は未検証。'
        code = 0
    except (Exception, KeyboardInterrupt):
        result = '隔離復元は完了確認できません。本番接続・バックアップ変更は行っていません。記録を保持しています。'
        code = 1
    finally:
        if name and started:
            try:
                stopped = subprocess.run(['docker', 'stop', '-t', '10', name], stdout=subprocess.DEVNULL,
                                         stderr=subprocess.DEVNULL, timeout=30, check=False)
                status['container_stopped'] = stopped.returncode == 0
            except (Exception, KeyboardInterrupt):
                status['container_stopped'] = False
        if stage:
            (stage / 'rehearsal-status.json').write_text(json.dumps(status, ensure_ascii=False, indent=2))
    print(result, flush=True)
    return code


if __name__ == '__main__':
    raise SystemExit(main())
