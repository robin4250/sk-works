#!/usr/bin/env python3
"""PREPARE ONLY add-only subset of exact reviewed sources. Never connects."""
import argparse
import hashlib
import json
from pathlib import Path
import re

ROOT=Path(__file__).resolve().parents[2]
INVENTORY=ROOT/'tool/security_collector_deployment/inventory.read-only.sql'
SOURCE_HASHES={
 'reauthentication_proofs.sql':'51277eeb58825c81fc09d94fd9a5ad0cb9b2106eed625682656c8050f2beb073',
 'collector_storage.sql':'b96f6e4365e2e992886f38dad0f777e55665f18b03525cddf4edbdf746348207',
 'collector_public_read.sql':'2e3e5dd51c24d9f8c9553aec67a758f6ab7b9480fa6d6b8b6e01ee12bbe96f1a',
 'handler.mjs':'ae7f75504bb4a83b527e3b76685fb9147d1e0f164ef81e2af485c47315430992'}
ADDED={
 'private.reauthentication_scope(text)', 'private.reauthentication_required(text)',
 'public.reauthentication_capabilities()',
 'public.issue_reauthentication_proof(uuid,uuid,text,jsonb,text)',
 'private.consume_reauthentication_proof(text,jsonb,text)',
 'private.ingest_security_collector_event(jsonb)',
 'private.read_security_collector_events(text)', 'public.master_security_collector_events(text)'}
TABLES={'private.reauthentication_rollout','private.reauthentication_proofs',
 'private.security_collector_control','private.security_collector_events','private.security_collector_read_audit'}
BUSINESS={'public.companies','public.company_members','public.workers','public.worker_payroll_settings',
 'public.payroll_statements','public.payroll_adjustments','public.invoices',
 'private.master_admins','private.master_devices','private.account_deletion_access_restrictions'}
BRIDGE='sko_security_collector_ingest'


def literal(s):return "'"+s.replace("'","''")+"'"


def sources():
    result={}
    for name,digest in SOURCE_HASHES.items():
        raw=(ROOT/'tool/security_collector_deployment/reviewed_sources'/name).read_bytes()
        if hashlib.sha256(raw).hexdigest()!=digest:raise ValueError('reviewed source changed: '+name)
        result[name]=raw.decode()
    # Exact prefix only. It ends before the existing setter replacements, which
    # are intentionally not authorized by this additive installation.
    marker='create function public.replace_secondary_password_with_proof('
    base=result['reauthentication_proofs.sql']
    if base.count(marker)!=1:raise ValueError('proof subset boundary differs')
    unit=base.split(marker)[0]
    if re.search(r'create\s+or\s+replace|update\s+public\.',unit,re.I):
        raise ValueError('subset must never replace existing application routines')
    unit+='\n'+result['collector_storage.sql']+'\n'+result['collector_public_read.sql']
    unit=re.sub(r'(?m)^begin;\s*$', '',unit)
    unit=re.sub(r'(?m)^commit;\s*$', '',unit)
    return unit


def routine_specs(unit):
    found={}
    regex=r'create function ([\w.]+)\(([^)]*)\)\s*returns (\w+)([\s\S]*?)as (\$[\w]*\$)([\s\S]*?)\5;'
    for name,args,returns,attrs,_,body in re.findall(regex,unit,re.I):
        parts=[a.strip().split() for a in args.split(',')] if args.strip() else []
        identity=name+'('+','.join(p[-1] for p in parts)+')'
        found[identity]=dict(name=name,returns=returns,args=[p[-1] for p in parts],
          argnames=[p[0] for p in parts] or None,language='plpgsql' if 'plpgsql' in attrs else 'sql',
          source_md5=hashlib.md5(body.encode()).hexdigest(),definer='security definer' in attrs,
          volatility='i' if 'immutable' in attrs else 's' if 'stable' in attrs else 'v')
    if set(found)!=ADDED:raise ValueError('exact eight additive routines required')
    return found


