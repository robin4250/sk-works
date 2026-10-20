#!/usr/bin/env python3
"""Read existing CLI-owned remote config into a fresh private Mac folder only.

Scope: external-state evidence around the DB-only common-payroll rollout.
Not a full platform/secret/Storage backup and never a config push or deployment.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

PROJECT = 'ztktgquxvcxcjxtluspu'
CLI_VERSION = '2.120.0'
DATABASE_CAPTURE = 'database-capture-4b6w8i_n'
# The reviewed common-payroll DDL changes no Edge function or Storage object.
# Adding a future function here requires a new root review/hash-pinned loader.
EDGE_FUNCTIONS = ()
SEED_CONFIG = 'project_id = "sko-private-external-evidence"\n[db]\nmajor_version = 17\n'


class CaptureFailure(Exception):
    pass


def now():
    return datetime.now(timezone.utc).isoformat()


def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1048576), b''):
            h.update(chunk)
    return h.hexdigest()


def private_path(path, directory=False):
    if any(p.is_symlink() for p in (path, *path.parents)):
        raise CaptureFailure('symlink_refused')
    if not (path.is_dir() if directory else path.is_file()):
        raise CaptureFailure('required_file_missing')
    if path.stat().st_mode & 0o077:
        raise CaptureFailure('private_permissions_required')


def function_records(raw):
    value = json.loads(raw)
    if isinstance(value, dict):
        value = value.get('functions', value.get('data'))
        if isinstance(value, dict):
            value = value.get('functions')
    if not isinstance(value, list) or any(not isinstance(v, dict) for v in value):
        raise CaptureFailure('function_metadata_contract_unknown')
    return sorted(value, key=lambda row: str(row.get('slug', row.get('name', ''))))


def run_capture(root, previous=None):
    os.umask(0o077)
    root.mkdir(mode=0o700, parents=True, exist_ok=True)
    private_path(root, directory=True)
    original = root / DATABASE_CAPTURE
    private_path(original, directory=True)
    original_status = original / 'capture-status.json'
    private_path(original_status)
    saved = json.loads(original_status.read_text())
    if saved.get('capture_completed') is not True:
        raise CaptureFailure('original_database_capture_incomplete')
    for name in ('database.dump', 'roles.sql', 'archive-list.txt'):
        path = original / name
        private_path(path)
        record = saved.get('files', {}).get(name, {})
        if path.stat().st_size != record.get('bytes') or digest(path) != record.get('sha256'):
            raise CaptureFailure('original_database_capture_changed')
    original_identity = digest(original_status)
    prior = None
    if previous is not None:
        if not re.fullmatch(r'external-config-[A-Za-z0-9_-]+', previous):
            raise CaptureFailure('previous_capture_name_invalid')
        prior_dir = root / previous
        private_path(prior_dir, directory=True)
        path = prior_dir / 'external-status.json'
        private_path(path)
        prior = json.loads(path.read_text())
        if prior.get('captured') is not True or prior.get('project') != PROJECT:
            raise CaptureFailure('previous_capture_incomplete')
    stage = Path(tempfile.mkdtemp(prefix='external-config-', dir=root))
    work = stage / 'private-config'
    (work / 'supabase').mkdir(mode=0o700, parents=True)
    config = work / 'supabase' / 'config.toml'
    config.write_text(SEED_CONFIG)
    status = {
        'schema': 1, 'project': PROJECT, 'captured': False,
        'scope': 'common-payroll-db-only-external-evidence',
        'started_at_utc': now(), 'project_settings_written': False,
        'database_connected': False, 'database_password_requested': False,
        'credential_store_opened_by_helper': False,
        'full_platform_restore_verified': False,
        'provider_secret_restore_verified': False,
        'edge_secret_values_captured': False,
        'storage_objects_in_scope': 0, 'storage_bytes_captured': False,
        'storage_not_modified_by_reviewed_ddl': True,
        'selected_edge_functions': list(EDGE_FUNCTIONS),
        'same_snapshot_as_database_archive': False,
        'database_delta_preflight_still_required': True,
        'database_archive_file_mtime_utc': datetime.fromtimestamp(
            (original / 'database.dump').stat().st_mtime, timezone.utc).isoformat(),
        'database_capture_status_sha256': original_identity,
    }
    # Let the CLI use its existing account login through its supported interface.
    # Do not open keychain/token files, inherit endpoint/debug overrides, or use a DB login.
    env = {k: v for k, v in os.environ.items()
           if not k.startswith(('PG', 'SUPABASE_')) and k not in ('DB_PASSWORD', 'DEBUG')}
    env['NO_COLOR'] = '1'

    def command(args, label, timeout=120):
        status['phase'] = label
        result = subprocess.run(['supabase', *args], env=env,
                                stdin=subprocess.DEVNULL, capture_output=True,
                                text=True, timeout=timeout, cwd=work)
        # Everything potentially containing configuration/code stays in the private stage.
        (stage / (label + '-stdout.txt')).write_text(result.stdout)
        (stage / (label + '-stderr.txt')).write_text(result.stderr)
        if result.returncode:
            raise CaptureFailure(label + '_failed')
        if len(result.stdout) > 2097152 or len(result.stderr) > 2097152:
            raise CaptureFailure(label + '_output_too_large')
        return result.stdout

    try:
        version = command(['--version'], 'cli-version', 15)
        if version.strip() != CLI_VERSION:
            raise CaptureFailure('cli_version_changed')
        help_text = command(['config', 'pull', '--help'], 'config-pull-help', 15)
        if 'config pull' not in help_text or '--project-ref' not in help_text or '--force' not in help_text:
            raise CaptureFailure('config_pull_not_supported')
        list_help = command(['functions', 'list', '--help'], 'functions-list-help', 15)
        global_help = command(['--help'], 'global-help', 15)
        if '--project-ref' not in list_help or '--output-format' not in global_help:
            raise CaptureFailure('functions_list_not_supported')
        if EDGE_FUNCTIONS:
            download_help = command(['functions', 'download', '--help'], 'functions-download-help', 15)
            if '--use-api' not in download_help or '--project-ref' not in download_help:
                raise CaptureFailure('functions_download_not_supported')
        command(['config', 'pull', '--project-ref', PROJECT, '--workdir', str(work),
                 '--force', '--yes'], 'config-pull')
        private_path(config)
        text = config.read_text()
        if text == SEED_CONFIG or len(text) > 2097152 or '[auth]' not in text or 'site_url' not in text:
            raise CaptureFailure('pulled_auth_config_not_verified')
        metadata_raw = command(['functions', 'list', '--project-ref', PROJECT,
                                '--workdir', str(work), '--output-format', 'json'], 'functions-list')
        metadata = function_records(metadata_raw)
        metadata_path = stage / 'functions-metadata.json'
        metadata_path.write_text(json.dumps(metadata, ensure_ascii=False, sort_keys=True, indent=2))
        available = {row.get('slug', row.get('name')) for row in metadata}
        for name in EDGE_FUNCTIONS:
            if not re.fullmatch(r'[a-z0-9][a-z0-9_-]{0,62}', name) or name not in available:
                raise CaptureFailure('selected_function_missing')
            command(['functions', 'download', name, '--project-ref', PROJECT,
                     '--workdir', str(work), '--use-api'], 'function-' + name)
        # No Storage command runs for this DB-only scope. No Auth user list is read.
        status['config_sha256'] = digest(config)
        status['edge_metadata_sha256'] = digest(metadata_path)
        if prior is not None:
            status['previous_external_settings_match'] = (
                prior.get('config_sha256') == status['config_sha256'] and
                prior.get('edge_metadata_sha256') == status['edge_metadata_sha256'])
            if not status['previous_external_settings_match']:
                raise CaptureFailure('external_settings_changed_review_required')
        if digest(original_status) != original_identity:
            raise CaptureFailure('original_capture_status_changed_during_read')
        for name in ('database.dump', 'roles.sql', 'archive-list.txt'):
            if digest(original / name) != saved['files'][name]['sha256']:
                raise CaptureFailure('original_archive_changed_during_read')
        status.update(captured=True, phase='captured', finished_at_utc=now(),
                      auth_config_snapshot_saved=True, edge_metadata_saved=True,
                      supported_config_only=True)
    except (Exception, KeyboardInterrupt) as error:
        status['failure_code'] = str(error) if isinstance(error, CaptureFailure) else 'capture_failed'
        raise CaptureFailure(status['failure_code']) from None
    finally:
        status['attempt_finished_at_utc'] = now()
        # Reapply private permissions only inside the newly created stage.
        for path in stage.rglob('*'):
            if path.is_symlink():
                status.update(captured=False, failure_code='downloaded_symlink_refused')
                continue
            path.chmod(0o700 if path.is_dir() else 0o600)
        (stage / 'external-status.json').write_text(json.dumps(status, ensure_ascii=False, indent=2))
    if not status['captured']:
        raise CaptureFailure(status['failure_code'])
    return stage


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compare-capture', help='以前のexternal-config-*保存名だけを指定')
    args = parser.parse_args()
    try:
        if sys.platform != 'darwin':
            raise CaptureFailure('mac_required')
        stage = run_capture(Path.home() / 'SKO-source-backups', args.compare_capture)
        result = f'共通手当DB限定反映用の外部設定・Edge一覧を非公開保存: {stage.name}。設定変更なし。provider秘密値復元・Storage実bytes・DBとの同時点整合は未検証。'
        code = 0
    except (Exception, KeyboardInterrupt) as error:
        reason = str(error) if isinstance(error, CaptureFailure) else 'capture_failed'
        result = f'外部設定の非公開取得は未完了（{reason}）。本番設定・DB・Storageは変更していません。DBパスワード入力は不要です。'
        code = 1
    print(result, flush=True)
    if sys.platform == 'darwin':
        subprocess.run(['/usr/bin/pbcopy'], input=result, text=True, check=False)
    return code


if __name__ == '__main__':
    raise SystemExit(main())
