#!/usr/bin/env python3
"""Rehearsal-only source snapshot/restore. Never contacts or restores a database."""
import argparse
import hashlib
import io
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tarfile
import tempfile
from urllib.parse import urlsplit


def require(value, message):
    if not value:
        raise ValueError(message)


def command(repo, *args, input_data=None):
    env = {key: value for key, value in os.environ.items() if not key.startswith('GIT_')}
    env.update(GIT_CONFIG_NOSYSTEM='1', GIT_CONFIG_GLOBAL=os.devnull, GIT_TERMINAL_PROMPT='0')
    p = subprocess.run(['git', '-c', 'core.fsmonitor=false', '-c', 'core.hooksPath=/dev/null',
                        '-C', str(repo), *args], input=input_data,
                       capture_output=True, check=False, env=env)
    require(p.returncode == 0, 'Git operation failed; no source was reset or cleaned')
    return p.stdout


def sha(data):
    return hashlib.sha256(data).hexdigest()


def safe_relative(value):
    p = Path(value)
    require(value and not p.is_absolute() and '..' not in p.parts
            and '.git' not in p.parts and '\\' not in value, 'Unsafe source path')
    return p


def outside_git(parent):
    parent = parent.resolve(strict=True)
    p = subprocess.run(['git', '-C', str(parent), 'rev-parse', '--show-toplevel'], capture_output=True)
    require(p.returncode != 0, 'Output must be outside every Git checkout')
    return parent


def private_write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    with path.open('xb') as stream:
        os.fchmod(stream.fileno(), 0o600)
        stream.write(data)


def state(repo):
    paths = command(repo, 'ls-files', '-z', '--cached', '--others', '--exclude-standard').split(b'\0')
    files = {}
    for encoded in sorted(set(paths)):
        if not encoded:
            continue
        name = os.fsdecode(encoded)
        relative = safe_relative(name)
        target = repo / relative
        require(target.resolve().is_relative_to(repo), 'Source path escapes checkout')
        require(not any(p.is_symlink() for p in [target, *target.parents] if p != repo and p.is_relative_to(repo)),
                'Source symlink ancestors require separate review')
        if not target.exists() and not target.is_symlink():
            files[name] = {'deleted': True}
            continue
        require(target.is_file() and not target.is_symlink(), 'Submodules/symlinks require a separate reviewed backup')
        files[name] = {'sha256': sha(target.read_bytes()), 'executable': bool(target.stat().st_mode & 0o111)}
    return {'head': command(repo, 'rev-parse', 'HEAD').decode().strip(),
            'status': command(repo, 'status', '--porcelain=v1', '-z', '--untracked-files=all').hex(),
            'index': sha(command(repo, 'ls-files', '--stage', '-z')), 'files': files}


def snapshot(repo, destination):
    repo = Path(command(repo, 'rev-parse', '--show-toplevel').decode().strip()).resolve()
    parent = outside_git(destination.parent)
    destination = parent / destination.name
    require(not destination.exists() and not destination.is_symlink(), 'Never overwrite a snapshot')
    before = state(repo)
    destination.mkdir(mode=0o700)
    artifacts = {
        'head.tar': command(repo, 'archive', '--format=tar', 'HEAD'),
        'staged.patch': command(repo, 'diff', '--cached', '--binary', '--full-index', '--no-ext-diff', '--no-textconv'),
        'working.patch': command(repo, 'diff', '--binary', '--full-index', '--no-ext-diff', '--no-textconv'),
    }
    for name, data in artifacts.items():
        private_write(destination / name, data)
    for name, entry in before['files'].items():
        if not entry.get('deleted'):
            current_bytes = (repo / name).read_bytes()
            require(sha(current_bytes) == entry['sha256'], 'Source changed while copying; snapshot incomplete')
            private_write(destination / 'current' / safe_relative(name), current_bytes)
    for path in destination.rglob('*'):
        if path.is_dir():
            path.chmod(0o700)
    require(state(repo) == before, 'Source changed during backup; incomplete snapshot must not be used')
    artifact_hashes = {name: sha(data) for name, data in artifacts.items()}
    private_write(destination / 'manifest.json', json.dumps({
        'schema': 'sko-source-rehearsal-v1', 'complete': True,
        'state': before, 'artifacts': artifact_hashes,
        'production_backup_complete': False, 'database_restore_executed': False,
    }, sort_keys=True).encode())
    return destination


def verify_snapshot(folder):
    require(not folder.is_symlink() and folder.is_dir(), 'Snapshot directory required')
    manifest = json.loads((folder / 'manifest.json').read_text())
    require(manifest.get('schema') == 'sko-source-rehearsal-v1' and manifest.get('complete') is True,
            'Incomplete snapshot')
    for name, expected in manifest['artifacts'].items():
        path = folder / safe_relative(name)
        require(not path.is_symlink() and sha(path.read_bytes()) == expected, 'Backup artifact changed')
    for name, entry in manifest['state']['files'].items():
        safe_relative(name)
        if not entry.get('deleted'):
            path = folder / 'current' / name
            require(not path.is_symlink() and sha(path.read_bytes()) == entry['sha256'], 'Backup source bytes changed')
    return manifest


