#!/usr/bin/env python3
"""Candidate: exact annual SQL delivery; no login or connection at import time."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile

PROJECT = 'ztktgquxvcxcjxtluspu'
INSTALL_SHA = 'bd9f2a93b3762c4f8374e34de4562f1a8040bbd5011cdc084d2935113555ea20'
BEFORE_SHA = 'ab7099f3522e8d097d77ac459c696865de022df73746679da9a7a4380da9fb35'
OBSERVER_SHA = 'dadd39538d121145d9fa64c21c88e3618c5e77ea73e5e26a59d1f4a55fc2e76a'
GENERATOR_SHA = '0952c04fb3bb0a1400c66c6e19377f5bb1ca12a43630070b81cf20ab69d3b656'
HELPERS = {
    'owner_database_capture': '15875c927d90364f8dec1973f5fb1661dc12b9f5242aee5175203f7cb8a8702d',
    'owner_cli_database_capture': 'e4f206b3dab91f98295f2f2a1688a02cc74adb80d00d6262a3f3ce4cc9a300e0',
}
RUNTIME_HASHES = {
    'cli': 'e9ded83b4a7892847ac9c29e7b06e4f69cbc8d1584066a3e8b5f59b340396289',
    'psql': '705f13dd9114e0b6793ddcddfd17e5d8a894ea5faadf84d824e0b484a168b3f5',
    'certificate': '700723581420dd1ac98fd7e9ac529f0ef210eadcaf87fc868a3ad7d114c2f3b7',
}
IDENTITY_SQL = b"""begin isolation level repeatable read read only;
select jsonb_build_object('read_only',current_setting('transaction_read_only'),
'current_user',current_user,'session_user',session_user,'database',current_database(),
'server_version_num',current_setting('server_version_num'), 'auth_uid',auth.uid(),
'jwt_claims',nullif(current_setting('request.jwt.claims',true),''),
'jwt_sub',nullif(current_setting('request.jwt.claim.sub',true),''),
'jwt_role',nullif(current_setting('request.jwt.claim.role',true),''));rollback;"""
MAX_BYTES = 2 * 1024 * 1024
MARKER = 'annual-install-attempt.private.json'


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def private_dir(path):
    if not path.is_absolute() or any(p.is_symlink() for p in (path, *path.parents)):
        raise ValueError('private_directory_required')
    s = path.stat()
    if not stat.S_ISDIR(s.st_mode) or s.st_uid != os.getuid() or s.st_mode & 0o077:
        raise ValueError('private_directory_required')


def read_private(path):
    private_dir(path.parent)
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    with os.fdopen(fd, 'rb') as stream:
        s = os.fstat(stream.fileno())
        if not stat.S_ISREG(s.st_mode) or s.st_uid != os.getuid() or s.st_mode & 0o077 or s.st_size > MAX_BYTES:
            raise ValueError('private_file_required')
        return stream.read(MAX_BYTES + 1)


def write_once(path, raw):
    private_dir(path.parent)
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, 'wb') as stream:
        stream.write(raw)
        stream.flush()
        os.fsync(stream.fileno())
    sync_dir(path.parent)


def write_once_or_verify(path, raw):
    if path.exists() or path.is_symlink():
        if read_private(path) != raw:
            raise ValueError('existing_evidence_changed')
    else:
        write_once(path, raw)


def sync_dir(path):
    fd = os.open(path, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def update_marker(path, state):
    read_private(path)
    with tempfile.NamedTemporaryFile(dir=path.parent, prefix='.receipt-', delete=False) as stream:
        stream.write(json.dumps(state, sort_keys=True).encode())
        stream.flush()
        os.fsync(stream.fileno())
        temp = Path(stream.name)
    os.replace(temp, path)
    sync_dir(path.parent)


def load_exact_module(name, path, expected):
    if path.is_symlink() or sha(path.read_bytes()) != expected:
        raise ValueError('reviewed_source_changed')
    if name in sys.modules and Path(sys.modules[name].__file__).resolve() != path.resolve():
        raise ValueError('module_conflict')
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


class Proof:
    def __init__(self, bundle, source_root):
        self.install = read_private(bundle / 'annual-prepared-install.sql.review-only')
        before_raw = read_private(bundle / 'annual-before-checkpoint.json')
        self.read_sql = read_private(bundle / 'annual-before-observer.read-only.sql')
        if (sha(self.install), sha(before_raw), sha(self.read_sql)) != (INSTALL_SHA, BEFORE_SHA, OBSERVER_SHA):
            raise ValueError('exact_private_artifact_changed')
        self.before = json.loads(before_raw)
        self.generator = load_exact_module('_annual_review_generator',
            source_root / 'tool/security/prepare_resident_annual_deployment_review.py', GENERATOR_SHA)
        self.source_root = source_root
        if self.generator.prepare_install(self.before, source_root).encode() != self.install:
            raise ValueError('install_not_reviewed_generation')
        # Reuse the reviewed SQL postflight inside a read-only transaction. Its
        # temporary observation setting is local, not an application write.
        _, expected = self.generator.sources(source_root)
        self.after_sql = ("begin isolation level repeatable read read only;\n"
            "set local statement_timeout='30s';set local TimeZone='UTC';set local DateStyle='ISO, YMD';\n"
            + self.generator.postflight(self.before, expected)
            + "select current_setting('sko.resident_annual_observation')::jsonb;\nrollback;\n").encode()

    def before_ok(self, value):
        if value != self.before:
            raise ValueError('before_checkpoint_changed')

    def after_ok(self, value):
        # No removal is executed. Generation enforces exact inventory, original
        # values/catalog, expected new sources and four empty annual tables.
        return self.generator.prepare_restore(self.before, value, self.source_root).encode()


class PsqlTransport:
    def __init__(self, binding, config, password):
        self.binding, self.config, self.password = binding, config, password
        self.attempted = False

    def request(self, sql, readonly):
        if not isinstance(sql, bytes) or not 0 < len(sql) <= MAX_BYTES:
            raise ValueError('bounded_sql_required')
        for key in ('psql', 'cli', 'certificate'):
            item = self.binding[key]
            p = Path(item['path'])
            if p.is_symlink() or sha(p.read_bytes()) != item['sha256']:
                raise ValueError('runtime_binding_changed')
        env = {**self.config, 'PGPASSWORD': self.password, 'PGSSLMODE': 'verify-full',
            'PGSSLROOTCERT': self.binding['certificate']['path'], 'PGCONNECT_TIMEOUT': '10',
            'PGPASSFILE': '/dev/null', 'PGSERVICEFILE': '/dev/null', 'LC_ALL': 'C', 'LANG': 'C',
            'PGOPTIONS': '-c search_path= -c statement_timeout=30000 -c lock_timeout=3000 -c idle_in_transaction_session_timeout=35000'
                + (' -c default_transaction_read_only=on' if readonly else '')}
        try:
            result = subprocess.run([self.binding['psql']['path'], '-X', '-w', '-q', '-A', '-t',
                '-v', 'ON_ERROR_STOP=1', '-v', 'VERBOSITY=sqlstate'], input=sql, env=env,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=45, close_fds=True)
            if result.returncode or len(result.stdout) > MAX_BYTES:
                raise RuntimeError('psql_result_unknown')
            if readonly:
                value = json.loads(result.stdout)
                if not isinstance(value, dict):
                    raise ValueError('observation_object_required')
                return value
            if result.stdout.strip():
                raise RuntimeError('commit_ack_unknown')
        except (Exception, KeyboardInterrupt):
            raise RuntimeError('transport_result_unknown') from None
        finally:
            env.pop('PGPASSWORD', None)

    def read(self, sql):
        return self.request(sql, True)

    def install_once(self, sql):
        if self.attempted or sha(sql) != INSTALL_SHA:
            raise ValueError('install_resend_or_changed_sql')
        self.attempted = True
        self.request(sql, False)


def operate(root, proof, transport, mode):
    private_dir(root)
    marker = root / MARKER
    if mode == 'install':
        if marker.exists() or marker.is_symlink():
            raise ValueError('prior_attempt_recovery_only')
        actual = transport.read(proof.read_sql)
        proof.before_ok(actual)
        write_once(root / 'before.private.json', json.dumps(actual, sort_keys=True).encode())
        state = {'schema': 1, 'project': PROJECT, 'phase': 'attempt_recorded',
            'install_sha256': INSTALL_SHA, 'commit_acknowledged': False,
            'complete': False, 'retry_allowed': False, 'financial_input_performed': False}
        write_once(marker, json.dumps(state, sort_keys=True).encode())
        try:
            transport.install_once(proof.install)
            state.update(phase='commit_acknowledged', commit_acknowledged=True)
        except (Exception, KeyboardInterrupt):
            state['phase'] = 'result_unknown_readonly_recovery_required'
        update_marker(marker, state)
    else:
        state = json.loads(read_private(marker))
        if state.get('project') != PROJECT or state.get('install_sha256') != INSTALL_SHA or state.get('retry_allowed') is not False:
            raise ValueError('attempt_marker_changed')
    try:
        actual = transport.read(proof.read_sql)
        if actual == proof.before:
            state.update(phase='not_installed_observed_no_resend', complete=False)
        else:
            verified = transport.read(proof.after_sql)
            if verified != actual:
                raise ValueError('after_observation_changed')
            restore = proof.after_ok(actual)
            suffix = sha(json.dumps(actual, sort_keys=True).encode())[:20]
            output = root / ('after-' + suffix + '.private.json')
            write_once_or_verify(output, json.dumps(actual, sort_keys=True).encode())
            undo = root / ('unused-removal-' + suffix + '.sql.review-only')
            write_once_or_verify(undo, restore)
            state.update(phase='installed_verified_unused', complete=True,
                after_sha256=sha(json.dumps(actual, sort_keys=True).encode()),
                unused_removal_sha256=sha(restore))
    except (Exception, KeyboardInterrupt):
        state.update(phase='result_unknown_readonly_recovery_required', complete=False)
    update_marker(marker, state)
    return state


def connect(binding, root):
    here = Path(__file__).resolve().parent
    for name, digest in HELPERS.items():
        load_exact_module(name, here / (name + '.py'), digest)
    cli = sys.modules['owner_cli_database_capture']
    if set(binding) != {'project', 'host', 'cli', 'psql', 'certificate'} or binding.get('project') != PROJECT or binding.get('host') != 'aws-0-ap-northeast-1.pooler.supabase.com':
        raise ValueError('project_or_host_binding_changed')
    for key in ('psql', 'cli', 'certificate'):
        item = binding[key]
        p = Path(item['path'])
        if set(item) != {'path', 'sha256'} or item['sha256'] != RUNTIME_HASHES[key] or not p.is_absolute() or p.is_symlink() or sha(p.read_bytes()) != item['sha256']:
            raise ValueError('runtime_binding_changed')
    if Path(binding['certificate']['path']) != Path.home() / 'Downloads/prod-ca-2021.crt':
        raise ValueError('certificate_path_changed')
    result = subprocess.run([binding['cli']['path'], '--version'], capture_output=True, timeout=15, check=True)
    if result.stdout.strip() != b'2.120.0':
        raise ValueError('cli_version_changed')
    old = os.environ.get('PATH')
    try:
        os.environ['PATH'] = str(Path(binding['cli']['path']).parent) + ':/usr/bin:/bin'
        with tempfile.TemporaryDirectory(dir=root, prefix='.cli-') as temp:
            work = Path(temp)
            (work / 'supabase').mkdir(mode=0o700)
            (work / 'supabase/config.toml').write_text('project_id="sko-private-capture"\n[db]\nmajor_version=17\n')
            url, password = cli.obtain_connection(work)
    finally:
        if old is None:
            os.environ.pop('PATH', None)
        else:
            os.environ['PATH'] = old
    config = cli.capture.endpoint(url, cli_login=True)
    if config['PGHOST'] != binding['host'] or config['PGPORT'] != '5432' or not config['PGUSER'].startswith('cli_login_'):
        raise ValueError('connection_binding_changed')
    transport = PsqlTransport(binding, config, password)
    try:
        identity = transport.read(IDENTITY_SQL)
        expected = {'read_only', 'current_user', 'session_user', 'database', 'server_version_num',
            'auth_uid', 'jwt_claims', 'jwt_sub', 'jwt_role'}
        if set(identity) != expected or identity['read_only'] != 'on' or identity['current_user'] != 'postgres' or identity['database'] != 'postgres' or not 170000 <= int(identity['server_version_num']) < 180000:
            raise ValueError('maintenance_identity_refused')
        if config['PGUSER'] not in (identity['session_user'], identity['session_user'] + '.' + PROJECT) or any(identity[k] is not None for k in ('auth_uid', 'jwt_claims', 'jwt_sub', 'jwt_role')):
            raise ValueError('maintenance_identity_refused')
        return transport
    except BaseException:
        transport.password = None
        raise
    finally:
        password = None


def main():
    os.umask(0o077)
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('mode', choices=['install', 'recover'])
    p.add_argument('--bundle', type=Path, required=True)
    p.add_argument('--source-root', type=Path, required=True)
    a = p.parse_args()
    transport = None
    try:
        if sys.platform != 'darwin' or not sys.flags.isolated:
            raise ValueError('isolated_mac_python_required')
        root = Path.home() / 'SKO-source-backups/resident-annual-owner-20261024'
        private_dir(root.parent)
        root.mkdir(mode=0o700, exist_ok=True)
        private_dir(root)
        proof = Proof(a.bundle, a.source_root)
        if a.mode == 'install' and ((root / MARKER).exists() or (root / MARKER).is_symlink()):
            raise ValueError('prior_attempt_recovery_only')
        binding = json.loads(read_private(a.bundle / 'runtime-binding.private.json'))
        transport = connect(binding, root)
        state = operate(root, proof, transport, a.mode)
    except (Exception, KeyboardInterrupt):
        state = {'schema': 1, 'project': PROJECT, 'complete': False,
            'phase': 'requires_review', 'retry_allowed': False,
            'financial_input_performed': False}
    finally:
        if transport is not None:
            transport.password = None
    text = json.dumps(state, sort_keys=True)
    print(text, flush=True)
    if sys.platform == 'darwin':
        subprocess.run(['/usr/bin/pbcopy'], input=text.encode(), check=False, timeout=10)
    return 0 if state.get('complete') else 1


if __name__ == '__main__':
    raise SystemExit(main())
