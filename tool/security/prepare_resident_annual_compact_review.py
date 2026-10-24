#!/usr/bin/env python3
"""Review-only annual installer using a server-derived canonical JSONB digest.

The digest MUST come from the exact observer JSONB on PostgreSQL. Python JSON
serialization is never substituted for PostgreSQL's jsonb::text rendering.
"""
import argparse
import hashlib
import json
import re
from pathlib import Path
import prepare_resident_annual_deployment_review as original


def checked_digest(value):
    if not re.fullmatch(r'[0-9a-f]{64}', value):
        raise ValueError('server canonical SHA256 must be 64 lowercase hex characters')
    return value


def hash_expression(expression):
    return "encode(sha256(convert_to((" + expression + ")::text,'UTF8')),'hex')"


def before_guard(digest):
    checked_digest(digest)
    return original.observer() + "do $annual_compact_before$ begin if " + hash_expression("current_setting('sko.resident_annual_observation')::jsonb") + " is distinct from '" + digest + "' then raise exception 'annual compact checkpoint changed';end if;end $annual_compact_before$;\n"


def postflight(digest, expected):
    checked_digest(digest)
    lit = original.literal
    tables = ','.join(map(lit, original.NEW_TABLES))
    routines = ','.join(map(lit, sorted(original.NEW_ROUTINES)))
    sql = original.observer() + "do $annual_compact_postflight$ declare a jsonb:=current_setting('sko.resident_annual_observation')::jsonb; old jsonb; begin\n"
    sql += "old:=jsonb_build_object('schema',a->'schema','data',(a->'data')-array[" + tables + "],'relations',(a->'relations')-array[" + tables + "],'routines',(a->'routines')-array[" + routines + "],'namespaces',(a->'namespaces')-'resident_tax_annual_private');\n"
    sql += "if " + hash_expression('old') + " is distinct from '" + digest + "' then raise exception 'annual compact installation changed originals';end if;\n"
    for section, names in [('relations', set(original.PROTECTED_TABLES + original.NEW_TABLES)), ('data', set(original.PROTECTED_TABLES + original.NEW_TABLES)), ('routines', original.DEPENDENCIES | original.NEW_ROUTINES), ('namespaces', original.EXISTING_NAMESPACES | {original.NEW_SCHEMA})]:
        sql += "if (select array_agg(x order by x collate \"C\") from jsonb_object_keys(a->" + lit(section) + ")x) is distinct from array[" + ','.join(map(lit, sorted(names))) + "]::text[] then raise exception 'annual compact inventory differs: " + section + "';end if;\n"
    return sql + original.new_object_guard(expected) + 'end $annual_compact_postflight$;\n'


def prepare_install(before, server_digest, root):
    original.validate_before(before)
    checked_digest(server_digest)
    body, expected = original.sources(root)
    return "-- REVIEW ONLY: server-canonical checkpoint-bound annual API installation.\n-- No tax input or confirmation. Digest must be obtained independently READ ONLY.\nbegin;\nset local lock_timeout='3s';\nset local statement_timeout='30s';\nset local search_path='';\nset local TimeZone='UTC';\nset local DateStyle='ISO, YMD';\n" + original.lock_tables(original.PROTECTED_TABLES) + before_guard(server_digest) + body + '\n' + postflight(server_digest, expected) + 'commit;\n'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-root', type=Path, required=True)
    parser.add_argument('--before', type=Path, required=True)
    parser.add_argument('--server-digest', required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    sql = prepare_install(json.loads(args.before.read_text()), args.server_digest, args.source_root)
    original.write_private(args.output, sql)
    print(json.dumps({'schema': 1, 'prepare_only': True, 'deployment_performed': False, 'sha256': hashlib.sha256(sql.encode()).hexdigest(), 'bytes': len(sql.encode()), 'server_digest': args.server_digest}))


if __name__ == '__main__':
    main()
