#!/usr/bin/env python3
"""Offline reconciliation only; never starts a DB or executes archived SQL."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

NAMES = {'private-before.json', 'private-catalog.json', 'private-after.json'}
REQUIRED = {('auth','users'), ('auth','identities'), ('auth','sessions'),
            ('private','master_admins'), ('public','companies'), ('public','company_members'),
            ('public','workers'), ('public','member_feature_permissions'),
            ('public','worker_personnel_profiles'), ('public','worker_family_members')}


def private_file(path):
    if not path.is_absolute() or path.is_symlink() or not path.is_file():
        raise ValueError('private regular file required')
    st = path.stat()
    if st.st_uid != os.getuid() or st.st_mode & 0o077:
        raise ValueError('private owner permissions required')
    return path


def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as source:
        for part in iter(lambda: source.read(1024*1024), b''):
            h.update(part)
    return h.hexdigest()


def verify_capsule(root):
    if not root.is_absolute() or root.is_symlink() or not root.is_dir():
        raise ValueError('private directory required')
    st = root.stat()
    if st.st_uid != os.getuid() or st.st_mode & 0o077:
        raise ValueError('private directory permissions required')
    manifest = json.loads(private_file(root / 'private-manifest.json').read_text())
    if (manifest.get('read_only_api') is not True or type(manifest.get('production_writes')) is not int
            or manifest.get('production_writes') != 0):
        raise ValueError('read-only collection manifest required')
    if manifest.get('schema_archive_created') is not False or manifest.get('restoration_verified') is not False:
        raise ValueError('scope mismatch')
    files = manifest.get('files')
    if not isinstance(files, dict) or set(files) != NAMES:
        raise ValueError('fixed file set required')
    values = {}
    for name in sorted(NAMES):
        path = private_file(root / name)
        if not isinstance(files[name], str) or not re.fullmatch(r'[a-f0-9]{64}', files[name]) or digest(path) != files[name]:
            raise ValueError('collection hash mismatch')
        value = json.loads(path.read_text())
        if not isinstance(value, dict) or value.get('read_only') is not True or not isinstance(value.get('payload'), dict):
            raise ValueError('read-only result evidence required')
        values[name] = value
    if values['private-before.json'] != values['private-after.json']:
        raise ValueError('identity membership mismatch')
    return values


def inspect_toc(text, values):
    tables = set()
    for line in text.splitlines():
        m = re.match(r'^\d+;\s+\d+\s+\d+\s+TABLE\s+(?!DATA\s|ATTACH\s)(\S+)\s+(\S+)\s+', line)
        if m:
            tables.add((m.group(1), m.group(2)))
    catalog = values['private-catalog.json']['payload']
    objects = catalog.get('objects')
    if not isinstance(objects, list):
        raise ValueError('catalog objects missing')
    live_tables = {(x.get('schema'), x.get('name')) for x in objects
                   if isinstance(x, dict) and x.get('type') == 'table'}
    return {'archive_table_count':len(tables), 'live_catalog_table_count':len(live_tables),
            'missing_required_table_count':len(REQUIRED - tables),
            'live_tables_absent_from_archive_count':len(live_tables - tables),
            'complete_database_restore_verified':False, 'subset_restore_verified':False,
            'role_acl_restore_verified':False, 'time_gap_closed':False,
            'production_connections':0, 'production_writes':0,
            'unverified':['archive-time data vs collection-time data', 'current exact SQL definitions and RLS',
                          'role settings/passwords/default and column ACL', 'native isolated restoration',
                          'administrator and provider login', 'outbound isolation before executing any SQL']}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--capsule', required=True, type=Path)
    p.add_argument('--archive', required=True, type=Path)
    p.add_argument('--pg-bin', required=True, type=Path)
    p.add_argument('--output-parent', type=Path, default=Path.home()/'SKO-source-backups')
    args = p.parse_args()
    os.umask(0o077)
    evidence = None
    try:
        values = verify_capsule(args.capsule)
        archive = private_file(args.archive)
        binary = args.pg_bin / 'pg_restore'
        if not binary.is_absolute() or not binary.is_file():
            raise ValueError('explicit pg_restore required')
        with archive.open('rb') as source:
            if source.read(5) != b'PGDMP':
                raise ValueError('custom archive required')
        parent = args.output_parent
        if not parent.is_absolute() or parent.is_symlink() or not parent.is_dir():
            raise ValueError('existing absolute backup parent required')
        st = parent.stat()
        if st.st_uid != os.getuid() or st.st_mode & 0o022:
            raise ValueError('owned non-writable-by-others parent required')
        evidence = Path(tempfile.mkdtemp(prefix='entry-check-',dir=str(parent)))
        evidence.chmod(0o700)
        env = {k:v for k,v in os.environ.items() if not k.upper().startswith('PG')
               and k not in ('PSQLRC','ENV','BASH_ENV','SUPABASE_ACCESS_TOKEN')}
        env.update({'LC_ALL':'C','LANG':'C'})
        before = digest(archive)
        with (evidence / 'private-errors.log').open('wb') as errors:
            version = subprocess.check_output([str(binary),'--version'], env=env, stderr=errors, timeout=20)
            if not re.search(rb'\b17\.',version):
                raise ValueError('PostgreSQL 17 required')
            with (evidence / 'private-toc.txt').open('wb') as out:
                subprocess.run([str(binary),'--list',str(archive)],env=env,stdout=out,stderr=errors,timeout=120,check=True)
        if digest(archive) != before:
            raise ValueError('archive changed during inventory')
        report = inspect_toc((evidence / 'private-toc.txt').read_text(),values)
        report.update({'archive_sha256':before,
                       'archive_file_mtime_ns':archive.stat().st_mtime_ns,
                       'collection_file_mtime_ns':(args.capsule/'private-before.json').stat().st_mtime_ns,
                       'file_times_are_not_database_snapshot_times':True})
        (evidence / 'private-comparison.json').write_text(json.dumps(report,indent=2))
        summary = {k:report[k] for k in ('missing_required_table_count','live_tables_absent_from_archive_count',
                                        'time_gap_closed','subset_restore_verified','production_connections','production_writes')}
        print('OFFLINE INVENTORY ONLY: '+json.dumps(summary))
        print('No database started; no archived SQL executed. Full/subset restoration and current data recovery: NOT verified.')
        print('Private evidence: '+str(evidence))
        return 2
    except Exception as error:
        print('STOP: offline comparison incomplete ('+type(error).__name__+'). No database start or restoration performed.')
        if evidence is not None:
            print('Private evidence: '+str(evidence))
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
