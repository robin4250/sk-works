#!/usr/bin/env python3
"""Offline compact equivalent of the reviewed full-checkpoint installer.

The supplied fingerprint MUST come from PostgreSQL hashing its complete JSONB
observation. Python never canonicalizes or hashes the observation itself.
"""
import argparse
import json
import re
from pathlib import Path

import prepare_company_rate_defaults_install as original


def digest(expression):
    return "encode(sha256(convert_to((" + expression + ")::text,'UTF8')),'hex')"


def fingerprint_query(root):
    return ("begin transaction read only;\nset local statement_timeout='15s';\n"
            "set local lock_timeout='3s';\n" + original.observer(root) +
            "select jsonb_build_object('schema',1,'observation_kind',"
            "'company_rate_defaults_checkpoint_sha256','sha256'," +
            digest("current_setting('sko.rate_defaults_observation')::jsonb") +
            ",'postgres_encoding',current_setting('server_encoding'),"
            "'observation',current_setting('sko.rate_defaults_observation')::jsonb);\nrollback;\n")


def prepare_install(root, before, server_sha256):
    if not isinstance(server_sha256, str) or not re.fullmatch('[0-9a-f]{64}', server_sha256):
        raise ValueError('PostgreSQL-produced complete observation SHA256 required')
    manifest, unit = original.sources(root)
    original.validate_before(before, manifest)
    expected = original.literal(server_sha256)
    sql = ("-- PRIVATE REVIEW ONLY. Compact full-checkpoint parity candidate.\n"
           "-- Fingerprint must be independently obtained from PostgreSQL, never Python JSON serialization.\n"
           "begin;\nset local lock_timeout='3s';\nset local statement_timeout='30s';\n"
           "set local search_path='';\nset local TimeZone='UTC';\nset local DateStyle='ISO, YMD';\n")
    sql += original.block('rate_defaults_owner', "\nbegin if current_user<>'postgres' then raise exception 'postgres installer required';end if;end ")
    sql += 'lock table public.companies,public.company_rate_settings in access exclusive mode;\n'
    sql += original.observer(root)
    sql += original.block('rate_defaults_compact_before', "\nbegin\nif " +
        digest("current_setting('sko.rate_defaults_observation')::jsonb") +
        ' is distinct from ' + expected + " then raise exception 'rate defaults full checkpoint changed';end if;\nend ")
    sql += unit + '\n' + original.observer(root)
    signatures = ','.join(map(original.literal, sorted(original.NEW)))
    missing = original.literal(json.dumps(sorted(s.split('(')[0] for s in original.NEW), separators=(',', ':')))
    body = "\ndeclare a jsonb:=current_setting('sko.rate_defaults_observation')::jsonb; restored jsonb;p record;begin\n"
    body += "if a->'missing_routine_names' is distinct from '[]'::jsonb then raise exception 'rate defaults missing installed routines';end if;\n"
    body += "restored:=jsonb_set(jsonb_set(a,'{routines}',(a->'routines')-array[" + signatures + "]),'{missing_routine_names}'," + missing + "::jsonb);\n"
    body += 'if ' + digest('restored') + ' is distinct from ' + expected + " then raise exception 'rate defaults changed full original catalog/data';end if;\n"
    for sig, (lang, secdef, volatility) in original.NEW.items():
        md5 = manifest['expected_new_functions_source_md5'][sig.split('(')[0]]
        body += "select q.*,l.lanname into p from pg_proc q join pg_language l on l.oid=q.prolang where q.oid=to_regprocedure(" + original.literal(sig) + ");\n"
        body += "if not found or pg_get_userbyid(p.proowner)<>'postgres' or md5(p.prosrc)<>" + original.literal(md5) + " or p.proconfig is distinct from array['search_path=\"\"'] or p.prosecdef is distinct from " + ('true' if secdef else 'false') + " or p.provolatile<>" + original.literal(volatility) + " or p.lanname<>" + original.literal(lang) + " or p.proretset or p.prorettype<>'jsonb'::regtype then raise exception 'rate defaults new function source/attributes differ';end if;\n"
        body += "if not has_function_privilege('authenticated',p.oid,'execute') or exists(select 1 from aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) x where x.grantee not in(p.proowner,(select oid from pg_roles where rolname='authenticated')) or x.grantor<>p.proowner or x.privilege_type<>'EXECUTE' or x.is_grantable) then raise exception 'rate defaults new function ACL differs';end if;\n"
    return sql + original.block('rate_defaults_compact_after', body + 'end ') + 'commit;\n'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-root', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--before', type=Path)
    parser.add_argument('--postgres-sha256')
    parser.add_argument('mode', choices=['fingerprint-query', 'install'])
    args = parser.parse_args()
    if args.mode == 'fingerprint-query':
        text = fingerprint_query(args.source_root)
    else:
        if args.before is None or args.postgres_sha256 is None:
            parser.error('install requires --before and --postgres-sha256')
        text = prepare_install(args.source_root, json.loads(args.before.read_text()), args.postgres_sha256)
    original.write_private(args.output, text)


if __name__ == '__main__':
    main()
