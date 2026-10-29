"""OFF offline catalog preflight; never connects/applies/reads application rows.

Reuse existing management CAPTURE, redact definitions/prosrc before output.
Unsigned snapshots prove only mechanical consistency, never capture authenticity,
source-owner scope, signatures, custody or permission to install/activate.
"""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parent
ISSUER = ROOT.parent / 'free-worker-candidate/issuer'
spec = importlib.util.spec_from_file_location('existing_management_guard', ISSUER / 'prepare-management-issuer-guards.py')
existing = importlib.util.module_from_spec(spec)
spec.loader.exec_module(existing)
EXTRA = ['security_management_issuer_private.binding(uuid,uuid,uuid,text,boolean)',
         'security_management_issuer_private.digest(text)',
         'archive_readback_private.reject_rewrite()']
# The old CAPTURE remains the one core/dependency/table/default catalogue source.
# Its function definitions are reduced inside SQL: they never leave the server.
META = """jsonb_build_object('signature',replace(f->>'signature',', ',','),'owner',(f#>>'{metadata,proowner}')::bigint,
 'source_md5',md5(f#>>'{metadata,prosrc}'),'definer',(f#>>'{metadata,prosecdef}')::boolean,
 'kind',f#>>'{metadata,prokind}','returns_set',(f#>>'{metadata,proretset}')::boolean,
 'config_count',jsonb_array_length(coalesce(nullif(f#>'{metadata,proconfig}','null'::jsonb),'[]')),
 'empty_search_path',coalesce(f#>'{metadata,proconfig}','[]') @> '["search_path=\\"\\""]'::jsonb,
 'config_md5',md5(coalesce(f#>'{metadata,proconfig}','null'::jsonb)::text),
 'acl',(select coalesce(jsonb_agg(jsonb_build_object('grantee',a.grantee::bigint,'grantor',a.grantor::bigint,
 'privilege',a.privilege_type,'grantable',a.is_grantable)order by a.grantee,a.privilege_type),'[]')
 from pg_catalog.pg_proc p cross join lateral pg_catalog.aclexplode(coalesce(p.proacl,pg_catalog.acldefault('f',p.proowner)))a
 where p.oid=pg_catalog.to_regprocedure(f->>'signature')))"""
CAPTURE = f"""with baseline as ({existing.CAPTURE.rstrip().rstrip(';')}),
 all_functions as (select f from baseline b cross join lateral jsonb_array_elements(b.snapshot->'functions')f
 union all select jsonb_build_object('signature',s,'metadata',to_jsonb(p)) from unnest({existing.arr(EXTRA)})s
 join pg_catalog.pg_proc p on p.oid=pg_catalog.to_regprocedure(s)),
 registry as ({existing.table_query(existing.arr(['archive_readback_private.authority_records']))})
 select jsonb_build_object('v',1,'phase','archive_runtime_preapply',
 'read_only',current_setting('transaction_read_only')='on',
 'operator',(select snapshot->>'operator'from baseline),'session_operator',(select snapshot->>'session_operator'from baseline),
 'owner_oid',current_user::regrole::oid::bigint,
 'functions',(select coalesce(jsonb_agg({META}order by f->>'signature'),'[]')from all_functions),
 'schemas',(select coalesce(jsonb_agg(jsonb_build_object('name',n.nspname,'owner',n.nspowner::bigint,
 'acl',(select coalesce(jsonb_agg(jsonb_build_object('grantee',a.grantee::bigint,'privilege',a.privilege_type,'grantable',a.is_grantable)),'[]')from pg_catalog.aclexplode(coalesce(n.nspacl,pg_catalog.acldefault('n',n.nspowner)))a))order by n.nspname),'[]')
 from pg_catalog.pg_namespace n where n.nspname in('private','security_management_issuer_private','archive_readback_private')),
 'registry',(select jsonb_build_object('relation',r->'relation','columns',(select jsonb_agg(jsonb_build_object('name',a->>'attname','type',(a->>'atttypid')::bigint,'not_null',(a->>'attnotnull')::boolean)order by (a->>'attnum')::int)
 from jsonb_array_elements(coalesce(nullif(r->'columns','null'::jsonb),'[]'))a where not (a->>'attisdropped')::boolean))from registry x cross join lateral jsonb_array_elements(x.coalesce)r),
 'runtime_role_absent',not exists(select 1 from pg_catalog.pg_roles where rolname='archive_readback_runtime'),
 'runtime_helper_absent',not exists(select 1 from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid=p.pronamespace where n.nspname='archive_readback_private'and p.proname='authorize_observation'),
 'unexpected_function_defaults',(select exists(select 1 from pg_catalog.pg_default_acl d cross join lateral pg_catalog.aclexplode(d.defaclacl)a
 where d.defaclrole=current_user::regrole and d.defaclobjtype='f'and(d.defaclnamespace=0 or d.defaclnamespace=pg_catalog.to_regnamespace('archive_readback_private'))
 and a.grantee<>d.defaclrole and a.grantee<>0 and a.grantee not in(select oid from pg_catalog.pg_roles where rolname in('anon','authenticated','service_role'))))) snapshot;
"""

def function_source(text, name):
    start = text.lower().index('create function ' + name.lower() + '(')
    match = re.search(r'\bas\s+(\$[a-z_]*\$)(.*?)\1', text[start:], re.I | re.S)
    if not match:
        raise ValueError('reviewed source body missing')
    return hashlib.md5(match[2].encode()).hexdigest()


