#!/usr/bin/env python3
"""Offline review artifact preparation only. Never connects or executes SQL."""
import argparse
import hashlib
import json
import os
import re
from pathlib import Path

ORIGINAL = {
 'payroll_unit_private.resolve_company_common(uuid,uuid,date,date)': 'd56f5fa295167f8c49f6e9c1dd97b7f0',
 'payroll_unit_private.augment_settings(uuid,uuid,date,date,jsonb)': '47ee121481cea77af1e0275c686c65db',
 'payroll_unit_private.common_state(uuid,uuid,date)': 'a2de405fc0e6721fd1eaf81325a60b8d',
 'company_common_allowance_private.publish_payroll(uuid,text,date,bigint,jsonb,bigint,uuid)': '8a58b8bc819b9dd2c28298617b3da859',
}
UNIT_SHA256 = {
 'snapshot': '8265a81b98414eaa8a8ed92a781f9bfc2235dad5678bd7af24a041e26f09fe03',
 'resolver': '457ea816448c3f0fbf0bd66ae3902d33cca5126293fda0f0d0213ecf04a012b6',
 'publisher': 'ca692c956dec5dfbe7ef07e8bfe50cb5cdd172221cf48c94b53953423b534754',
}

def reviewed_sources():
    result={}
    for unit,expected in UNIT_SHA256.items():
        path=Path(__file__).resolve().parents[2]/'docs/candidates'/('company_common_canonical_'+unit+'_20261022.sql.review-only')
        data=path.read_bytes()
        if hashlib.sha256(data).hexdigest()!=expected:
            raise ValueError('review unit hash changed: '+unit)
        for match in re.finditer(r'create (?:or replace )?function ([a-z_][a-z_0-9]*\.[a-z_][a-z_0-9]*)\(.*?\bas \$\$(.*?)\$\$;',data.decode(),re.S|re.I):
            result[match[1]]=hashlib.md5(match[2].encode()).hexdigest()
    return result

NEW_TABLES = ['company_common_allowance_private.' + s for s in (
 'payroll_activation_modes', 'payroll_type_activation', 'payroll_type_activation_events')]
SCHEMAS = ['payroll_unit_private', 'company_common_allowance_private',
 'company_allowance_identity_private', 'payroll_scope_private', 'company_common_canonical_review_private']
REQUIRED_PRIVATE_TABLES = ['company_common_allowance_private.'+x for x in ('state','items','history','unit_aliases','requests','payroll_activation','payroll_publications','payroll_publication_receipts')]+['company_allowance_identity_private.'+x for x in ('state','identities','history')]+['payroll_unit_private.conditions','payroll_unit_private.quantities']
PUBLIC_TABLES = ['payroll_statements', 'payroll_adjustments', 'payroll_audit', 'attendance_entries',
 'worker_payroll_settings', 'company_rate_settings', 'workers', 'company_members', 'companies']

def literal(value):
    return "'" + value.replace("'", "''") + "'"

