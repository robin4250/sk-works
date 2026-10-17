#!/usr/bin/env python3
"""Private operator snapshot via one fixed read-only Management API endpoint.

No DB password, login-role creation, unban, restoration or schema archive.
Run only after review. Credentials and result rows must stay on the operator Mac.
"""
import argparse
import base64
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import ssl
import subprocess
import sys
import urllib.error
import urllib.request

PROJECT = 'ztktgquxvcxcjxtluspu'
URL = 'https://api.supabase.com/v1/projects/' + PROJECT + '/database/query/read-only'
COLLECTOR_HASH = '7cdb772f6844db962eafb93f4ac44a9e4629a1edf4b79fc6659aeb3b45b29b81'
TOKEN_PATTERN = re.compile(r'sbp_(oauth_|v0_)?[a-f0-9]{40}')
MAX_BYTES = 16 * 1024 * 1024


class Stop(Exception):
    def __init__(self, category, status=None):
        self.category, self.status = category, status


def private_read(path):
    if not path.is_absolute() or path.is_symlink() or not path.is_file():
        raise Stop('local_file_boundary')
    st = path.stat()
    if st.st_uid != os.getuid() or st.st_mode & 0o077:
        raise Stop('local_file_permissions')
    return path.read_text().strip()


def normalize(value):
    if value.startswith('go-keyring-base64:'):
        try:
            value = base64.b64decode(value.split(':', 1)[1], validate=True).decode('utf-8')
        except Exception:
            raise Stop('credential_encoding') from None
    if not TOKEN_PATTERN.fullmatch(value):
        raise Stop('credential_format')
    return value


def token_from_store(env, run=subprocess.run, home=None):
    home = Path.home() if home is None else home
    state = Path(env.get('SUPABASE_HOME', '').strip() or str(home / '.supabase'))
    if not state.is_absolute() or state.is_symlink():
        raise Stop('profile_boundary')
    profile = env.get('SUPABASE_PROFILE')
    if profile is None and (state / 'profile').exists():
        p = state / 'profile'
        if p.is_symlink() or not p.is_file() or p.stat().st_uid != os.getuid() or p.stat().st_mode & 0o022:
            raise Stop('profile_boundary')
        profile = p.read_text().strip()
    if (profile or 'supabase').lower() != 'supabase':
        raise Stop('nondefault_profile_not_supported')
    if 'SUPABASE_ACCESS_TOKEN' in env:
        return normalize(env['SUPABASE_ACCESS_TOKEN'])
    if env.get('SUPABASE_NO_KEYRING') != '1':
        for account in ('supabase', 'access-token'):
            result = run(['/usr/bin/security', 'find-generic-password', '-s', 'Supabase CLI',
                          '-a', account, '-w'], capture_output=True, text=True, timeout=30,
                         env={'PATH': '/usr/bin:/bin', 'HOME': str(home)})
            if result.returncode == 0:
                return normalize(result.stdout.strip())
            if result.returncode != 44:  # errSecItemNotFound; do not retry access denial.
                raise Stop('credential_store_unavailable')
    path = state / 'access-token'
    if not path.exists():
        raise Stop('credential_not_available')
    return normalize(private_read(path))


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise Stop('redirect_refused', code)


def make_opener():
    return urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect(),
                                      urllib.request.HTTPSHandler(context=ssl.create_default_context()))


