#!/usr/bin/env python3
"""Offline checkpoint-bound annual resident tax installer/unused removal preparation."""
import argparse
import hashlib
import json
import os
import re
from pathlib import Path

def literal(value):
    return "'" + value.replace("'", "''") + "'"

def write_private(path,text):
    fd=os.open(path,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
    with os.fdopen(fd,'w') as f: f.write(text)

UNIT='docs/candidates/resident_tax_annual_20261020.sql.review-only'
NEW_SCHEMA='resident_tax_annual_private'
PROTECTED_TABLES=[
 'public.companies','public.company_members','public.workers',
 'public.worker_payroll_settings','public.payroll_statements',
 'resident_tax_private.state','resident_tax_private.entries','resident_tax_private.history']
NEW_TABLES=[NEW_SCHEMA+'.'+n for n in ('confirmations','batches','changes','undos')]
DEPENDENCIES={
 'private.account_access_allowed()',
 'private.payroll_allowed(uuid, text)',
 'private.payroll_settings_allowed(uuid, uuid, text)',
 'resident_tax_private.require_access(uuid, uuid, text)',
 'resident_tax_private.state_value(uuid, uuid)',
 'resident_tax_private.resolve(uuid, uuid, date)',
 'resident_tax_private.save_state(uuid, uuid, bigint, text, text, jsonb, boolean)',
 'payroll_scope_private.lock_scopes(jsonb, boolean)'}
PINNED={
 'resident_tax_private.save_state(uuid, uuid, bigint, text, text, jsonb, boolean)':'0607111ec8cc09f32e6173df60ec4324',
 'resident_tax_private.resolve(uuid, uuid, date)':'9eee6842f1749d3133e5d6306de37f27',
 'payroll_scope_private.lock_scopes(jsonb, boolean)':'1bce36e2e59eeb8e0144c5743b8ea800'}
NEW_ROUTINES={
 'resident_tax_annual_private.validate_year(integer)',
 'resident_tax_annual_private.cohort(uuid)',
 'resident_tax_annual_private.source(uuid, uuid)',
 'resident_tax_annual_private.amounts(uuid, uuid, integer)',
 'resident_tax_annual_private.display_amounts(uuid, uuid, integer, boolean)',
 'resident_tax_annual_private.source_amounts(jsonb, integer)',
 'resident_tax_annual_private.undo_info(uuid, uuid, integer)',
 'resident_tax_annual_private.year_complete(uuid, integer)',
 'resident_tax_annual_private.read_state(uuid, integer, uuid)',
 'resident_tax_annual_private.save_state(uuid, integer, jsonb, jsonb, uuid)',
 'resident_tax_annual_private.undo_state(uuid, integer, uuid, jsonb, uuid, uuid)',
 'public.read_company_resident_tax_annual(uuid, integer, uuid)',
 'public.save_company_resident_tax_annual(uuid, integer, jsonb, jsonb, uuid)',
 'public.undo_company_resident_tax_annual(uuid, integer, uuid, jsonb, uuid, uuid)'}
EXISTING_NAMESPACES={'private','public','resident_tax_private','payroll_scope_private'}
UNIT_HASH='bf6e11a2bdfb91b6a5623d1f9ca116f1e9849196a4de0ad5debc500bda8b4da1'

def observer():
    relations = ','.join(map(literal, PROTECTED_TABLES + NEW_TABLES))
    names = sorted({s.split('(')[0] for s in DEPENDENCIES | NEW_ROUTINES})
    functions = ','.join(map(literal, names))
    return f"""do $resident_annual_observe$
declare r record; data jsonb:='{{}}'; relations jsonb:='{{}}'; routines jsonb; namespaces jsonb; meta jsonb; row_count bigint; rows_hash text;
begin
 if current_user <> 'postgres' then raise exception 'postgres owner observer required';end if;
 -- pg_get_constraintdef/functiondef depend on search_path; normalize every observation.
 perform set_config('search_path','',true);
 if exists(select 1 from unnest(array[{','.join(map(literal, PROTECTED_TABLES))}]::text[]) w(name) where to_regclass(w.name) is null) then raise exception 'protected annual resident tax baseline relation missing';end if;
 for r in select n.nspname,c.relname,c.oid from pg_class c join pg_namespace n on n.oid=c.relnamespace where (n.nspname||'.'||c.relname in ({relations}) or n.nspname='resident_tax_annual_private') and c.relkind in('r','p') order by n.nspname,c.relname loop
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
 select coalesce(jsonb_object_agg(n.nspname||'.'||p.proname||'('||oidvectortypes(p.proargtypes)||')',jsonb_build_object('source_md5',md5(p.prosrc),'definition',pg_get_functiondef(p.oid),'owner',pg_get_userbyid(p.proowner),'attributes',to_jsonb(p)-'prosrc')),'{{}}') into routines from pg_proc p join pg_namespace n on n.oid=p.pronamespace where p.prokind='f' and (n.nspname||'.'||p.proname in ({functions}) or n.nspname='resident_tax_annual_private');
 select coalesce(jsonb_object_agg(n.nspname,jsonb_build_object('owner',pg_get_userbyid(n.nspowner),'acl',n.nspacl)),'{{}}') into namespaces from pg_namespace n where n.nspname in('private','public','resident_tax_private','payroll_scope_private','resident_tax_annual_private');
 perform set_config('sko.resident_annual_observation',jsonb_build_object('schema',1,'data',data,'relations',relations,'routines',routines,'namespaces',namespaces)::text,true);
end $resident_annual_observe$;
"""

def lock_tables(tables):
    if any(not re.fullmatch(r'[a-z_]+\.[a-z_]+', t) for t in tables):
        raise ValueError('unexpected PNG relation identifier')
    return 'lock table ' + ','.join('.'.join('"'+x+'"' for x in t.split('.')) for t in sorted(tables)) + ' in access exclusive mode;\n'


def sources(root):
    raw=(root/UNIT).read_bytes()
    if hashlib.sha256(raw).hexdigest()!=UNIT_HASH:
        raise ValueError('reviewed annual unit changed')
    text=raw.decode()
    prefix='-- Review-only annual confirmation. No seed, activation or production application.\nbegin;\n'
    if not text.startswith(prefix) or not text.rstrip().endswith('commit;'):
        raise ValueError('annual transaction envelope changed')
    expected={}
    for m in re.finditer(r'create function ([a-z_]+\.[a-z_]+)\(.*?\breturns\b(.*?)\bas \$\$(.*?)\$\$;',text,re.S):
        header=m[2]
        expected[m[1]]={'source_md5':hashlib.md5(m[3].encode()).hexdigest(),
            'security_definer':'security definer' in header,
            'volatility':'i' if re.search(r'\bimmutable\b',header) else 's' if re.search(r'\bstable\b',header) else 'v'}
    if set(expected)!={x.split('(')[0] for x in NEW_ROUTINES}:
        raise ValueError('annual function inventory differs')
    return text[len(prefix):].rstrip()[:-len('commit;')],expected


def validate_before(before):
    if before.get('schema')!=1 or set(before['data'])!=set(PROTECTED_TABLES) or set(before['relations'])!=set(PROTECTED_TABLES):
        raise ValueError('complete annual original checkpoint required')
    if set(before['routines'])!=DEPENDENCIES or set(before['namespaces'])!=EXISTING_NAMESPACES:
        raise ValueError('annual dependency/schema inventory differs')
    for sig,digest in PINNED.items():
        p=before['routines'][sig]
        if p['source_md5']!=digest or p['owner']!='postgres' or not p['attributes']['prosecdef'] or p['attributes']['proconfig']!=['search_path=""']:
            raise ValueError('annual pinned prerequisite differs')


def checkpoint_guard(value):
    return observer()+"do $resident_annual_guard$ begin if current_setting('sko.resident_annual_observation')::jsonb is distinct from "+literal(json.dumps(value,separators=(',',':')))+"::jsonb then raise exception 'annual catalog/data checkpoint changed';end if;end $resident_annual_guard$;\n"


def new_object_guard(expected):
    sql="if a#>>array['namespaces','resident_tax_annual_private','owner'] is distinct from 'postgres' then raise exception 'annual schema owner differs';end if;\n"
    for table in NEW_TABLES:
        sql+="if a#>>array['data',"+literal(table)+",'count'] <> '0' or a#>>array['relations',"+literal(table)+",'owner'] <> 'postgres' or a#>>array['relations',"+literal(table)+",'rls'] <> 'true' then raise exception 'annual table is used or protection differs';end if;\n"
    for sig in sorted(NEW_ROUTINES):
        e=expected[sig.split('(')[0]]
        sql+="if a#>>array['routines',"+literal(sig)+",'source_md5'] is distinct from "+literal(e['source_md5'])+" or a#>>array['routines',"+literal(sig)+",'owner'] <> 'postgres' or a#>array['routines',"+literal(sig)+",'attributes','proconfig'] is distinct from '[\"search_path=\\\"\\\"\"]'::jsonb or a#>>array['routines',"+literal(sig)+",'attributes','prosecdef'] <> "+literal(str(e['security_definer']).lower())+" or a#>>array['routines',"+literal(sig)+",'attributes','provolatile'] <> "+literal(e['volatility'])+" then raise exception 'annual installed source/attributes differs';end if;\n"
    # The candidate's own ACL postcondition rejects all nonowner grants except
    # authenticated usage and the six specifically public/invoked functions.
    sql+="if exists(select 1 from pg_class c cross join lateral aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) g where c.relnamespace='resident_tax_annual_private'::regnamespace and g.grantee<>c.relowner) then raise exception 'annual table grants differ';end if;\n"
    sql+="if exists(select 1 from pg_namespace n cross join lateral aclexplode(coalesce(n.nspacl,acldefault('n',n.nspowner)))g where n.nspname='resident_tax_annual_private' and g.grantee<>n.nspowner and not(g.grantee='authenticated'::regrole and g.privilege_type='USAGE' and not g.is_grantable)) then raise exception 'annual schema grants differ';end if;\n"
    entrypoints={s for s in NEW_ROUTINES if s.startswith('public.') or s.split('(')[0].split('.')[-1] in ('read_state','save_state','undo_state')}
    allowed=','.join(literal(s)+'::regprocedure' for s in sorted(entrypoints))
    all_funcs=','.join(literal(s)+'::regprocedure' for s in sorted(NEW_ROUTINES))
    sql+="if exists(select 1 from pg_proc p cross join lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner)))g where p.oid in("+all_funcs+") and g.grantee<>p.proowner and not(g.grantee='authenticated'::regrole and g.privilege_type='EXECUTE' and not g.is_grantable and p.oid in("+allowed+"))) then raise exception 'annual function grants differ';end if;\n"
    return sql


def postflight(before,expected):
    sql=observer()+"do $resident_annual_postflight$ declare b jsonb:="+literal(json.dumps(before,separators=(',',':')))+"::jsonb; a jsonb:=current_setting('sko.resident_annual_observation')::jsonb; begin\n"
    sql+="if (a->'data')-array["+','.join(map(literal,NEW_TABLES))+"] is distinct from b->'data' or (a->'relations')-array["+','.join(map(literal,NEW_TABLES))+"] is distinct from b->'relations' or (a->'routines')-array["+','.join(map(literal,sorted(NEW_ROUTINES)))+"] is distinct from b->'routines' or (a->'namespaces')-'resident_tax_annual_private' is distinct from b->'namespaces' then raise exception 'annual installation changed originals';end if;\n"
    for section,expected_names in [('relations',set(PROTECTED_TABLES+NEW_TABLES)),('data',set(PROTECTED_TABLES+NEW_TABLES)),('routines',DEPENDENCIES|NEW_ROUTINES),('namespaces',EXISTING_NAMESPACES|{NEW_SCHEMA})]:
        sql+="if (select array_agg(x order by x collate \"C\") from jsonb_object_keys(a->"+literal(section)+")x) is distinct from array["+','.join(map(literal,sorted(expected_names)))+"]::text[] then raise exception 'annual installed inventory differs: "+section+"';end if;\n"
    return sql+new_object_guard(expected)+"end $resident_annual_postflight$;\n"


def prepare_install(before,root):
    validate_before(before)
    body,expected=sources(root)
    return "-- REVIEW ONLY: initial schema/API installation, no tax input or confirmation.\nbegin;\nset local lock_timeout='3s';\nset local statement_timeout='30s';\nset local search_path='';\n"+lock_tables(PROTECTED_TABLES)+checkpoint_guard(before)+body+'\n'+postflight(before,expected)+'commit;\n'


def prepare_restore(before,after,root):
    validate_before(before)
    _,expected=sources(root)
    if set(after['data'])!=set(PROTECTED_TABLES+NEW_TABLES) or set(after['relations'])!=set(PROTECTED_TABLES+NEW_TABLES) or set(after['routines'])!=DEPENDENCIES|NEW_ROUTINES or set(after['namespaces'])!=EXISTING_NAMESPACES|{NEW_SCHEMA}:
        raise ValueError('annual installed inventory differs')
    for section in ('data','relations'):
        if any(after[section][t]!=before[section][t] for t in PROTECTED_TABLES):
            raise ValueError('annual protected original changed')
    if any(after['routines'][s]!=before['routines'][s] for s in DEPENDENCIES) or any(after['namespaces'][s]!=before['namespaces'][s] for s in EXISTING_NAMESPACES):
        raise ValueError('annual dependency/schema changed')
    if any(after['data'][t]['count']!=0 for t in NEW_TABLES):
        raise ValueError('annual installation already used; removal is not a financial undo')
    for sig in NEW_ROUTINES:
        p=after['routines'][sig];e=expected[sig.split('(')[0]]
        if p['source_md5']!=e['source_md5'] or p['owner']!='postgres' or p['attributes']['proconfig']!=['search_path=""'] or p['attributes']['prosecdef']!=e['security_definer'] or p['attributes']['provolatile']!=e['volatility']:
            raise ValueError('annual installed source/attributes differs')
    sql="-- REVIEW ONLY: unused installation removal; never reverses financial updates.\nbegin;\nset local lock_timeout='3s';\nset local statement_timeout='30s';\nset local search_path='';\n"+lock_tables(PROTECTED_TABLES+NEW_TABLES)+checkpoint_guard(after)+postflight(before,expected)
    sql+='drop function '+','.join(sorted(s for s in NEW_ROUTINES if s.startswith('public.')))+';\n'
    sql+='drop table '+','.join(sorted(NEW_TABLES))+';\n'
    sql+='drop function '+','.join(sorted(s for s in NEW_ROUTINES if not s.startswith('public.')))+';\n'
    sql+='drop schema resident_tax_annual_private;\n'+checkpoint_guard(before)+'commit;\n'
    return sql


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--source-root',type=Path,required=True)
    p.add_argument('--before',type=Path)
    p.add_argument('--after',type=Path)
    p.add_argument('--output',type=Path,required=True)
    p.add_argument('mode',choices=['observer','install','unused-restore'])
    a=p.parse_args()
    if a.mode=='observer': sql=observer()+"select current_setting('sko.resident_annual_observation')::jsonb as observation;\n"
    else:
        if a.before is None: p.error('--before required')
        before=json.loads(a.before.read_text())
        if a.mode=='install': sql=prepare_install(before,a.source_root)
        else:
            if a.after is None:p.error('--after required')
            sql=prepare_restore(before,json.loads(a.after.read_text()),a.source_root)
    write_private(a.output,sql)
    print(json.dumps({'schema':1,'prepare_only':True,'deployment_performed':False,'mode':a.mode,'sha256':hashlib.sha256(sql.encode()).hexdigest()}))


if __name__=='__main__':main()