def inspect(snapshot):
    reasons = []
    if not isinstance(snapshot, dict) or snapshot.get('v') != 1 or snapshot.get('phase') != 'archive_runtime_preapply':
        raise ValueError('archive_readiness_snapshot_invalid')
    if snapshot.get('read_only') is not True:
        reasons.append('capture_not_read_only')
    if snapshot.get('operator') != 'postgres' or snapshot.get('session_operator') != 'postgres':
        reasons.append('protected_operator_mismatch')
    owner = snapshot.get('owner_oid')
    if not isinstance(owner, int) or isinstance(owner, bool):
        reasons.append('protected_owner_missing')
    functions = {f['signature']: f for f in snapshot.get('functions', [])}
    if len(functions) != len(snapshot.get('functions', [])):
        raise ValueError('duplicate function signature')
    for signature in existing.CORE + EXTRA:
        if signature not in functions:
            reasons.append('required_function_missing:' + signature)
    expected = {}
    for row in json.loads((ISSUER / 'current-core-fixtures.json').read_text()):
        signature = row['signature'] if '.' in row['signature'] else 'public.' + row['signature']
        paths = re.search(r'SET search_path TO ([^\n]+)', row['definition'])[1]
        values = re.findall(r"'([^']*)'", paths)
        setting = 'search_path=' + (', '.join(values) if values != [''] else '""')
        config_hash = hashlib.md5(json.dumps([setting]).encode()).hexdigest()
        expected[signature] = (row['body_md5'], 'SECURITY DEFINER' in row['definition'], config_hash)
    management = (ISSUER / 'management-issuer.sql.review-only').read_text()
    empty_config = hashlib.md5(json.dumps(['search_path=""']).encode()).hexdigest()
    expected[EXTRA[0]] = (function_source(management, EXTRA[0].split('(')[0]), True, empty_config)
    expected[EXTRA[1]] = (function_source(management, EXTRA[1].split('(')[0]), False, empty_config)
    expected[EXTRA[2]] = (function_source((ROOT / 'src/archive-readback-registry.sql.review-only').read_text(), EXTRA[2].split('(')[0]), False, empty_config)
    for signature, (digest, definer, config_hash) in expected.items():
        f = functions.get(signature)
        if not f:
            continue
        if f.get('source_md5') != digest or f.get('definer') is not definer or f.get('kind') != 'f' or f.get('returns_set') is not False:
            reasons.append('required_function_source_or_attributes_drift:' + signature)
        if f.get('owner') != owner or f.get('config_md5') != config_hash or f.get('config_count') != 1:
            reasons.append('required_function_owner_or_config_drift:' + signature)
        # Existing core ACLs are NOT redefined here. Existing management guarded
        # compiler binds their reviewed complete catalogue before its own apply.
        if signature in EXTRA and any(a.get('grantee') != owner or a.get('privilege') != 'EXECUTE' or a.get('grantable') is not False for a in f.get('acl', [])):
            reasons.append('private_function_acl_drift:' + signature)
    schemas = {s['name']: s for s in snapshot.get('schemas', [])}
    for name in ['private', 'security_management_issuer_private', 'archive_readback_private']:
        s = schemas.get(name)
        if not s:
            reasons.append('required_schema_missing:' + name)
        elif s.get('owner') != owner or any(a.get('grantee') != owner for a in s.get('acl', [])):
            reasons.append('protected_schema_owner_or_acl_drift:' + name)
    registry = snapshot.get('registry') or {}
    relation = registry.get('relation')
    if not relation:
        reasons.append('registry_relation_missing')
    elif str(relation.get('owner')) != str(owner) or relation.get('kind') != 'r' or relation.get('persistence') != 'p' or relation.get('rls') is not True:
        reasons.append('registry_owner_or_protection_drift')
    # ACL text is retained only for offline root comparison, never credential rows.
    if relation and relation.get('acl') not in (None, []):
        if any(not re.fullmatch(r'postgres=arwdDxtm?/postgres', a) for a in relation['acl']):
            reasons.append('registry_acl_requires_review')
    names = ['object_id','authority_id','company_id','owner_id','deployment_id','event_id','revision','snapshot_sha256','payload_sha256','byte_length']
    types = [25,2950,2950,2950,25,2950,20,25,25,23]
    if registry.get('columns') != [dict(name=n, type=t, not_null=True) for n,t in zip(names,types)]:
        reasons.append('registry_column_contract_drift')
    if snapshot.get('runtime_role_absent') is not True or snapshot.get('runtime_helper_absent') is not True:
        reasons.append('runtime_installation_collision')
    if snapshot.get('unexpected_function_defaults') is not False:
        reasons.append('unexpected_function_default_grants')
    return dict(status='blocked_unattested', mechanical_catalogue_match=not reasons,
                blockers=sorted(reasons), activation_allowed=False, production_applied=False,
                capture_authenticity_verified=False, source_owner_scope_verified=False,
                signature_authority_verified=False, independent_custody_verified=False,
                unverified_prerequisites=['capture_authenticity','source_owner_scope','signature_authority','independent_custody','production_role_deployment'],
                runtime_source_sha256=hashlib.sha256((ROOT / 'src/archive-readback-runtime-role.sql.review-only').read_bytes()).hexdigest())


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--capture', action='store_true')
    parser.add_argument('--snapshot')
    args = parser.parse_args()
    try:
        if args.capture and not args.snapshot:
            print(CAPTURE)
        elif args.snapshot and not args.capture:
            value = json.load(sys.stdin) if args.snapshot == '-' else json.loads(Path(args.snapshot).read_text())
            print(json.dumps(inspect(value.get('snapshot', value)), sort_keys=True))
            # Never provide a successful shell gate for apply/activation, even
            # when only the mechanical catalogue comparison matches.
            sys.exit(2)
        else:
            parser.error('choose --capture or --snapshot FILE|-')
    except (ValueError, KeyError, TypeError, AttributeError):
        print(json.dumps(dict(status='blocked_invalid_snapshot', activation_allowed=False)), file=sys.stdout)
        sys.exit(1)