def comparable(snapshot):
    value=json.loads(json.dumps(snapshot))
    value.pop('bridge_dependencies',None)
    for k in ADDED:value['routines'].pop(k,None)
    for r in value['routines'].values():r.pop('definition',None)
    for k in TABLES:value['relations'].pop(k,None)
    # Sole intentional existing-schema change: USAGE for the isolated bridge.
    acl=value['private_schema'].get('nspacl')
    if acl is not None:value['private_schema']['nspacl']=[x for x in acl if not x.startswith(BRIDGE+'=')]
    return value


def guard(snapshot,label):
    expected=json.dumps(comparable(snapshot),separators=(',',':'))
    if '$security_expected$' in expected:raise ValueError('unexpected delimiter')
    return """do $security_guard$
declare a jsonb; k text; expected jsonb:=$security_expected$%s$security_expected$::jsonb;
begin
 select inventory into a from (%s) observed;
 a:=a-'bridge_dependencies';
 for k in select jsonb_object_keys(a->'routines') loop
  if k=any(array[%s]) then a:=a#-array['routines',k];
  else a:=jsonb_set(a,array['routines',k],(a#>array['routines',k])-'definition');end if;
 end loop;
 for k in select unnest(array[%s]) loop a:=a#-array['relations',k];end loop;
 if a#>'{private_schema,nspacl}'<>'null'::jsonb then
  a:=jsonb_set(a,'{private_schema,nspacl}',(select coalesce(jsonb_agg(x),'[]') from jsonb_array_elements(a#>'{private_schema,nspacl}') x where x#>>'{}' not like 'sko_security_collector_ingest=%%'));
 end if;
 if a is distinct from expected then raise exception 'Collector %s inventory differs; re-observe without retry';end if;
end $security_guard$;
"""%(expected,INVENTORY.read_text().strip().rstrip(';'),','.join(map(literal,sorted(ADDED))),','.join(map(literal,sorted(TABLES))),label)


