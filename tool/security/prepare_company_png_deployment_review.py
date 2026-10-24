#!/usr/bin/env python3
"""Offline, checkpoint-bound PNG installer/unused-restore preparation."""
import argparse
import hashlib
import json
import os
import re
from pathlib import Path

# Reused verbatim from prepare_common_canonical_deployment_review.py. That
# payroll-specific candidate is not on main, so do not add its installer here.
def literal(value):
    return "'" + value.replace("'", "''") + "'"


def write_private(path,text):
    fd=os.open(path,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
    with os.fdopen(fd,'w') as f: f.write(text)


UNIT = 'docs/candidates/company_seal_uploaded_png_20261020.sql.review-only'
UNIT_HASH = 'afb4d3fb4ffff27ac763def102df6c267e7864c0a583955a8efa3b04dadcced1'
ORIGINAL = 'private.document_company_seal_snapshot(jsonb, uuid, boolean)'
ORIGINAL_MD5 = '5e29407c55cfe7fa33eb7933a38d2af7'
PROTECTED_TABLES = ['public.companies', 'public.company_members', 'public.invoices',
                    'public.payment_certificates', 'public.payroll_statements']
NEW_TABLES = ['private.company_seal_png_versions', 'private.company_seal_png_selection']
NEW_ROUTINES = {
    'private.company_seal_png_version_immutable()',
    'private.company_uploaded_seal_settings(uuid)', 'public.company_uploaded_seal_settings(uuid)',
    'private.save_company_uploaded_seal(uuid, text, integer, text, text, boolean)',
    'public.save_company_uploaded_seal(uuid, text, integer, text, text, boolean)',
    'private.uploaded_company_seal_snapshot(uuid)',
    'private.company_current_uploaded_seal(uuid)', 'public.company_current_uploaded_seal(uuid)',
}
DEPENDENCIES = {ORIGINAL, 'private.account_access_allowed()', 'private.aoyagi_reisho_name_supported(text)'}


def observer():
    relations = ','.join(map(literal, PROTECTED_TABLES + NEW_TABLES))
    names = sorted({s.split('(')[0] for s in DEPENDENCIES | NEW_ROUTINES})
    functions = ','.join(map(literal, names))
    return f"""do $png_observe$
declare r record; data jsonb:='{{}}'; relations jsonb:='{{}}'; routines jsonb; namespaces jsonb; meta jsonb; row_count bigint; rows_hash text;
begin
 if current_user <> 'postgres' then raise exception 'postgres owner observer required';end if;
 if exists(select 1 from unnest(array[{','.join(map(literal, PROTECTED_TABLES))}]::text[]) w(name) where to_regclass(w.name) is null) then raise exception 'protected PNG baseline relation missing';end if;
 for r in select n.nspname,c.relname,c.oid from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname||'.'||c.relname in ({relations}) and c.relkind in('r','p') order by n.nspname,c.relname loop
  execute format('select count(*),encode(sha256(convert_to(coalesce(jsonb_agg(v order by v::text)::text,''[]''),''UTF8'')),''hex'') from (select to_jsonb(t) v from %I.%I t) q',r.nspname,r.relname) into row_count,rows_hash;
  data:=data||jsonb_build_object(r.nspname||'.'||r.relname,jsonb_build_object('count',row_count,'sha256',rows_hash));
  select jsonb_build_object('owner',pg_get_userbyid(c.relowner),'acl',c.relacl,'rls',c.relrowsecurity,'force_rls',c.relforcerowsecurity,'kind',c.relkind,'options',c.reloptions,
   'columns',(select jsonb_agg(jsonb_build_object('name',a.attname,'type',format_type(a.atttypid,a.atttypmod),'not_null',a.attnotnull,'identity',a.attidentity,'generated',a.attgenerated,'default',pg_get_expr(d.adbin,d.adrelid)) order by a.attnum) from pg_attribute a left join pg_attrdef d on d.adrelid=a.attrelid and d.adnum=a.attnum where a.attrelid=c.oid and a.attnum>0 and not a.attisdropped),
   'constraints',(select coalesce(jsonb_agg(jsonb_build_object('name',x.conname,'definition',pg_get_constraintdef(x.oid)) order by x.conname),'[]') from pg_constraint x where x.conrelid=c.oid),
   'indexes',(select coalesce(jsonb_agg(jsonb_build_object('name',i.relname,'definition',pg_get_indexdef(i.oid)) order by i.relname),'[]') from pg_index x join pg_class i on i.oid=x.indexrelid where x.indrelid=c.oid),
   'triggers',(select coalesce(jsonb_agg(jsonb_build_object('name',t.tgname,'enabled',t.tgenabled,'definition',pg_get_triggerdef(t.oid)) order by t.tgname),'[]') from pg_trigger t where t.tgrelid=c.oid and not t.tgisinternal),
   'policies',(select coalesce(jsonb_agg(to_jsonb(p)-'oid' order by p.polname),'[]') from pg_policy p where p.polrelid=c.oid)) into meta from pg_class c where c.oid=r.oid;
  relations:=relations||jsonb_build_object(r.nspname||'.'||r.relname,meta);
 end loop;
 select coalesce(jsonb_object_agg(n.nspname||'.'||p.proname||'('||oidvectortypes(p.proargtypes)||')',jsonb_build_object('source_md5',md5(p.prosrc),'definition',pg_get_functiondef(p.oid),'owner',pg_get_userbyid(p.proowner),'attributes',to_jsonb(p)-'prosrc')),'{{}}') into routines from pg_proc p join pg_namespace n on n.oid=p.pronamespace where p.prokind='f' and n.nspname||'.'||p.proname in ({functions});
 select coalesce(jsonb_object_agg(n.nspname,jsonb_build_object('owner',pg_get_userbyid(n.nspowner),'acl',n.nspacl)),'{{}}') into namespaces from pg_namespace n where n.nspname in('private','public');
 perform set_config('sko.png_observation',jsonb_build_object('schema',1,'data',data,'relations',relations,'routines',routines,'namespaces',namespaces)::text,true);
end $png_observe$;
"""


def sources(source_root):
    raw = (source_root / UNIT).read_bytes()
    if hashlib.sha256(raw).hexdigest() != UNIT_HASH:
        raise ValueError('reviewed PNG unit hash changed')
    text = raw.decode()
    # Strip only the single reviewed outer transaction, never arbitrary SQL.
    prefix = '-- REVIEW ONLY. OFF by default. Requires updated clients before activation.\n-- No historical document UPDATE, Storage object mutation or company-style rewrite.\nBEGIN;\n'
    if not text.startswith(prefix) or not text.rstrip().endswith('COMMIT;'):
        raise ValueError('reviewed transaction envelope changed')
    body = text[len(prefix):].rstrip()[:-len('COMMIT;')]
    expected = {}
    for m in re.finditer(r'CREATE FUNCTION ([a-z_]+\.[a-z_]+)\(.*?\bAS \$\$(.*?)\$\$;', text, re.S):
        expected[m[1]] = hashlib.md5(m[2].encode()).hexdigest()
    if len(expected) != 8:
        raise ValueError('PNG function source inventory mismatch')
    return body, expected


def validate_before(before):
    if before.get('schema') != 1 or set(before['relations']) != set(PROTECTED_TABLES) or set(before['data']) != set(PROTECTED_TABLES):
        raise ValueError('complete protected PNG checkpoint required')
    if set(before['routines']) != DEPENDENCIES:
        raise ValueError('PNG baseline function inventory mismatch')
    p = before['routines'][ORIGINAL]
    if p['source_md5'] != ORIGINAL_MD5 or p['owner'] != 'postgres' or p['attributes']['proconfig'] != ['search_path=""'] or not p['attributes']['prosecdef']:
        raise ValueError('PNG snapshot baseline source/attributes mismatch')
    if set(before['namespaces']) != {'private', 'public'}:
        raise ValueError('PNG baseline namespace mismatch')


def checkpoint_guard(value):
    return observer() + 'do $png_guard$ begin if current_setting(\'sko.png_observation\')::jsonb is distinct from ' + literal(json.dumps(value, separators=(',', ':'))) + "::jsonb then raise exception 'PNG catalog/data checkpoint changed';end if;end $png_guard$;\n"


def lock_tables(tables):
    if any(not re.fullmatch(r'[a-z_]+\.[a-z_]+', t) for t in tables):
        raise ValueError('unexpected PNG relation identifier')
    return 'lock table ' + ','.join('.'.join('"'+x+'"' for x in t.split('.')) for t in sorted(tables)) + ' in access exclusive mode;\n'


def patched_snapshot(before):
    original = before['routines'][ORIGINAL]['definition']
    if original.count('declare c public.companies;') != 1 or original.count(' select * into c from public.companies where id=p_company for share;') != 1:
        raise ValueError('PNG original snapshot anchors changed')
    return original.replace('declare c public.companies;', 'declare c public.companies; uploaded_png jsonb;').replace(' select * into c from public.companies where id=p_company for share;', '\n uploaded_png:=private.uploaded_company_seal_snapshot(p_company);\n if uploaded_png IS NOT NULL then\n  return uploaded_png;\n end if;\n select * into c from public.companies where id=p_company for share;')


def prepare_install(before, source_root):
    validate_before(before)
    body, expected = sources(source_root)
    sql = "-- REVIEW ONLY: financial originals protected; no PNG selection activated.\nbegin;\nset local lock_timeout='3s';\nset local statement_timeout='30s';\nset local search_path='';\n"
    sql += lock_tables(PROTECTED_TABLES) + checkpoint_guard(before) + body + '\n' + observer()
    sql += "do $png_postflight$ declare b jsonb:=" + literal(json.dumps(before, separators=(',', ':'))) + "::jsonb; a jsonb:=current_setting('sko.png_observation')::jsonb; s text; begin\n"
    sql += "if (a->'data')-array[" + ','.join(map(literal, NEW_TABLES)) + "] is distinct from b->'data' or (a->'relations')-array[" + ','.join(map(literal, NEW_TABLES)) + "] is distinct from b->'relations' or a->'namespaces' is distinct from b->'namespaces' then raise exception 'PNG installation changed original catalog/data';end if;\n"
    sql += "if (select array_agg(x order by x) from jsonb_object_keys(a->'relations') x) is distinct from array[" + ','.join(map(literal, sorted(PROTECTED_TABLES + NEW_TABLES))) + "]::text[] then raise exception 'PNG new table inventory changed';end if;\n"
    for t in NEW_TABLES:
        sql += "if a#>>array['data'," + literal(t) + ",'count'] <> '0' then raise exception 'PNG selection or version already used';end if;\n"
    for sig in DEPENDENCIES:
        if sig == ORIGINAL:
            sql += "if (a#>array['routines',"+literal(sig)+"])-array['definition','source_md5'] is distinct from (b#>array['routines',"+literal(sig)+"])-array['definition','source_md5'] then raise exception 'PNG snapshot attributes changed';end if;\n"
        else:
            sql += "if a#>array['routines',"+literal(sig)+"] is distinct from b#>array['routines',"+literal(sig)+"] then raise exception 'PNG dependency changed';end if;\n"
    sql += "if (select array_agg(x order by x) from jsonb_object_keys(a->'routines') x) is distinct from array[" + ','.join(map(literal, sorted(DEPENDENCIES | NEW_ROUTINES))) + "]::text[] then raise exception 'PNG routine inventory changed';end if;\n"
    for sig in NEW_ROUTINES:
        sql += "if a#>>array['routines',"+literal(sig)+",'source_md5'] is distinct from "+literal(expected[sig.split('(')[0]])+" then raise exception 'PNG installed source changed';end if;\n"
    # The snapshot body must be exactly the reviewed transformation of the protected original.
    patched = patched_snapshot(before)
    sql += "if a#>>array['routines',"+literal(ORIGINAL)+",'definition'] is distinct from "+literal(patched)+" then raise exception 'PNG patched snapshot definition changed';end if;end $png_postflight$;\ncommit;\n"
    return sql


def prepare_restore(before, after, source_root):
    validate_before(before)
    # Reuse the same exact-source checks as install postflight before even writing restore.
    _, expected = sources(source_root)
    if set(after['data']) != set(PROTECTED_TABLES + NEW_TABLES) or set(after['relations']) != set(PROTECTED_TABLES + NEW_TABLES) or set(after['routines']) != DEPENDENCIES | NEW_ROUTINES:
        raise ValueError('PNG installed inventory mismatch')
    for t in PROTECTED_TABLES:
        if after['data'][t] != before['data'][t] or after['relations'][t] != before['relations'][t]:
            raise ValueError('PNG protected original changed')
    if after['namespaces'] != before['namespaces'] or any(after['data'][t]['count'] != 0 for t in NEW_TABLES):
        raise ValueError('PNG install is no longer unused')
    for sig in DEPENDENCIES:
        a, b = after['routines'][sig], before['routines'][sig]
        if sig == ORIGINAL:
            if a['definition'] != patched_snapshot(before):
                raise ValueError('PNG installed snapshot source differs')
            if a['attributes'] != b['attributes'] or a['owner'] != b['owner']:
                raise ValueError('PNG original snapshot attributes changed')
        elif a != b:
            raise ValueError('PNG original dependency changed')
    for sig in NEW_ROUTINES:
        if after['routines'][sig]['source_md5'] != expected[sig.split('(')[0]] or after['routines'][sig]['owner'] != 'postgres':
            raise ValueError('PNG installed source differs')
    sql="-- REVIEW ONLY: unused PNG installation only; refuses any registered or selected PNG.\nbegin;\nset local lock_timeout='3s';\nset local statement_timeout='30s';\nset local search_path='';\n"
    sql += lock_tables(PROTECTED_TABLES + NEW_TABLES) + checkpoint_guard(after)
    sql += before['routines'][ORIGINAL]['definition'].rstrip(';') + ';\n'
    sql += 'drop function ' + ','.join(sorted(s for s in NEW_ROUTINES if s.startswith('public.'))) + ';\n'
    sql += 'drop table private.company_seal_png_selection,private.company_seal_png_versions;\n'
    sql += 'drop function ' + ','.join(sorted(s for s in NEW_ROUTINES if s.startswith('private.'))) + ';\n'
    sql += checkpoint_guard(before) + 'commit;\n'
    return sql


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-root',type=Path,required=True)
    parser.add_argument('--before',type=Path)
    parser.add_argument('--after',type=Path)
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('mode',choices=['observer','install','unused-restore'])
    args=parser.parse_args()
    if args.mode=='observer': sql=observer()+"select current_setting('sko.png_observation')::jsonb as observation;\n"
    else:
        if args.before is None: parser.error('--before required')
        before=json.loads(args.before.read_text())
        if args.mode=='install': sql=prepare_install(before,args.source_root)
        else:
            if args.after is None: parser.error('--after required')
            sql=prepare_restore(before,json.loads(args.after.read_text()),args.source_root)
    write_private(args.output,sql)
    print(json.dumps({'schema':1,'prepare_only':True,'deployment_performed':False,'mode':args.mode,'sha256':hashlib.sha256(sql.encode()).hexdigest()}))


if __name__=='__main__':main()
