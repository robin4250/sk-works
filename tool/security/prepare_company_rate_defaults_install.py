#!/usr/bin/env python3
"""Offline four-function installation, bound to a private two-table checkpoint.

Uses the same literal/exclusive-write and repeated-observer pattern as the
reviewed PNG/common installers. No database connection or data repair exists.
"""
import argparse
import hashlib
import json
import os
import re
from pathlib import Path


def literal(value):
    return "'" + value.replace("'", "''") + "'"


def write_private(path, text):
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, 'w') as stream:
        stream.write(text)


UNIT = 'docs/candidates/company_rate_defaults_20261024.sql.review-only'
MANIFEST = 'docs/review/company-rate-defaults-observed-manifest-20261024.json'
OBSERVER = 'tool/security/payroll_settings_entry_observation/checkpoint.read-only.sql'
TABLES = {'public.companies', 'public.company_rate_settings'}
NEW = {
    'company_common_allowance_private.read_rate_defaults(uuid)': ('plpgsql', True, 's'),
    'company_common_allowance_private.save_rate_defaults(uuid, jsonb, jsonb)': ('plpgsql', True, 'v'),
    'public.read_company_rate_defaults(uuid)': ('sql', False, 's'),
    'public.save_company_rate_defaults(uuid, jsonb, jsonb)': ('sql', False, 'v'),
}


def block(prefix, body):
    suffix = hashlib.sha256(body.encode()).hexdigest()[:20]
    tag = '$' + prefix + '_' + suffix + '$'
    if tag in body:
        raise ValueError('SQL delimiter collision')
    return 'do ' + tag + body + tag + ';\n'


def sources(root):
    manifest = json.loads((root / MANIFEST).read_text())
    raw = (root / UNIT).read_bytes()
    if hashlib.sha256(raw).hexdigest() != manifest['unit_sha256']:
        raise ValueError('reviewed four-function unit changed')
    text = raw.decode()
    prefix = "-- REVIEW ONLY. Reuse existing authorization and storage; never update allowances.\nbegin;\nset local lock_timeout='5s';\n"
    if not text.startswith(prefix) or not text.rstrip().endswith('commit;'):
        raise ValueError('reviewed transaction envelope changed')
    if set(manifest['expected_new_functions_source_md5']) != {s.split('(')[0] for s in NEW}:
        raise ValueError('four-function source inventory changed')
    body = text[len(prefix):].rstrip()[:-len('commit;')]
    return manifest, body


def observer(root):
    text = (root / OBSERVER).read_text()
    start = text.index('with relation_names(name) as (values')
    suffix = ') as observation;\n\nROLLBACK;\n'
    if not text.endswith(suffix):
        raise ValueError('reviewed checkpoint observer changed')
    select = text[start:-len(suffix)] + ') into observed;\n'
    body = "\ndeclare observed jsonb; begin\n" + normalize() + select
    body += "perform set_config('sko.rate_defaults_observation',observed::text,true);\nend "
    return block('rate_defaults_observe', body)


def normalize():
    return "perform set_config('search_path','',true);\nperform set_config('TimeZone','UTC',true);\nperform set_config('DateStyle','ISO, YMD',true);\n"


def validate_before(before, manifest):
    if before.get('schema') != 1 or before.get('observation_kind') != 'company_rate_defaults_checkpoint':
        raise ValueError('normalized rate-defaults checkpoint required')
    if before.get('application_rows_read') is not True or before.get('application_values_returned') is not False:
        raise ValueError('count/hash checkpoint contract changed')
    if set(before['data']) != TABLES or set(before['relations']) != TABLES:
        raise ValueError('exact two-writer checkpoint required')
    if set(before['namespaces']) != {'public', 'private', 'company_common_allowance_private', 'company_allowance_identity_private'}:
        raise ValueError('checkpoint namespace inventory changed')
    if any(value.get('exists') is not True for value in before['namespaces'].values()):
        raise ValueError('existing checkpoint namespace missing')
    for table in TABLES:
        row = before['data'][table]
        meta = before['relations'][table]
        if type(row.get('count')) is not int or row['count'] < 0 or not re.fullmatch('[0-9a-f]{64}', row.get('sha256', '')):
            raise ValueError('invalid protected row count/hash')
        if not meta.get('exists') or meta['owner'] != 'postgres' or meta['rls'] is not True:
            raise ValueError('protected writer owner/RLS changed')
    expected_missing = sorted(s.split('(')[0] for s in NEW)
    if before['missing_routine_names'] != expected_missing:
        raise ValueError('new functions partially present or dependency missing')
    originals = manifest['protected_existing_routines']
    if set(before['routines']) != set(originals):
        raise ValueError('existing function inventory changed')
    for sig, wanted in originals.items():
        got = before['routines'][sig]
        if got['source_md5'] != wanted['source_md5'] or got['owner'] != wanted['owner']:
            raise ValueError('existing source/owner changed: ' + sig)
        attrs = got['attributes']
        if attrs['prosecdef'] != wanted['security_definer'] or attrs['proconfig'] != wanted['search_path'] or attrs['provolatile'] != wanted['volatility']:
            raise ValueError('existing function attributes changed: ' + sig)


def checkpoint_guard(root, expected):
    value = literal(json.dumps(expected, ensure_ascii=False, separators=(',', ':')))
    return observer(root) + block('rate_defaults_checkpoint', "\nbegin\nif current_setting('sko.rate_defaults_observation')::jsonb is distinct from " + value + "::jsonb then raise exception 'rate defaults catalog/data checkpoint changed';end if;\nend ")


