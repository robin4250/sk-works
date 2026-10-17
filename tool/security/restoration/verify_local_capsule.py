#!/usr/bin/env python3
"""Offline archive inventory only. Never connects, restores, or authorizes apply."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile


REQUIRED = {
    ('auth', 'users'), ('auth', 'identities'), ('auth', 'sessions'),
    ('public', 'companies'), ('public', 'company_members'),
    ('public', 'member_feature_permissions'), ('public', 'workers'),
    ('public', 'worker_personnel_profiles'), ('public', 'worker_family_members'),
    ('private', 'master_admins'),
}


def inventory(toc):
    tables, extensions = set(), set()
    for line in toc.splitlines():
        # PostgreSQL TOC metadata only; not rows or an executable SQL parser.
        m = re.match(r'^\d+;\s+\d+\s+\d+\s+TABLE\s+(?!DATA\s|ATTACH\s)(\S+)\s+(\S+)\s+', line)
        if m:
            tables.add((m.group(1), m.group(2)))
        m = re.match(r'^\d+;\s+\d+\s+\d+\s+EXTENSION\s+-\s+(\S+)', line)
        if m:
            extensions.add(m.group(1))
    return tables, extensions


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--archive', required=True, type=Path)
    parser.add_argument('--pg-bin', required=True, type=Path)
    args = parser.parse_args()
    os.umask(0o077)
    evidence = Path(tempfile.mkdtemp(prefix='sko-capsule-preflight-'))
    evidence.chmod(0o700)
    # No PGHOST/PGSERVICE/PGPASSWORD/PSQLRC/BASH_ENV inherited by subprocesses.
    env = {k: v for k, v in os.environ.items()
           if not k.upper().startswith('PG') and k not in ('PSQLRC', 'BASH_ENV', 'ENV')}
    env.update({'LC_ALL': 'C', 'LANG': 'C'})
    try:
        archive = args.archive
        if not archive.is_absolute() or archive.is_symlink() or not archive.is_file():
            raise ValueError('archive must be an existing absolute regular non-symlink path')
        binary = args.pg_bin / 'pg_restore'
        if not binary.is_absolute() or not binary.is_file():
            raise ValueError('explicit absolute pg_restore required')
        with archive.open('rb') as source:
            if source.read(5) != b'PGDMP':
                raise ValueError('custom archive required')
        with (evidence / 'private-error.log').open('wb') as errors:
            version = subprocess.check_output([str(binary), '--version'], env=env, stderr=errors, timeout=20)
            if not re.search(rb'\b17\.', version):
                raise ValueError('PostgreSQL 17 required')
            with (evidence / 'private-toc.txt').open('wb') as output:
                subprocess.run([str(binary), '--list', str(archive)], env=env,
                               stdout=output, stderr=errors, timeout=120, check=True)
            # Extraction to a NEW private file only; never sends SQL to a server.
            subprocess.run([str(binary), '--schema-only', '--file', str(evidence / 'private-schema.sql'), str(archive)],
                           env=env, stdout=errors, stderr=errors, timeout=120, check=True)
        tables, extensions = inventory((evidence / 'private-toc.txt').read_text())
        missing = REQUIRED - tables
        with archive.open('rb') as source:
            digest = hashlib.file_digest(source, 'sha256').hexdigest()
        report = {
            'scope': 'offline archive inventory; no database was started or contacted',
            'archive_sha256': digest, 'table_count': len(tables),
            'extensions': sorted(extensions), 'missing_expected_tables': sorted(missing),
            'full_restore_verified': False, 'subset_restore_verified': False,
            'roles_acl_recovery_verified': False, 'candidate_apply_verified': False,
            'production_connections': 0, 'production_writes': 0,
            'required_next_review': [
                'Resolve the exact personnel authorization dependency subgraph from private schema SQL.',
                'Obtain original role definitions/attributes/memberships in a separately protected capsule.',
                'Select only necessary extension dependencies; unrelated extensions do not block a bounded subset claim.',
                'Verify outbound isolation independently before executing any archived SQL.',
                'Restore exact selected definitions/ACL/dependencies without permissive stubs; compare protected rows internally.',
                'Exercise all three reviewed migrations and exact rollback in disposable isolation only.',
            ],
        }
        (evidence / 'private-manifest.json').write_text(json.dumps(report, indent=2))
        print('PREFLIGHT ONLY: archive inventory extracted privately. Restore/apply NOT performed. Production connections/writes: 0.')
        print('STOP: dependency, role/ACL capsule and outbound-isolation review required before restore.')
        print('Private evidence: ' + str(evidence))
        return 2
    except Exception as error:
        # Exceptions may contain account names, SQL or connection data: type only.
        print('STOP: offline preflight incomplete (' + type(error).__name__ + '). No restore or database connection performed.')
        print('Private evidence: ' + str(evidence))
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
