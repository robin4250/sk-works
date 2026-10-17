#!/usr/bin/env python3
"""Operator-Mac-only read-only collection candidate. Never restores or deploys."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import tempfile

KEYS = {'PGHOST', 'PGPORT', 'PGUSER', 'PGPASSWORD', 'PGDATABASE'}
PROJECT = 'ztktgquxvcxcjxtluspu'
INVARIANTS = """
SELECT jsonb_build_object(
 'masters',(SELECT jsonb_agg(jsonb_build_object('user',to_jsonb(t)->'user_id','enabled',to_jsonb(t)->'enabled') ORDER BY to_jsonb(t)->>'user_id') FROM private.master_admins t),
 'memberships',(SELECT jsonb_agg(jsonb_build_object('company',to_jsonb(t)->'company_id','user',to_jsonb(t)->'user_id','role',to_jsonb(t)->'role') ORDER BY to_jsonb(t)->>'company_id',to_jsonb(t)->>'user_id') FROM public.company_members t),
 'companies',(SELECT jsonb_agg(to_jsonb(t)->'id' ORDER BY to_jsonb(t)->>'id') FROM public.companies t),
 'users',(SELECT jsonb_agg(to_jsonb(t)->'id' ORDER BY to_jsonb(t)->>'id') FROM auth.users t),
 'providers',(SELECT jsonb_agg(jsonb_build_object('user',to_jsonb(t)->'user_id','provider',to_jsonb(t)->'provider') ORDER BY to_jsonb(t)->>'user_id',to_jsonb(t)->>'provider') FROM auth.identities t)
);
"""


def parse_plan(text):
    result = {}
    for line in text.splitlines():
        if not re.match(r'^\s*(?:export\s+)?PG[A-Z]+=', line):
            continue
        tokens = shlex.split(line, comments=True)
        if tokens and tokens[0] == 'export':
            tokens = tokens[1:]
        for token in tokens:
            name, separator, value = token.partition('=')
            if name not in KEYS:
                continue
            if not separator or any(x in value for x in ('${', '$(', '`')):
                raise ValueError('non-static plan value')
            if name in result and result[name] != value:
                raise ValueError('conflicting plan values')
            result[name] = value
    if set(result) != KEYS or not all(result.values()):
        raise ValueError('five static connection items required')
    direct = result['PGHOST'] == 'db.' + PROJECT + '.supabase.co'
    pool = (re.fullmatch(r'aws-\d+-[a-z0-9-]+\.pooler\.supabase\.com', result['PGHOST'])
            and result['PGUSER'].endswith('.' + PROJECT))
    if not (direct or pool):
        raise ValueError('project binding not established')
    if not result['PGPORT'].isdigit() or not 1 <= int(result['PGPORT']) <= 65535:
        raise ValueError('invalid port')
    return result


def transaction(sql):
    return ("BEGIN READ ONLY; SET LOCAL statement_timeout='45s'; "
            "SET LOCAL lock_timeout='5s'; SET LOCAL idle_in_transaction_session_timeout='60s'; "
            "SELECT current_setting('transaction_read_only')='on' AS read_only; "
            + sql + '\nCOMMIT;')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--plan', required=True, type=Path)
    parser.add_argument('--pg-bin', required=True, type=Path)
    args = parser.parse_args()
    os.umask(0o077)
    root = Path(tempfile.mkdtemp(prefix='sko-private-capsule-'))
    root.chmod(0o700)
    try:
        if not args.plan.is_absolute() or args.plan.is_symlink() or not args.plan.is_file():
            raise ValueError('private absolute regular plan required')
        st = args.plan.stat()
        if st.st_uid != os.getuid() or st.st_mode & 0o077:
            raise ValueError('plan permissions must be private')
        env = {k: v for k, v in os.environ.items()
               if not k.upper().startswith('PG') and k not in ('PSQLRC', 'BASH_ENV', 'ENV')}
        env.update(parse_plan(args.plan.read_text()))
        env.update({'PGSSLMODE': 'require', 'PGCONNECT_TIMEOUT': '15',
                    'PGAPPNAME': 'sko-readonly-private-capsule',
                    'PGOPTIONS': '-c default_transaction_read_only=on -c statement_timeout=45000 -c lock_timeout=5000',
                    'LC_ALL': 'C', 'LANG': 'C'})
        binaries = [args.pg_bin / name for name in ('psql', 'pg_dump')]
        if not all(p.is_absolute() and p.is_file() for p in binaries):
            raise ValueError('explicit native PostgreSQL tools required')
        psql, dump = binaries
        with (root / 'private-errors.log').open('wb') as errors:
            for binary in binaries:
                version = subprocess.check_output([str(binary), '--version'], env=env, stderr=errors, timeout=20)
                if not re.search(rb'\b17\.', version):
                    raise ValueError('PostgreSQL 17 required')
            def query(sql, output):
                with output.open('wb') as out:
                    subprocess.run([str(psql), '-X', '-w', '-qAt', '-v', 'ON_ERROR_STOP=1', '-c', transaction(sql)],
                                   env=env, stdout=out, stderr=errors, timeout=90, check=True)
                lines = output.read_text().splitlines()
                if not lines or lines[0] != 't':
                    raise ValueError('read-only verification missing')
                return json.loads('\n'.join(lines[1:]))
            before = query(INVARIANTS, root / 'private-before.json')
            catalog = Path(__file__).with_name('role_dependency_inventory.sql.review-only')
            query(catalog.read_text(), root / 'private-catalog.json')
            # Separate read-only schema snapshot; no role globals or data included.
            subprocess.run([str(dump), '--schema-only', '--format=custom', '--role=postgres',
                            '--lock-wait-timeout=5s', '--no-password', '--file', str(root / 'private-schema.dump')],
                           env=env, stdout=errors, stderr=errors, timeout=300, check=True)
            after = query(INVARIANTS, root / 'private-after.json')
            if before != after:
                raise ValueError('protected identity membership state drifted during collection')
        manifest = {'collection_only': True, 'production_writes': 0,
                    'read_only_identity_membership_comparison': True,
                    'same_database_snapshot_across_files': False,
                    'restoration_verified': False, 'full_role_acl_backup': False,
                    'files': {}}
        for path in root.iterdir():
            if path.is_file():
                manifest['files'][path.name] = hashlib.sha256(path.read_bytes()).hexdigest()
        (root / 'private-manifest.json').write_text(json.dumps(manifest, indent=2))
        print('COLLECTED PRIVATELY: read-only catalog/schema and minimal identity/company/role invariants; before/after unchanged. Production writes: 0.')
        print('Restore/apply/provider-login/full-role-ACL recovery: NOT verified. Private values must stay on this Mac.')
        print('Private evidence: ' + str(root))
        return 2
    except Exception as error:
        print('STOP: private collection incomplete (' + type(error).__name__ + '). No production write or restoration performed.')
        print('Private evidence: ' + str(root))
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
