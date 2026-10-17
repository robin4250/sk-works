#!/usr/bin/env python3
"""Offline fixed-class summary; never prints private log text or stored values."""
import argparse
import json
import os
from pathlib import Path


def classify(text):
    text = text.lower()
    checks = [
        ('private_schema_permission_denied', 'permission denied for schema private'),
        ('set_role_denied', 'permission denied to set role'),
        ('authentication_rejected', 'password authentication failed'),
        ('statement_timeout', 'canceling statement due to statement timeout'),
        ('permission_denied', 'permission denied'),
        ('connection_refused', 'connection refused'),
        ('connection_timeout', 'timeout expired'),
        ('dns_failure', 'could not translate host name'),
        ('connection_closed', 'server closed the connection unexpectedly'),
        ('sql_syntax', 'syntax error'),
        ('catalog_unsupported', 'unrecognized object class'),
    ]
    for category, marker in checks:
        if marker in text:
            return category
    if 'column' in text and 'does not exist' in text:
        return 'missing_column'
    if 'relation' in text and 'does not exist' in text:
        return 'missing_relation'
    return 'unclassified_private_review_required'


def inspect(root):
    if not root.is_absolute() or root.is_symlink() or not root.is_dir():
        raise ValueError('private directory required')
    state = root.stat()
    if state.st_uid != os.getuid() or state.st_mode & 0o077:
        raise ValueError('private owned directory required')
    filenames = ['private-before.json', 'private-catalog.json',
                 'private-schema.dump', 'private-after.json']
    statuses = []
    for name in filenames:
        path = root / name
        if path.is_symlink():
            raise ValueError('unexpected symlink')
        if not path.exists():
            statuses.append('absent')
        elif not path.is_file() or path.stat().st_uid != os.getuid():
            raise ValueError('private regular file required')
        elif path.stat().st_size == 0:
            statuses.append('empty')
        elif name.endswith('.dump'):
            statuses.append('nonempty_not_verified')
        else:
            # Decode only to decide completeness; never return private values.
            try:
                lines = path.read_text().splitlines()
                if not lines or lines[0] != 't':
                    statuses.append('read_only_marker_missing')
                else:
                    json.loads('\n'.join(lines[1:]))
                    statuses.append('read_only_json_complete')
            except (ValueError, UnicodeError):
                statuses.append('partial_not_verified')
    log = root / 'private-errors.log'
    if log.is_symlink() or not log.is_file() or log.stat().st_uid != os.getuid():
        raise ValueError('private error log unavailable')
    category = classify(log.read_text(errors='replace'))
    stages = ['initial_identity_read', 'catalog_read', 'schema_export', 'final_identity_read']
    stage = 'post_collection_validation_or_shutdown'
    for index, status in enumerate(statuses):
        if status not in ('read_only_json_complete', 'nonempty_not_verified'):
            stage = stages[index]
            break
    return {'stage_hint': stage, 'error_class': category,
            'file_states': statuses, 'database_connections_performed': 0,
            'private_values_printed': 0, 'retry_authorized': False}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', type=Path)
    args = parser.parse_args()
    try:
        print(json.dumps(inspect(args.directory), sort_keys=True))
    except Exception as error:
        print(json.dumps({'status': 'STOP', 'error_type': type(error).__name__,
                          'private_log_text_printed': False}))
        raise SystemExit(1)
