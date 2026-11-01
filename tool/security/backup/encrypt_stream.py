#!/usr/bin/env python3
"""Encrypt an explicitly supplied backup stream; never export production data."""
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


def encrypt(recipient_file, output):
    executable = shutil.which('age')
    if executable is None:
        raise ValueError('age_required')
    recipient = Path(recipient_file).read_text(encoding='ascii').strip()
    if not re.fullmatch(r'age1[023456789acdefghjklmnpqrstuvwxyz]{58}', recipient):
        raise ValueError('one_native_age_public_recipient_required')
    output = Path(output)
    if output.exists() or output.is_symlink() or not output.parent.is_dir():
        raise ValueError('new_output_in_existing_directory_required')
    if sys.stdin.isatty():
        raise ValueError('backup_stream_required')
    descriptor, temporary = tempfile.mkstemp(prefix='.sko-encrypted-', dir=output.parent)
    try:
        with os.fdopen(descriptor, 'wb') as encrypted:
            result = subprocess.run([executable, '--encrypt', '--recipient', recipient],
                                    stdin=sys.stdin.buffer, stdout=encrypted,
                                    stderr=subprocess.DEVNULL, check=False)
            if result.returncode != 0:
                raise ValueError('encryption_failed')
            encrypted.flush()
            os.fsync(encrypted.fileno())
        # A hard link publishes the complete ciphertext without overwriting even
        # if another writer created the destination after the initial check.
        os.link(temporary, output)
    finally:
        Path(temporary).unlink(missing_ok=True)
    digest = hashlib.sha256()
    with output.open('rb') as encrypted:
        for chunk in iter(lambda: encrypted.read(1024 * 1024), b''):
            digest.update(chunk)
    return {'schema': 1, 'encrypted_sha256': digest.hexdigest(),
            'restoration_verified': False, 'production_export_performed': False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--recipient-file', required=True)
    parser.add_argument('--output', required=True)
    args = parser.parse_args()
    try:
        result = encrypt(args.recipient_file, args.output)
    except (OSError, UnicodeError, ValueError, subprocess.SubprocessError):
        print('Encrypted backup could not be completed; no success is recorded.', file=sys.stderr)
        return 1
    print(json.dumps(result))
    return 0


if __name__ == '__main__':
    sys.exit(main())