def new_guard(specs):
    lines=['do $new_security$ begin']
    allowed={'public.reauthentication_capabilities()':['authenticated'],
      'public.issue_reauthentication_proof(uuid,uuid,text,jsonb,text)':['service_role'],
      'private.ingest_security_collector_event(jsonb)':[BRIDGE],
      'private.read_security_collector_events(text)':['authenticated'],
      'public.master_security_collector_events(text)':['authenticated']}
    for identity,s in specs.items():
        ref=literal(identity)+'::regprocedure'
        # Pin all non-OID pg_proc attributes. Type/namespace/language/owner OIDs
        # are compared by their canonical names separately, never guessed.
        attrs=dict(proname=s['name'].split('.')[1],procost=100,prorows=0,provariadic='0',
          prosupport='-',prokind='f',prosecdef=s['definer'],proleakproof=False,proisstrict=False,
          proretset=False,provolatile=s['volatility'],proparallel='u',pronargs=len(s['args']),
          pronargdefaults=0,proallargtypes=None,proargmodes=None,proargnames=s['argnames'],
          proargdefaults=None,protrftypes=None,probin=None,prosqlbody=None,proconfig=['search_path=""'])
        drops="array['oid','pronamespace','proowner','prolang','prosrc','proacl','prorettype','proargtypes']"
        acl=['postgres=X/postgres']+[x+'=X/postgres' for x in allowed.get(identity,[])]
        lines.append("if not exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace join pg_language l on l.oid=p.prolang where p.oid="+ref+" and md5(p.prosrc)="+literal(s['source_md5'])+" and n.nspname="+literal(s['name'].split('.')[0])+" and l.lanname="+literal(s['language'])+" and pg_get_userbyid(p.proowner)='postgres' and p.prorettype="+literal(s['returns'])+"::regtype and oidvectortypes(p.proargtypes)="+literal(', '.join(s['args']))+" and to_jsonb(p)-"+drops+"="+literal(json.dumps(attrs))+"::jsonb and to_jsonb(p.proacl)="+literal(json.dumps(acl))+"::jsonb) then raise exception 'New collector routine contract differs: "+identity+"';end if;")
    columns={
      'private.reauthentication_rollout':[('scope','text',None,''),('enabled','boolean','false','')],
      'private.reauthentication_proofs':[('proof_hash','text',None,''),('actor_id','uuid',None,''),('session_id','uuid',None,''),('operation','text',None,''),('target','jsonb',None,''),('issued_at','timestamp with time zone','clock_timestamp()',''),('expires_at','timestamp with time zone',None,''),('consumed_at','timestamp with time zone',None,'')],
      'private.security_collector_control':[('singleton','boolean','true',''),('ingest_enabled','boolean','false',''),('read_enabled','boolean','false','')],
      'private.security_collector_events':[('event_id','uuid',None,''),('collector_id','uuid',None,''),('occurred_at','timestamp with time zone',None,''),('received_at','timestamp with time zone','clock_timestamp()',''),('event_kind','text',None,''),('generation','integer',None,''),('correlation_key','text',None,''),('key_epoch','date',None,''),('source_provenance','text',"'trusted_collector_observation'::text",'')],
      'private.security_collector_read_audit':[('audit_id','bigint',None,'a'),('actor_id','uuid',None,''),('read_at','timestamp with time zone','clock_timestamp()',''),('result_count','integer',None,'')]}
    constraint_counts={'private.reauthentication_rollout':2,'private.reauthentication_proofs':3,
      'private.security_collector_control':2,'private.security_collector_events':6,'private.security_collector_read_audit':2}
    constraint_defs={
      'private.reauthentication_rollout':["PRIMARY KEY (scope)","CHECK ((scope = ANY (ARRAY['secondary_password'::text, 'master_feature'::text, 'master_security'::text])))"],
      'private.reauthentication_proofs':["PRIMARY KEY (proof_hash)","CHECK ((proof_hash ~ '^[0-9a-f]{64}$'::text))","CHECK (((expires_at > issued_at) AND (expires_at <= (issued_at + '00:02:00'::interval))))"],
      'private.security_collector_control':["PRIMARY KEY (singleton)","CHECK (singleton)"],
      'private.security_collector_events':["PRIMARY KEY (event_id)","CHECK (isfinite(occurred_at))","CHECK ((event_kind = ANY (ARRAY['current_lure_touched'::text, 'retired_lure_touched'::text])))","CHECK (((generation >= 1) AND (generation <= 1000000)))","CHECK ((correlation_key ~ '^[0-9a-f]{64}$'::text))","CHECK ((source_provenance = 'trusted_collector_observation'::text))"],
      'private.security_collector_read_audit':["PRIMARY KEY (audit_id)","CHECK (((result_count >= 0) AND (result_count <= 100)))"]}
    for table in sorted(TABLES):
        lines.append("if not exists(select 1 from pg_class c where c.oid="+literal(table)+"::regclass and c.relowner='postgres'::regrole and c.relrowsecurity and not c.relforcerowsecurity and not exists(select 1 from pg_policy where polrelid=c.oid) and not exists(select 1 from aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) a where a.grantee<>c.relowner)) then raise exception 'Private collector table security differs';end if;")
        expected=[dict(name=n,type=t,default=d,identity=i,not_null=n!='consumed_at') for n,t,d,i in columns[table]]
        lines.append("if (select jsonb_agg(jsonb_build_object('name',a.attname,'type',format_type(a.atttypid,a.atttypmod),'default',pg_get_expr(d.adbin,d.adrelid),'identity',a.attidentity,'not_null',a.attnotnull) order by a.attnum) from pg_attribute a left join pg_attrdef d on d.adrelid=a.attrelid and d.adnum=a.attnum where a.attrelid="+literal(table)+"::regclass and a.attnum>0 and not a.attisdropped) is distinct from "+literal(json.dumps(expected))+"::jsonb then raise exception 'Private collector column contract differs: "+table+"';end if;")
        lines.append("if (select count(*) from pg_constraint where conrelid="+literal(table)+"::regclass)<>"+str(constraint_counts[table])+" or exists(select 1 from pg_constraint where conrelid="+literal(table)+"::regclass and (not convalidated or condeferrable or condeferred or contype not in ('p','c'))) then raise exception 'Private collector constraint contract differs';end if;")
        expected_constraints=json.dumps(sorted(constraint_defs[table]))
        lines.append("if (select jsonb_agg(def order by def collate \"C\") from (select pg_get_constraintdef(oid) def from pg_constraint where conrelid="+literal(table)+"::regclass) checks) is distinct from "+literal(expected_constraints)+"::jsonb then raise exception 'Private collector exact CHECK/PK differs: "+table+"';end if;")
        indexes=[dict(unique=True,primary=True,valid=True,ready=True,live=True,immediate=True,clustered=False,replica=False,nulls_not_distinct=False,keys='1',options='0',method='btree',expressions=None,predicate=None)]
        if table=='private.security_collector_events':indexes.append(dict(unique=False,primary=False,valid=True,ready=True,live=True,immediate=True,clustered=False,replica=False,nulls_not_distinct=False,keys='4 1',options='3 0',method='btree',expressions=None,predicate=None))
        indexes.sort(key=lambda v:(not v['primary'],v['keys']))
        lines.append("if (select jsonb_agg(jsonb_build_object('unique',i.indisunique,'primary',i.indisprimary,'valid',i.indisvalid,'ready',i.indisready,'live',i.indislive,'immediate',i.indimmediate,'clustered',i.indisclustered,'replica',i.indisreplident,'nulls_not_distinct',i.indnullsnotdistinct,'keys',i.indkey::text,'options',i.indoption::text,'method',a.amname,'expressions',pg_get_expr(i.indexprs,i.indrelid),'predicate',pg_get_expr(i.indpred,i.indrelid)) order by not i.indisprimary,i.indkey::text) from pg_index i join pg_class c on c.oid=i.indexrelid join pg_am a on a.oid=c.relam where i.indrelid="+literal(table)+"::regclass) is distinct from "+literal(json.dumps(indexes))+"::jsonb then raise exception 'Private collector index shape differs: "+table+"';end if;")
    lines.append("if exists(select 1 from private.reauthentication_rollout where enabled) or (select count(*) from private.reauthentication_rollout)<>3 or exists(select 1 from private.security_collector_control where ingest_enabled or read_enabled) or (select count(*) from private.security_collector_control)<>1 then raise exception 'Collector must remain default OFF';end if;")
    lines.append("if exists(select 1 from private.reauthentication_proofs) or exists(select 1 from private.security_collector_events) or exists(select 1 from private.security_collector_read_audit) then raise exception 'Collector has been used; unused restore is prohibited';end if;")
    lines.append("if exists(select 1 from private.security_collector_read_audit_audit_id_seq where is_called or last_value<>1) then raise exception 'Collector audit sequence used; unused restore prohibited';end if;")
    lines.append("if not exists(select 1 from pg_class c where c.oid='private.security_collector_read_audit_audit_id_seq'::regclass and c.relkind='S' and c.relowner='postgres'::regrole and not exists(select 1 from aclexplode(coalesce(c.relacl,acldefault('S',c.relowner))) a where a.grantee<>c.relowner)) then raise exception 'Private audit sequence security differs';end if;")
    lines.append("if not has_schema_privilege('sko_security_collector_ingest','private','USAGE') or has_schema_privilege('sko_security_collector_ingest','private','CREATE') then raise exception 'Bridge private schema privilege differs';end if;")
    lines.append("if exists(select 1 from pg_shdepend d where d.refclassid='pg_authid'::regclass and d.refobjid='sko_security_collector_ingest'::regrole and not (d.deptype='a' and ((d.classid='pg_namespace'::regclass and d.objid='private'::regnamespace) or (d.classid='pg_proc'::regclass and d.objid='private.ingest_security_collector_event(jsonb)'::regprocedure)))) then raise exception 'Bridge has unexpected object dependencies';end if;")
    lines.append('end $new_security$;')
    return '\n'.join(lines)+'\n'