def observer():
    schemas = ','.join(map(literal, SCHEMAS))
    public_tables = ','.join(map(literal, PUBLIC_TABLES))
    required_tables=','.join(map(literal,['public.'+x for x in PUBLIC_TABLES]+REQUIRED_PRIVATE_TABLES))
    required_schemas=','.join(map(literal,[x for x in SCHEMAS if x!='company_common_canonical_review_private']))
    # pg_temp is not used: this read-only block creates no database object.
    return f"""do $sko_observe$
declare obsrel record; data jsonb:='{{}}'; counts jsonb:='{{}}'; rows_hash text; row_count bigint; routines jsonb; namespaces jsonb; relations jsonb:='{{}}'; relation_meta jsonb; impact jsonb;
begin
 if current_user <> 'postgres' then raise exception 'postgres owner observer required';end if;
 if exists(select 1 from unnest(array[{required_tables}]::text[]) wanted(name) where to_regclass(wanted.name) is null)
 or exists(select 1 from unnest(array[{required_schemas}]::text[]) wanted(name) where to_regnamespace(wanted.name) is null) then
  raise exception 'required canonical baseline relation or schema missing';end if;
 for obsrel in select n.nspname,c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace
 where c.relkind in ('r','p') and (n.nspname in ({schemas}) or (n.nspname='public' and c.relname in ({public_tables}))) order by n.nspname,c.relname loop
  execute format('select count(*),encode(sha256(convert_to(coalesce(jsonb_agg(v order by v::text)::text,''[]''),''UTF8'')),''hex'') from (select to_jsonb(t) v from %I.%I t) q',obsrel.nspname,obsrel.relname) into row_count,rows_hash;
  data:=data||jsonb_build_object(obsrel.nspname||'.'||obsrel.relname,jsonb_build_object('count',row_count,'sha256',rows_hash));
  counts:=counts||jsonb_build_object(obsrel.nspname||'.'||obsrel.relname,row_count);
  select jsonb_build_object('owner',pg_get_userbyid(c.relowner),'acl',c.relacl,'rls',c.relrowsecurity,'force_rls',c.relforcerowsecurity,'kind',c.relkind,'options',c.reloptions,
   'columns',(select jsonb_agg(jsonb_build_object('name',a.attname,'type',format_type(a.atttypid,a.atttypmod),'not_null',a.attnotnull,'identity',a.attidentity,'generated',a.attgenerated,'default',pg_get_expr(d.adbin,d.adrelid)) order by a.attnum) from pg_attribute a left join pg_attrdef d on d.adrelid=a.attrelid and d.adnum=a.attnum where a.attrelid=c.oid and a.attnum>0 and not a.attisdropped),
   'constraints',(select coalesce(jsonb_agg(jsonb_build_object('name',x.conname,'definition',pg_get_constraintdef(x.oid)) order by x.conname),'[]') from pg_constraint x where x.conrelid=c.oid),
   'triggers',(select coalesce(jsonb_agg(jsonb_build_object('name',t.tgname,'enabled',t.tgenabled,'definition',pg_get_triggerdef(t.oid)) order by t.tgname),'[]') from pg_trigger t where t.tgrelid=c.oid and not t.tgisinternal),
   'policies',(select coalesce(jsonb_agg(to_jsonb(p)-'oid' order by p.polname),'[]') from pg_policy p where p.polrelid=c.oid)) into relation_meta
   from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname=obsrel.nspname and c.relname=obsrel.relname;
  relations:=relations||jsonb_build_object(obsrel.nspname||'.'||obsrel.relname,relation_meta);
 end loop;
 select coalesce(jsonb_object_agg(p.oid::regprocedure::text,jsonb_build_object('source_md5',md5(p.prosrc),'definition',pg_get_functiondef(p.oid),'owner',pg_get_userbyid(p.proowner),'attributes',to_jsonb(p)-'prosrc')),'{{}}') into routines
 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where p.prokind='f' and
 (n.nspname in ({schemas}) or (n.nspname='private' and (p.proname like '%payroll%' or p.proname='account_access_allowed')) or
 (n.nspname='public' and (p.proname like '%company_common%' or p.proname='my_attendance_allowance_units' or p.proname='payroll_unit_conditions')));
 select coalesce(jsonb_object_agg(n.nspname,jsonb_build_object('owner',pg_get_userbyid(n.nspowner),'acl',n.nspacl)),'{{}}') into namespaces from pg_namespace n where n.nspname in ({schemas});
 select jsonb_build_object('companies',count(*),'positive_legacy_companies',count(*) filter(where positive_legacy),'activated_companies',count(*) filter(where active),'activated_positive_legacy_companies',count(*) filter(where active and positive_legacy),'activated_positive_legacy_with_publications',count(*) filter(where active and positive_legacy and publications>0)) into impact from (
  select c.id,exists(select 1 from public.company_rate_settings r where r.company_id=c.id and
   ((nullif(btrim(r.allowance_1_name),'') is not null and r.allowance_1_amount_yen>0) or (nullif(btrim(r.allowance_2_name),'') is not null and r.allowance_2_amount_yen>0) or (nullif(btrim(r.allowance_3_name),'') is not null and r.allowance_3_amount_yen>0))) positive_legacy,
  exists(select 1 from company_common_allowance_private.payroll_activation a where a.company_id=c.id) active,
  (select count(*) from company_common_allowance_private.payroll_publications p where p.company_id=c.id) publications from public.companies c
 ) x;
 perform set_config('sko.canonical_observation',jsonb_build_object('schema',1,'data',data,'counts',counts,'routines',routines,'namespaces',namespaces,'relations',relations,'impact',impact)::text,true);
end $sko_observe$;
"""

def load(path):
    obj=json.loads(path.read_text())
    if not isinstance(obj,dict) or obj.get('schema')!=1:
        raise ValueError('exact observation object required')
    return obj