def read_query(opener, token, query):
    request = urllib.request.Request(URL, data=json.dumps({'query': query}).encode(), method='POST',
                                     headers={'Authorization': 'Bearer ' + token,
                                              'Content-Type': 'application/json'})
    try:
        with opener.open(request, timeout=45) as response:
            if response.status != 201:
                raise Stop('http_status', response.status)
            raw = response.read(MAX_BYTES + 1)
            if len(raw) > MAX_BYTES:
                raise Stop('response_too_large')
    except urllib.error.HTTPError as error:
        raise Stop('http_status', error.code) from None
    except (urllib.error.URLError, TimeoutError, OSError):
        raise Stop('transport') from None
    try:
        rows = json.loads(raw)
        if not isinstance(rows, list) or len(rows) != 1 or set(rows[0]) != {'entry_payload'}:
            raise Stop('response_shape')
        payload = rows[0]['entry_payload']
        if not isinstance(payload, dict) or payload.get('read_only') is not True:
            raise Stop('read_only_not_proven')
        if set(payload) != {'read_only', 'payload'} or not isinstance(payload['payload'], dict):
            raise Stop('response_shape')
        return payload
    except (ValueError, TypeError, KeyError):
        raise Stop('response_shape') from None


def reviewed_queries(base):
    path = base / 'collect_private_capsule.py'
    if hashlib.sha256(path.read_bytes()).hexdigest() != COLLECTOR_HASH:
        raise Stop('collection_source_mismatch')
    spec = importlib.util.spec_from_file_location('_entry_source', path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    raw = (base / 'role_dependency_inventory.sql.review-only').read_bytes()
    if hashlib.sha256(raw).hexdigest() != module.CATALOG_SHA256:
        raise Stop('catalog_source_mismatch')
    catalog = raw.decode()
    # Read-only API requires physical entities to be schema-qualified.
    for name in ('pg_class', 'pg_namespace', 'pg_proc', 'pg_depend', 'pg_policy', 'pg_type',
                 'pg_auth_members', 'pg_roles', 'pg_identify_object', 'pg_get_function_identity_arguments',
                 'aclexplode'):
        catalog = re.sub(r'\b' + name + r'\b', 'pg_catalog.' + name, catalog)
    def envelope(sql):
        return ("SELECT pg_catalog.jsonb_build_object('read_only', "
                "pg_catalog.current_setting('transaction_read_only')='on', 'payload', (" +
                sql.strip().rstrip(';') + ')) AS entry_payload;')
    return module, envelope(module.INVARIANTS), envelope(catalog)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--collect', action='store_true', help='Explicitly permit read-only requests')
    parser.add_argument('--output-parent', type=Path, default=Path.home() / 'SKO-source-backups')
    args = parser.parse_args()
    if not args.collect:
        print('NOT RUN: use only after review; no credential access or requests performed.')
        return 2
    os.umask(0o077)
    root = None
    try:
        module, invariants, catalog = reviewed_queries(Path(__file__).parent)
        root = module.new_capsule_directory(args.output_parent)
        token = token_from_store(os.environ)
        opener = make_opener()
        before = read_query(opener, token, invariants)
        (root / 'private-before.json').write_text(json.dumps(before))
        current = read_query(opener, token, catalog)
        (root / 'private-catalog.json').write_text(json.dumps(current))
        after = read_query(opener, token, invariants)
        (root / 'private-after.json').write_text(json.dumps(after))
        if before != after:
            raise Stop('identity_membership_drift')
        manifest = {'read_only_api': True, 'production_writes': 0, 'utility_role_created': False,
                    'network_bans_changed': False, 'restoration_verified': False,
                    'schema_archive_created': False, 'full_database_auth_acl_recovery': False,
                    'same_snapshot_across_requests': False,
                    'files': {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                              for p in root.iterdir() if p.is_file()}}
        (root / 'private-manifest.json').write_text(json.dumps(manifest, indent=2))
        print('COLLECTED PRIVATELY: catalog and minimal identity/company/role invariants; read-only proven; before/after unchanged.')
        print('Schema archive/full restoration/provider login: NOT verified. Production writes: 0.')
        print('Private evidence: ' + str(root))
        return 2
    except Stop as error:
        print('STOP: ' + json.dumps({'category': error.category, 'status': error.status}))
    except Exception as error:
        print('STOP: ' + json.dumps({'category': type(error).__name__}))
    if root is not None:
        print('Private evidence: ' + str(root))
    return 1


if __name__ == '__main__':
    raise SystemExit(main())