def prepare(snapshot,output):
    before=json.loads(Path(snapshot).read_text());unit=sources();specs=routine_specs(unit)
    if before.get('schema')!=1 or set(before['business'])!=BUSINESS:raise ValueError('exact protected business inventory required')
    if any(before['routines'][k]['present'] for k in ADDED) or any(before['relations'][k]['present'] for k in TABLES):raise ValueError('additive scope already present; never reinstall')
    if any(not x['present'] for k,x in before['routines'].items() if k not in ADDED):raise ValueError('existing authorization/business routine missing')
    out=Path(output);out.mkdir(parents=True,exist_ok=False);out.chmod(0o700)
    blockers=[]
    role=before['bridge_role']
    if role is None:blockers.append('stage_one_bridge_role_provision_then_fresh_inventory_required')
    elif any(role[k] is not False for k in ['rolsuper','rolinherit','rolcreaterole','rolcreatedb','rolcanlogin','rolreplication','rolbypassrls']) or before['bridge_memberships'] or before.get('bridge_credential_absent') is not True or before.get('bridge_dependencies')!=0:
        blockers.append('bridge_role_attributes_or_memberships_differ')
    if before['authenticated_private_usage'] is not True:blockers.append('existing_authenticated_private_usage_missing')
    manifest=dict(schema=1,prepared_only=True,production_connected=False,deployment_performed=False,
      application_data_mutations=False,gates_enabled=False,source_hashes=SOURCE_HASHES,
      existing_routine_replacements=0,missing_historical_sources_reconstructed=False,
      snapshot_sha256=hashlib.sha256(Path(snapshot).read_bytes()).hexdigest(),
      native_lifecycle_proven=False,production_ready=False,
      edge_deployment_required=True,trusted_producer_provisioned=False,blockers=blockers,artifacts={})
    if not blockers:
        # Role provisioning is a separate owned stage. No CREATE/ALTER ROLE here.
        prefix="begin;set local search_path='';set local lock_timeout='3s';set local statement_timeout='30s';\n"
        names=sorted(before['relations'])
        prefix+="do $security_locks$ declare r record;begin for r in select c.oid,n.nspname,c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace where c.oid in("+','.join('to_regclass('+literal(x)+')' for x in names)+") order by c.oid loop execute format('lock table %I.%I in %s mode',r.nspname,r.relname,case when r.nspname='auth' then 'ACCESS SHARE' when r.nspname='private' and r.relname like 'security_collector%' or r.relname like 'reauthentication_%' then 'ACCESS EXCLUSIVE' else 'SHARE' end);end loop;end $security_locks$;\n"
        for name in TABLES:unit+='\nrevoke all on '+name+' from service_role,sko_security_collector_ingest;\n'
        for identity in ADDED:
            if identity!='public.issue_reauthentication_proof(uuid,uuid,text,jsonb,text)':unit+='revoke all on function '+identity+' from service_role;\n'
        check=new_guard(specs)
        install=prefix+guard(before,'before')+unit+'\n'+guard(before,'after')+check+'commit;\n'
        restore=prefix+guard(before,'unused restore before')+check
        for identity in ['public.master_security_collector_events(text)','private.read_security_collector_events(text)','private.ingest_security_collector_event(jsonb)','private.consume_reauthentication_proof(text,jsonb,text)','public.issue_reauthentication_proof(uuid,uuid,text,jsonb,text)','public.reauthentication_capabilities()','private.reauthentication_required(text)','private.reauthentication_scope(text)']:
            restore+='drop function '+identity+';\n'
        for table in ['private.security_collector_read_audit','private.security_collector_events','private.security_collector_control','private.reauthentication_proofs','private.reauthentication_rollout']:restore+='drop table '+table+';\n'
        restore+='revoke usage on schema private from sko_security_collector_ingest;\n'+guard(before,'restored')+'commit;\n'
        contents={'private-install.sql.review-only':install,
          'private-postflight.read-only.sql':'begin read only;'+guard(before,'postflight')+check+'commit;\n',
          'private-unused-restore.sql.review-only':restore}
        for name,content in contents.items():
            p=out/name;p.write_text(content);p.chmod(0o600);manifest['artifacts'][name]=hashlib.sha256(content.encode()).hexdigest()
    status=out/'prepare-status.json';status.write_text(json.dumps(manifest,indent=2)+'\n');status.chmod(0o600)
    return manifest


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('snapshot',type=Path);p.add_argument('output',type=Path)
    a=p.parse_args();print(json.dumps(prepare(a.snapshot,a.output)))