def postflight(root, before, manifest):
    b = literal(json.dumps(before, ensure_ascii=False, separators=(',', ':')))
    signatures = ','.join(map(literal, sorted(NEW)))
    body = "\ndeclare a jsonb:=current_setting('sko.rate_defaults_observation')::jsonb; b jsonb:=" + b + "::jsonb; p record; begin\n"
    body += "if (a-'routines'-'missing_routine_names') is distinct from (b-'routines'-'missing_routine_names') then raise exception 'rate defaults changed original catalog/data';end if;\n"
    body += "if (a->'routines')-array[" + signatures + "] is distinct from b->'routines' or a->'missing_routine_names' is distinct from '[]'::jsonb then raise exception 'rate defaults original function inventory changed';end if;\n"
    body += "if (select count(*) from jsonb_object_keys(a->'routines')) <> (select count(*) from jsonb_object_keys(b->'routines'))+4 then raise exception 'rate defaults new function inventory changed';end if;\n"
    for sig, (lang, secdef, volatility) in NEW.items():
        md5 = manifest['expected_new_functions_source_md5'][sig.split('(')[0]]
        body += "select q.*,l.lanname into p from pg_proc q join pg_language l on l.oid=q.prolang where q.oid=to_regprocedure(" + literal(sig) + ");\n"
        body += "if not found or pg_get_userbyid(p.proowner)<>'postgres' or md5(p.prosrc)<>" + literal(md5) + " or p.proconfig is distinct from array['search_path=\"\"'] or p.prosecdef is distinct from " + ('true' if secdef else 'false') + " or p.provolatile<>" + literal(volatility) + " or p.lanname<>" + literal(lang) + " or p.proretset or p.prorettype<>'jsonb'::regtype then raise exception 'rate defaults new function source/attributes differ';end if;\n"
        body += "if not has_function_privilege('authenticated',p.oid,'execute') or exists(select 1 from aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) x where x.grantee not in(p.proowner,(select oid from pg_roles where rolname='authenticated')) or x.grantor<>p.proowner or x.privilege_type<>'EXECUTE' or x.is_grantable) then raise exception 'rate defaults new function ACL differs';end if;\n"
    body += 'end '
    return observer(root) + block('rate_defaults_postflight', body)


def prepare_install(root, before):
    manifest, unit = sources(root)
    validate_before(before, manifest)
    sql = "-- PRIVATE REVIEW ONLY. Four function objects; no application value migration.\nbegin;\nset local lock_timeout='3s';\nset local statement_timeout='30s';\nset local search_path='';\nset local TimeZone='UTC';\nset local DateStyle='ISO, YMD';\n"
    sql += block('rate_defaults_owner', "\nbegin if current_user<>'postgres' then raise exception 'postgres installer required';end if;end ")
    sql += 'lock table public.companies,public.company_rate_settings in access exclusive mode;\n'
    sql += checkpoint_guard(root, before) + unit + '\n' + postflight(root, before, manifest)
    return sql + 'commit;\n'


def prepare_code_removal(root, before, after):
    manifest, _ = sources(root)
    validate_before(before, manifest)
    if {k: v for k, v in after.items() if k not in ('routines', 'missing_routine_names')} != {
            k: v for k, v in before.items() if k not in ('routines', 'missing_routine_names')}:
        raise ValueError('original writer checkpoint changed; no code-removal artifact')
    if after['missing_routine_names'] != [] or set(after['routines']) != set(before['routines']) | set(NEW):
        raise ValueError('installed function inventory changed')
    if {k: v for k, v in after['routines'].items() if k not in NEW} != before['routines']:
        raise ValueError('original functions changed')
    for sig, (_, secdef, volatility) in NEW.items():
        got = after['routines'][sig]
        attrs = got['attributes']
        if got['source_md5'] != manifest['expected_new_functions_source_md5'][sig.split('(')[0]] or got['owner'] != 'postgres':
            raise ValueError('installed function source/owner changed')
        if attrs['proconfig'] != ['search_path=""'] or attrs['prosecdef'] != secdef or attrs['provolatile'] != volatility:
            raise ValueError('installed function attributes changed')
        if set(attrs['proacl']) != {'postgres=X/postgres', 'authenticated=X/postgres'}:
            raise ValueError('installed function ACL changed')
    sql = "-- PRIVATE REVIEW ONLY. Code removal after an unchanged-data checkpoint.\n-- This is NOT a financial rollback or proof that the API has never been used.\nbegin;\nset local lock_timeout='3s';\nset local statement_timeout='30s';\nset local search_path='';\nset local TimeZone='UTC';\nset local DateStyle='ISO, YMD';\n"
    sql += block('rate_defaults_owner', "\nbegin if current_user<>'postgres' then raise exception 'postgres installer required';end if;end ")
    sql += 'lock table public.companies,public.company_rate_settings in access exclusive mode;\n'
    sql += checkpoint_guard(root, after) + postflight(root, before, manifest)
    sql += 'drop function public.read_company_rate_defaults(uuid),public.save_company_rate_defaults(uuid,jsonb,jsonb);\n'
    sql += 'drop function company_common_allowance_private.save_rate_defaults(uuid,jsonb,jsonb),company_common_allowance_private.read_rate_defaults(uuid);\n'
    return sql + checkpoint_guard(root, before) + 'commit;\n'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-root', required=True, type=Path)
    parser.add_argument('--before', required=True, type=Path)
    parser.add_argument('--after', type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('mode', choices=['install', 'code-removal'])
    args = parser.parse_args()
    before = json.loads(args.before.read_text())
    if args.mode == 'install':
        text = prepare_install(args.source_root, before)
    else:
        if args.after is None:
            parser.error('--after required for code-removal')
        text = prepare_code_removal(args.source_root, before, json.loads(args.after.read_text()))
    write_private(args.output, text)


if __name__ == '__main__':
    main()