def write_private(path,text):
    fd=os.open(path,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
    with os.fdopen(fd,'w') as f: f.write(text)

def prepare_restore(before, after):
    for sig,expected in ORIGINAL.items():
        if before['routines'][sig]['source_md5']!=expected:
            raise ValueError('original baseline mismatch: '+sig)
        if before['routines'][sig]['owner']!='postgres' or after['routines'][sig]['owner']!='postgres':
            raise ValueError('function ownership mismatch')
        # CREATE OR REPLACE must have preserved every existing attribute, including ACL.
        if before['routines'][sig]['attributes']!=after['routines'][sig]['attributes']:
            raise ValueError('original function attributes changed: '+sig)
    sources=reviewed_sources()
    for sig in (set(after['routines'])-set(before['routines']))|set(ORIGINAL):
        if after['routines'][sig]['source_md5']!=sources.get(sig.split('(')[0]):
            raise ValueError('post-install source differs from pinned unit: '+sig)
    if set(after['relations'])-set(before['relations'])!=set(NEW_TABLES) or any(after['relations'].get(k)!=v for k,v in before['relations'].items()):
        raise ValueError('existing relation catalog changed')
    if any(after['namespaces'].get(k)!=v for k,v in before['namespaces'].items()):
        raise ValueError('existing namespace changed')
    old_data=before['data']; new_data=after['data']
    if set(new_data)-set(old_data)!=set(NEW_TABLES) or not set(old_data)<=set(new_data):
        raise ValueError('unexpected table inventory')
    if any(new_data[k]!=v for k,v in old_data.items()):
        raise ValueError('installation changed existing application data')
    if any(new_data[k]['count']!=0 for k in NEW_TABLES):
        raise ValueError('activation metadata already used')
    old=before['routines']; new=after['routines']; added=set(new)-set(old)
    if not added or any(new[s]!=old[s] for s in old if s not in ORIGINAL):
        raise ValueError('unexpected existing routine change')
    expected_added={
      'company_common_canonical_review_private.snapshot_plan(uuid,text,bigint,jsonb,jsonb,text)',
      'company_common_canonical_review_private.publication_preview(uuid,text,date,bigint,jsonb,bigint,jsonb,text,uuid)',
      'company_common_canonical_review_private.resolve_legacy(uuid,uuid,date,date,jsonb,bigint,date)',
      'company_common_canonical_review_private.preview(uuid,text,date,bigint,jsonb,bigint,jsonb,text)',
      'company_common_allowance_private.preview_payroll_v2(uuid,text,date,bigint,jsonb,bigint,jsonb,text)',
      'company_common_allowance_private.publish_payroll_v2(uuid,text,date,bigint,jsonb,bigint,jsonb,text,uuid,text,boolean,text)',
      'company_common_allowance_private.read_publish_receipt_v2(uuid,uuid,jsonb)',
      'public.preview_company_common_payroll_v2(uuid,text,date,bigint,jsonb,bigint,jsonb,text)',
      'public.publish_company_common_payroll_v2(uuid,text,date,bigint,jsonb,bigint,jsonb,text,uuid,text,boolean,text)',
      'public.read_company_common_payroll_publish_receipt_v2(uuid,uuid,jsonb)',
      'public.company_common_payroll_publication_v2_contract_version()'}
    if added!=expected_added:
        raise ValueError('unexpected new routine inventory')
    if set(after['namespaces'])-set(before['namespaces'])!={'company_common_canonical_review_private'}:
        raise ValueError('unexpected namespace inventory')
    # Guard every observed routine/attribute and full protected-row digest at execution.
    sql="-- REVIEW ONLY: unused installation restore. Never applies or reverses financial data.\nbegin;\nset local lock_timeout='5s';\nset local statement_timeout='60s';\nset local search_path='';\n"
    # Block application writers before observing the unused condition. Root must
    # separately remain the only DDL writer; this is not concurrent DDL CAS.
    relations=[]
    for name in sorted(after['data']):
        if not re.fullmatch(r'[a-z_]+\.[a-z_]+',name):
            raise ValueError('unexpected relation identifier')
        relations.append('.'.join('"'+part+'"' for part in name.split('.')))
    sql+='lock table '+','.join(relations)+' in access exclusive mode;\n'
    sql+=observer()
    sql+="do $sko_guard$ begin if current_setting('sko.canonical_observation')::jsonb is distinct from "+literal(json.dumps(after,separators=(',',':')))+"::jsonb then raise exception 'post-install catalog/data changed; restore refused';end if;end $sko_guard$;\n"
    for sig in ORIGINAL:
        sql+=before['routines'][sig]['definition'].rstrip(';')+';\n'
    for sig in sorted(added,key=lambda s:(not s.startswith('public.'),s)):
        sql+='drop function '+sig+';\n'
    sql+='drop table '+','.join(NEW_TABLES)+';\ndrop schema company_common_canonical_review_private;\n'
    sql+=observer()
    sql+="do $sko_guard$ begin if current_setting('sko.canonical_observation')::jsonb is distinct from "+literal(json.dumps(before,separators=(',',':')))+"::jsonb then raise exception 'restored catalog/data differs; rollback required';end if;end $sko_guard$;\ncommit;\n"
    return sql

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--observer-output',type=Path)
    p.add_argument('--before',type=Path);p.add_argument('--after',type=Path);p.add_argument('--restore-output',type=Path)
    a=p.parse_args();os.umask(0o077)
    if a.observer_output:
        if any([a.before,a.after,a.restore_output]):p.error('choose observer or restore generation')
        text="-- REVIEW ONLY: private result contains complete function definitions.\nbegin isolation level repeatable read read only;\nset local statement_timeout='60s';\nset local search_path='';\n"+observer()+"select current_setting('sko.canonical_observation')::jsonb;\ncommit;\n"
        write_private(a.observer_output,text)
    elif all([a.before,a.after,a.restore_output]):
        text=prepare_restore(load(a.before),load(a.after));write_private(a.restore_output,text)
    else:p.error('observer-output or before/after/restore-output required')
    print('Review-only artifact created; no database connection or SQL execution. SHA256: '+hashlib.sha256(text.encode()).hexdigest())

if __name__=='__main__':main()
