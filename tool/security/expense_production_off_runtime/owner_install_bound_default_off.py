"""Owner entry point called only by the hash-pinned Mac bootstrap.

Stages the existing immutable prepared artifacts, then calls the reviewed
one-shot CLI transport. It never enables gates or converts financial rows.
"""
from __future__ import annotations

import hashlib
import importlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

PROJECT = 'ztktgquxvcxcjxtluspu'
ARTIFACTS = {
    'private-fresh-before.json': '63e6a610b2139d06209a311b9626c829608e74dae52070205f176d3ad06c8e9a',
    'private-prepared-install.sql.review-only': 'e1db52add6259495da9f3f47e870d2a81c356f991e7ee7c7df6ccee9fc30d840',
    'private-read-actual-after.sql.read-only': '0ada5da124e4ab4b7bb7b3739b77e747d620e68be954db5fd514a76a8ddbe9ab',
    'prepare-status.json': 'f8ac382e51403e9520c7b00cff02f69edf3c82c3b54ee7e976872bead142bc19',
}
MARKER = 'expense-default-off-install-attempt.json'


class OwnerRefused(RuntimeError):
    pass


def _digest(raw):
    return hashlib.sha256(raw).hexdigest()


def _private_directory(path):
    if not path.is_absolute() or '..' in path.parts or any(p.is_symlink() for p in (path, *path.parents)):
        raise OwnerRefused('private_directory_required')
    st = path.stat()
    if not path.is_dir() or st.st_uid != os.getuid() or st.st_mode & 0o077:
        raise OwnerRefused('private_directory_required')


def _read(path):
    _private_directory(path.parent)
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    try:
        import stat
        st = os.fstat(fd)
        if not stat.S_ISREG(st.st_mode) or st.st_uid != os.getuid() or st.st_mode & 0o077 or not 0 < st.st_size <= 16777216:
            raise OwnerRefused('private_artifact_required')
        raw = os.read(fd, st.st_size + 1)
        if len(raw) != st.st_size:
            raise OwnerRefused('private_artifact_changed')
        return raw
    finally:
        os.close(fd)


def _write_once(path, raw):
    if path.exists() or path.is_symlink():
        if _read(path) != raw:
            raise OwnerRefused('existing_artifact_differs')
        return
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    try:
        with os.fdopen(fd, 'wb', closefd=False) as f:
            f.write(raw)
            f.flush()
            os.fsync(fd)
    finally:
        os.close(fd)
    fd = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def stage_and_install(source, root, runtime, expected_manifest_sha256):
    """All parameters are constants in the independently reviewed bootstrap."""
    os.umask(0o077)
    if sys.platform != 'darwin':
        raise OwnerRefused('mac_required')
    if not sys.flags.isolated:
        raise OwnerRefused('isolated_python_required')
    source, root, runtime = Path(source), Path(root), Path(runtime)
    expected_root = Path.home() / 'SKO-source-backups' / ('expense-default-off-production-' + PROJECT)
    if root != expected_root or runtime != root / 'runtime':
        raise OwnerRefused('fixed_operator_root_required')
    for path in (source, root, runtime):
        _private_directory(path)
    if (root / MARKER).exists() or (root / MARKER).is_symlink():
        raise OwnerRefused('previous_attempt_requires_readonly_recovery')
    raw = _read(root / 'production-approval.json')
    if not re.fullmatch(r'[0-9a-f]{64}', expected_manifest_sha256) or _digest(raw) != expected_manifest_sha256:
        raise OwnerRefused('approved_manifest_changed')
    approval = json.loads(raw)
    if approval.get('project') != PROJECT or approval.get('artifacts') != ARTIFACTS:
        raise OwnerRefused('approved_original_hashes_differ')
    # Read and verify ALL originals before staging any prepared artifact.
    originals = {name: _read(source / name) for name in ARTIFACTS}
    if any(_digest(originals[name]) != wanted for name, wanted in ARTIFACTS.items()):
        raise OwnerRefused('original_prepared_artifact_changed')
    prepared = root / 'prepared'
    prepared.mkdir(mode=0o700, exist_ok=True)
    _private_directory(prepared)
    for name, content in originals.items():
        _write_once(prepared / name, content)
    # Isolated Python startup is required by the bootstrap. Only the fixed,
    # private, hash-verified runtime is added for these sibling imports.
    if any(name in sys.modules for name in ('cli_psql_transport', 'production_transport_binding', 'review_runner')):
        raise OwnerRefused('operator_module_already_loaded')
    sys.path.insert(0, str(runtime))
    binding = importlib.import_module('production_transport_binding')
    if binding.APPROVED_DURABLE_ROOT != root or binding.APPROVED_MANIFEST_SHA256 != expected_manifest_sha256:
        raise OwnerRefused('compiled_binding_differs')
    transport = importlib.import_module('cli_psql_transport')
    state = transport.install_cli_approved_once()
    phase = state.get('phase')
    return {
        'schema': 1, 'project': PROJECT, 'phase': phase,
        'commit_acknowledged': state.get('commit_acknowledged', False),
        # A before-state observation is not proof that an unacknowledged backend
        # cannot finish a delayed COMMIT. Never advertise it as a safe retry.
        'deployment_performed': True if phase == 'installed_off_unused_undo_candidate' else None,
        'observed_before': phase == 'before_state_observed',
        'application_data_mutations': False, 'conversion_performed': False,
        'retry_allowed': False, 'unused_undo_sha256': state.get('unused_undo_sha256'),
        'complete': False,
    }


def run_owner(source, root, runtime, expected_manifest_sha256):
    """Persist and auto-copy only sanitized results, never SQL or credentials."""
    os.umask(0o077)
    try:
        result = stage_and_install(source, root, runtime, expected_manifest_sha256)
    except (Exception, KeyboardInterrupt) as error:
        label = error.args[0] if isinstance(error, (OwnerRefused, RuntimeError)) and error.args else ''
        result = {'schema': 1, 'project': PROJECT, 'phase': 'requires_review',
                  'failure_code': label if isinstance(label, str) and re.fullmatch(r'[a-z_]{1,80}', label) else 'owner_install_incomplete',
                  'deployment_performed': None, 'application_data_mutations': False,
                  'conversion_performed': False, 'retry_allowed': False, 'complete': False}
    raw = json.dumps(result, ensure_ascii=False, sort_keys=True)
    try:
        _private_directory(Path(root))
        fd, name = tempfile.mkstemp(prefix='operator-result-', suffix='.json', dir=root)
        with os.fdopen(fd, 'wb') as f:
            f.write(raw.encode('utf-8'))
            f.flush()
            os.fsync(f.fileno())
        directory_fd = os.open(root, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(directory_fd)
        finally:
            os.close(directory_fd)
    except (Exception, KeyboardInterrupt):
        result['result_receipt_saved'] = False
        raw = json.dumps(result, ensure_ascii=False, sort_keys=True)
    print(raw, flush=True)
    if sys.platform == 'darwin':
        try:
            subprocess.run(['/usr/bin/pbcopy'], input=raw, text=True, check=True, timeout=10)
        except (Exception, KeyboardInterrupt):
            return 1
    return 0 if result.get('deployment_performed') is True else 1


if __name__ == '__main__':
    print('hash_pinned_owner_bootstrap_required')
    raise SystemExit(2)
