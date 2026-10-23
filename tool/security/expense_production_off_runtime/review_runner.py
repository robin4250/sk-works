#!/usr/bin/env python3
"""Review candidate: one-shot orchestration with offline/mock transport only.

No production adapter, connection, password acquisition or gate enable path is
provided. A later reviewed transport must use a dedicated session, search_path
public and the exact immutable SQL; READ ONLY classification uses a NEW session.
"""
from __future__ import annotations

from contextlib import contextmanager
import fcntl
import hashlib
import json
import os
from pathlib import Path
import subprocess
import stat
import tempfile
from typing import Protocol

MAX_BYTES = 16_777_216
MARKER = 'expense-default-off-install-attempt.json'
FILES = ('private-fresh-before.json', 'private-prepared-install.sql.review-only',
         'private-read-actual-after.sql.read-only')
RUNTIME = Path(__file__).parent


class Refused(RuntimeError):
    pass


class ReviewTransport(Protocol):
    """Only synthetic implementations are included; no arbitrary shell/SQL CLI."""
    def execute_install_once(self, sql: bytes) -> None: ...
    def capture_readonly(self, sql: bytes) -> bytes: ...


def sha(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def private_directory(path: Path) -> None:
    if not path.is_absolute() or '..' in path.parts:
        raise Refused('absolute_private_path_required')
    if any(p.is_symlink() for p in (path, *path.parents)):
        raise Refused('symlink_refused')
    st = path.stat()
    if not path.is_dir() or st.st_uid != os.getuid() or st.st_mode & 0o077:
        raise Refused('private_directory_required')


def read_private(path: Path) -> bytes:
    private_directory(path.parent)
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    try:
        st = os.fstat(fd)
        if not stat.S_ISREG(st.st_mode) or st.st_uid != os.getuid() or st.st_mode & 0o077 or not 0 < st.st_size <= MAX_BYTES:
            raise Refused('private_file_required')
        data = os.read(fd, MAX_BYTES + 1)
        if len(data) != st.st_size:
            raise Refused('private_file_changed')
        return data
    finally:
        os.close(fd)


def fsync_directory(path: Path) -> None:
    fd = os.open(path, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def write_new(path: Path, value: bytes) -> None:
    private_directory(path.parent)
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    try:
        with os.fdopen(fd, 'wb', closefd=False) as stream:
            stream.write(value)
            stream.flush()
            os.fsync(fd)
    finally:
        os.close(fd)
    fsync_directory(path.parent)


def atomic_state(path: Path, value: dict) -> None:
    private_directory(path.parent)
    # The permanent marker is never unlinked/rearmed, even for a proven rollback.
    if path.is_symlink():
        raise Refused('marker_symlink_refused')
    fd, name = tempfile.mkstemp(prefix='expense-state-', dir=path.parent)
    temporary = Path(name)
    try:
        with os.fdopen(fd, 'wb') as stream:
            stream.write(json.dumps(value, sort_keys=True).encode())
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
        fsync_directory(path.parent)
    finally:
        if temporary.exists():
            temporary.unlink()


@contextmanager
def operation_lock(root: Path):
    private_directory(root)
    fd = os.open(root / 'expense-default-off-runner.lock',
                 os.O_WRONLY | os.O_CREAT | os.O_NOFOLLOW, 0o600)
    try:
        st = os.fstat(fd)
        if st.st_uid != os.getuid() or st.st_mode & 0o077:
            raise Refused('private_lock_required')
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise Refused('operation_in_progress') from error
        yield
    finally:
        os.close(fd)


def generator(node: str, stage: Path, mode: str) -> None:
    result = subprocess.run([node, str(RUNTIME / 'offline_generator.mjs'), mode, str(stage)],
        stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        env={'PATH': os.environ.get('PATH', '')}, timeout=30)
    if result.returncode:
        raise Refused('offline_generator_refused')


def validated_copy(source: Path, root: Path, node: str) -> Path:
    private_directory(source)
    status = json.loads(read_private(source / 'prepare-status.json'))
    if status.get('verified') is not True or status.get('prepare_only') is not True or \
       status.get('production_connected') is not False:
        raise Refused('prepared_status_not_verified')
    contents = {name: read_private(source / name) for name in FILES}
    if sha(contents[FILES[0]]) != status.get('source_checkpoint_sha256'):
        raise Refused('before_hash_differs')
    for name in FILES[1:]:
        item = status.get('artifacts', {}).get(name, {})
        if sha(contents[name]) != item.get('sha256') or len(contents[name]) != item.get('bytes'):
            raise Refused('prepared_hash_differs')
    stage = Path(tempfile.mkdtemp(prefix='expense-production-off-review-', dir=root))
    for name, value in contents.items():
        write_new(stage / name, value)
    write_new(stage / 'prepare-status.json', read_private(source / 'prepare-status.json'))
    generator(node, stage, 'verify')
    verified = json.loads(read_private(stage / 'private-verified-plan.json'))
    if verified.get('verified') is not True or verified.get('install_sha256') != sha(contents[FILES[1]]) \
       or verified.get('read_after_sha256') != sha(contents[FILES[2]]):
        raise Refused('generated_plan_hash_differs')
    return stage


def classify(root: Path, state: dict, transport: ReviewTransport, node: str) -> dict:
    # Historical evidence stays immutable, but no earlier undo is current evidence
    # for a new observation (including a failure before any new read can run).
    for key in ('unused_undo', 'unused_undo_sha256', 'observation'):
        state.pop(key, None)
    state.update(phase='read_only_classification_pending', retry_allowed=False)
    atomic_state(root / MARKER, state)
    original = Path(state['stage'])
    private_directory(original)
    if original.parent != root:
        raise Refused('marker_stage_outside_root')
    # Recovery produces fresh evidence; originals and earlier actual-after stay immutable.
    stage = Path(tempfile.mkdtemp(prefix='expense-production-off-observation-', dir=root))
    for name in FILES:
        value = read_private(original / name)
        if sha(value) != state['artifacts'][name]:
            raise Refused('attempt_artifact_changed')
        write_new(stage / name, value)
    generator(node, stage, 'verify')
    state['phase'] = 'read_only_classification_pending'
    atomic_state(root / MARKER, state)
    try:
        result = transport.capture_readonly(read_private(stage / FILES[2]))
        if not isinstance(result, bytes) or not 0 < len(result) <= MAX_BYTES:
            raise Refused('readonly_result_invalid')
        # Read-only/metadata/source/OID checks are delegated to the original plan module.
        write_new(stage / 'private-production-actual-after.json', result)
        generator(node, stage, 'classify')
        observed = json.loads(read_private(stage / 'classification.json'))
        state.update(phase=observed['state'], observation=str(stage), retry_allowed=False)
        undo = stage / 'private-production-unused-undo.sql.review-only'
        if undo.exists():
            raw = read_private(undo)
            # No undo is ever executed here. fsync the generator-created private artifact.
            with undo.open('rb') as stream:
                os.fsync(stream.fileno())
            fsync_directory(stage)
            state.update(unused_undo=str(undo), unused_undo_sha256=sha(raw))
    except (Exception, KeyboardInterrupt):
        state.update(phase='state_requires_review', observation=str(stage), retry_allowed=False)
    atomic_state(root / MARKER, state)
    return state.copy()


def install_review_once(source: Path, root: Path, transport: ReviewTransport, node: str) -> dict:
    """Review harness only. One exact original BEGIN/COMMIT submission, never retries."""
    with operation_lock(root):
        if (root / MARKER).exists() or (root / MARKER).is_symlink():
            raise Refused('previous_attempt_requires_readonly_recovery')
        stage = validated_copy(source, root, node)
        state = {'schema': 1, 'review_candidate': True, 'stage': str(stage),
            'artifacts': {name: sha(read_private(stage / name)) for name in FILES},
            'phase': 'install_submission_pending', 'retry_allowed': False,
            'commit_acknowledged': False}
        # Crash/disconnect after this fsync is treated as unknown, even before submission.
        write_new(root / MARKER, json.dumps(state, sort_keys=True).encode())
        try:
            transport.execute_install_once(read_private(stage / FILES[1]))
            state.update(phase='commit_acknowledged', commit_acknowledged=True)
        except (Exception, KeyboardInterrupt):
            state['phase'] = 'commit_unknown'
        atomic_state(root / MARKER, state)
        return classify(root, state, transport, node)


def recover_review_readonly(root: Path, transport: ReviewTransport, node: str) -> dict:
    """Cannot execute or resubmit install SQL; marker is kept after every outcome."""
    with operation_lock(root):
        state = json.loads(read_private(root / MARKER))
        if state.get('schema') != 1 or state.get('retry_allowed') is not False:
            raise Refused('attempt_marker_invalid')
        return classify(root, state, transport, node)


def main() -> int:
    # No injectable endpoint, password, psql, CLI auth or production transport in CLI.
    print('実行不可：経費OFF導入runnerのレビュー候補です。本番adapter・接続・導入は未対応です。')
    return 2


if __name__ == '__main__':
    raise SystemExit(main())