def rehearse(folder, parent):
    manifest = verify_snapshot(folder)
    parent = outside_git(parent)
    # Always create a new disposable directory. Never restore over an existing path.
    restored = Path(tempfile.mkdtemp(prefix='sko-recovery-rehearsal-', dir=parent))
    with tarfile.open(fileobj=io.BytesIO((folder / 'head.tar').read_bytes())) as archive:
        members = archive.getmembers()
        for member in members:
            safe_relative(member.name)
            require(member.isfile() or member.isdir(), 'Special archive entries are forbidden')
        archive.extractall(restored, members=members, filter='data')
    for path in restored.rglob('*'):
        if path.is_dir():
            path.chmod(0o700)
        else:
            path.chmod(0o700 if path.stat().st_mode & 0o111 else 0o600)
    command(restored, 'init', '-b', 'main')
    command(restored, 'add', '--all')
    command(restored, '-c', 'user.name=Recovery Fixture', '-c', 'user.email=recovery@example.invalid',
            'commit', '--allow-empty', '-m', 'Isolated baseline, not original commit identity')
    staged = (folder / 'staged.patch').read_bytes()
    working = (folder / 'working.patch').read_bytes()
    if staged:
        command(restored, 'apply', '--index', '--binary', '-', input_data=staged)
    if working:
        command(restored, 'apply', '--binary', '-', input_data=working)
    tracked = set(os.fsdecode(p) for p in command(restored, 'ls-files', '-z').split(b'\0') if p)
    for name, entry in manifest['state']['files'].items():
        if name not in tracked and not entry.get('deleted'):
            path = restored / safe_relative(name)
            require(not path.exists(), 'Unexpected restore collision')
            path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
            shutil.copyfile(folder / 'current' / name, path)
            path.chmod(0o700 if entry['executable'] else 0o600)
    actual = state(restored)
    expected = manifest['state']
    require(actual['files'] == expected['files'] and actual['index'] == expected['index']
            and actual['status'] == expected['status'], 'Isolated restore differs from source snapshot')
    report = {'schema': 'sko-source-restore-result-v1', 'source_sha': expected['head'],
              'snapshot_manifest_sha256': sha((folder / 'manifest.json').read_bytes()),
              'source_files_equal': True, 'staged_index_equal': True, 'dirty_status_equal': True,
              'production_backup_complete': False, 'database_restore_executed': False,
              'production_permission_change_authorized': False}
    private_write(folder / ('restore-' + restored.name.removeprefix('sko-recovery-rehearsal-') + '.json'),
                  json.dumps(report, sort_keys=True).encode())
    return report


def database_target_shape(url):
    """Only a precheck. No DB connection, freshness proof or restore authorization."""
    parsed = urlsplit(url)
    require(parsed.scheme in ('postgres', 'postgresql') and parsed.hostname in ('127.0.0.1', '::1')
            and parsed.port and not parsed.username and not parsed.password and not parsed.query
            and not parsed.fragment and re.fullmatch(r'/sko_recovery_fixture_[0-9a-f]{32}', parsed.path),
            'Only credential-free loopback disposable fixture targets are accepted')
    return {'target_shape_valid': True, 'fresh_database_verified': False,
            'database_restore_authorized': False, 'reason': 'Freshness/catalog/backup verification is not implemented; restore remains blocked'}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('operation', choices=['snapshot', 'rehearse', 'database-target-shape'])
    p.add_argument('--repo', type=Path)
    p.add_argument('--output', type=Path)
    p.add_argument('--snapshot', type=Path)
    p.add_argument('--parent', type=Path)
    p.add_argument('--target')
    args = p.parse_args()
    try:
        if args.operation == 'snapshot':
            require(args.repo and args.output, 'Source and new output directory required')
            snapshot(args.repo, args.output)
            print('Source snapshot saved privately. Production backup remains incomplete.')
        elif args.operation == 'rehearse':
            require(args.snapshot and args.parent, 'Snapshot and outside-Git parent required')
            rehearse(args.snapshot, args.parent)
            print('Isolated source restore matched bytes, index and dirty state. No database restored.')
        else:
            require(args.target, 'Disposable target required')
            database_target_shape(args.target)
            print('Target shape is acceptable, but database restore remains BLOCKED: freshness and authorization are unverified.')
            return 2
    except (ValueError, OSError, KeyError, TypeError, tarfile.TarError):
        print('Recovery verification failed. Preserve originals; do not change production permissions.')
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
