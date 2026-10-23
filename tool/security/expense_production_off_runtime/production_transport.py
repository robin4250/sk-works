"""Dedicated adapter; deployment binding intentionally unset pending root review.

No connection or credential discovery. No fallback to fixture URLs/CLI auth.
"""
from __future__ import annotations
import hashlib
import json
import os
from pathlib import Path
import subprocess
import stat
from review_runner import (FILES, MAX_BYTES, Refused, RUNTIME, install_review_once,
                           recover_review_readonly, private_directory, read_private)
from production_transport_binding import APPROVED_DURABLE_ROOT, APPROVED_MANIFEST_SHA256

PROJECT = 'ztktgquxvcxcjxtluspu'
HOST = 'db.' + PROJECT + '.supabase.co'
NODE = Path('/usr/bin/node')
TRANSPORT_FILES = ('production_transport.py', 'production_transport_core.mjs',
                   'production_transport_worker.mjs')


def _sha(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def dependency_tree_sha256(root: Path) -> str:
    """Approve the installed pinned dependency bytes, not package names alone."""
    entries = []
    for path in sorted(root.rglob('*')):
        if path.is_symlink():
            raise Refused('dependency_symlink_refused')
        if path.is_file():
            entries.append([str(path.relative_to(root)), _sha(path.read_bytes())])
    if not entries:
        raise Refused('dependency_tree_missing')
    return _sha(json.dumps(entries, separators=(',', ':')).encode())


def _binding() -> dict:
    if APPROVED_DURABLE_ROOT is None or APPROVED_MANIFEST_SHA256 is None:
        raise Refused('production_binding_not_approved')
    root = APPROVED_DURABLE_ROOT
    private_directory(root)
    raw = read_private(root / 'production-approval.json')
    if _sha(raw) != APPROVED_MANIFEST_SHA256:
        raise Refused('production_approval_hash_differs')
    value = json.loads(raw)
    if set(value) != {'schema', 'project', 'host', 'role', 'database', 'root',
                     'artifacts', 'transport_files', 'node_sha256', 'pg_dependency_tree_sha256'} or \
       value['schema'] != 1 or value['project'] != PROJECT or value['host'] != HOST or \
       value['role'] != 'postgres' or value['database'] != 'postgres' or value['root'] != str(root):
        raise Refused('production_binding_refused')
    if set(value['artifacts']) != {*FILES, 'prepare-status.json'} or \
       set(value['transport_files']) != set(TRANSPORT_FILES):
        raise Refused('production_hash_set_refused')
    for name in (*FILES, 'prepare-status.json'):
        if _sha(read_private(root / 'prepared' / name)) != value['artifacts'][name]:
            raise Refused('approved_artifact_differs')
    for name in TRANSPORT_FILES:
        path = RUNTIME / name
        if path.is_symlink() or _sha(path.read_bytes()) != value['transport_files'][name]:
            raise Refused('approved_transport_differs')
    if not NODE.is_absolute() or not NODE.is_file() or _sha(NODE.read_bytes()) != value['node_sha256']:
        raise Refused('approved_node_differs')
    dependencies = RUNTIME.parent / 'fixture_dependencies' / 'node_modules'
    if dependencies.is_symlink() or dependency_tree_sha256(dependencies) != value['pg_dependency_tree_sha256']:
        raise Refused('approved_dependencies_differ')
    return value


def _read_password(fd: int) -> bytes:
    # Only an explicitly handed-off descriptor. Never search files/env/keychains.
    if not isinstance(fd, int) or fd < 3:
        raise Refused('private_credential_descriptor_required')
    metadata = os.fstat(fd)
    if not stat.S_ISREG(metadata.st_mode) or metadata.st_uid != os.getuid() or \
       metadata.st_mode & 0o077 or not 0 < metadata.st_size <= 1024:
        raise Refused('private_credential_descriptor_required')
    value = os.pread(fd, metadata.st_size + 1, 0)
    if len(value) != metadata.st_size:
        raise Refused('credential_changed')
    if not value or len(value) > 1024 or any(c in value for c in (b'\0', b'\r', b'\n')):
        raise Refused('credential_refused')
    try:
        value.decode('utf-8')
    except UnicodeError:
        raise Refused('credential_refused') from None
    return value


class _DedicatedTransport:
    def __init__(self, binding: dict, password: bytes):
        self._binding, self._password = binding, password
        self._install_started = False

    def _request(self, mode: str, sql: bytes) -> bytes:
        name = FILES[1] if mode == 'install' else FILES[2]
        if not isinstance(sql, bytes) or not 0 < len(sql) <= MAX_BYTES or \
           _sha(sql) != self._binding['artifacts'][name]:
            raise Refused('approved_sql_differs')
        request = json.dumps({'mode': mode, 'sql': sql.decode('utf-8'),
            'sha256': _sha(sql), 'password': self._password.decode('utf-8')}).encode()
        try:
            result = subprocess.run([str(NODE), str(RUNTIME / 'production_transport_worker.mjs')],
                input=request, capture_output=True, env={'LANG': 'C.UTF-8'},
                cwd=RUNTIME, timeout=45, close_fds=True)
        except (Exception, KeyboardInterrupt):
            raise ConnectionError('production_transport_unknown') from None
        if result.returncode or result.stderr or not 0 < len(result.stdout) <= MAX_BYTES:
            raise ConnectionError('production_transport_unknown')
        return result.stdout

    def execute_install_once(self, sql: bytes) -> None:
        if self._install_started:
            raise Refused('transport_install_already_attempted')
        # Mark before any process creation, including failed/timeout attempts.
        self._install_started = True
        if self._request('install', sql) != b'{"acknowledged":true}':
            raise ConnectionError('production_commit_unknown')

    def capture_readonly(self, sql: bytes) -> bytes:
        # Every request creates and terminates a separate dedicated pg.Client.
        return self._request('read-only', sql)


def install_approved_once(password_fd: int) -> dict:
    binding = _binding()  # Reject unapproved hashes/root BEFORE reading credentials.
    transport = _DedicatedTransport(binding, _read_password(password_fd))
    return install_review_once(APPROVED_DURABLE_ROOT / 'prepared',
        APPROVED_DURABLE_ROOT, transport, str(NODE))


def recover_approved_readonly(password_fd: int) -> dict:
    binding = _binding()
    transport = _DedicatedTransport(binding, _read_password(password_fd))
    return recover_review_readonly(APPROVED_DURABLE_ROOT, transport, str(NODE))


if __name__ == '__main__':
    # No generic operator CLI or hidden activation switch is introduced.
    print('production_operator_binding_required')
    raise SystemExit(2)
