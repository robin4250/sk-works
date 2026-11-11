"""Private append-only-by-convention receipt publisher. No database operations.

Exclusive atomic publication prevents overwrite/partial final receipts. This is
not WORM storage: the filesystem owner can still remove or modify files.
"""
import hashlib
import json
import os
from pathlib import Path
import stat
import uuid


def save_receipt(directory, payload, *, receipt_id=None):
    directory = Path(directory)
    directory.mkdir(mode=0o700, parents=False, exist_ok=True)
    info = directory.lstat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) != 0o700:
        raise ValueError('Receipt directory must be an owned real directory with mode 0700')
    required = {'scope', 'phase', 'artifact_sha256', 'approval_reference', 'evidence_sha256'}
    if not isinstance(payload, dict) or not required.issubset(payload):
        raise ValueError('Receipt fields missing')
    if payload['phase'] not in {'prepared', 'approved', 'commit_unknown', 'commit_confirmed', 'readback_confirmed', 'failed'}:
        raise ValueError('Unknown receipt phase')
    for field in ['artifact_sha256', 'evidence_sha256']:
        value = payload[field]
        if not isinstance(value, str) or len(value) != 64 or any(x not in '0123456789abcdef' for x in value):
            raise ValueError('Expected lowercase SHA256')
    if payload['phase'] != 'prepared' and not payload['approval_reference']:
        raise ValueError('Approval reference required')
    identity = receipt_id or uuid.uuid4().hex
    if not isinstance(identity, str) or not identity or any(c not in '0123456789abcdef-' for c in identity):
        raise ValueError('Unsafe receipt identity')
    content = (json.dumps(payload, ensure_ascii=False, sort_keys=True, indent=2) + '\n').encode()
    target = directory / (identity + '.json')
    pending = directory / ('.pending-' + uuid.uuid4().hex)
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, 'O_NOFOLLOW', 0)
    fd = os.open(pending, flags, 0o600)
    published = False
    try:
        with os.fdopen(fd, 'wb') as stream:
            stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())
        # Atomic link publication fails if the final name already exists.
        os.link(pending, target, follow_symlinks=False)
        published = True
        dirfd = os.open(directory, os.O_RDONLY | getattr(os, 'O_DIRECTORY', 0))
        try:
            os.fsync(dirfd)
        finally:
            os.close(dirfd)
    finally:
        # Remove only this call's exclusively-created staging file.
        pending.unlink(missing_ok=True)
    if not published:
        raise RuntimeError('Receipt was not published')
    return {'receipt': str(target), 'sha256': hashlib.sha256(content).hexdigest()}
