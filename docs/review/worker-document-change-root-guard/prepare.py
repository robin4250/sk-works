#!/usr/bin/env python3
"""Offline guarded OFF deployment proposal. No network/database connection."""
import argparse, hashlib, json, pathlib, re, uuid

CATALOG_SHA='fcab71fb136b7f71ed378c03830267df9b3558fea9dcbb8be17bfdc78d72cb17'
INSTALL_SHA='1f078c9a60e8c19163e7656a5067dec8ae9e20e0703cbd06073069c9e6f830ca'
RESTORE_SHA='22a5b160761a6e631858fd29d81263367ffe1bad7eed21be7446a8d055bc4e82'
TABLES=['worker_document_changes','worker_document_apply_tickets','worker_document_change_events','worker_document_change_rollout','worker_document_change_installation']
NAMES=['worker_document_change_enabled','worker_document_change_snapshot','worker_document_change_can_manage','worker_document_change_can_review','worker_document_change_can_access','worker_document_change_guard','worker_document_change_result','worker_document_change','worker_document_change_catalog']
PRED="((n.nspname='private' and p.proname in ("+','.join("'"+x+"'" for x in NAMES)+")) or (n.nspname='public' and p.proname='worker_document_change'))"
REL_PRED="n.nspname='private' and (c.relname like 'worker_document_change%' or c.relname like 'worker_document_apply_ticket%')"
def sha(s): return hashlib.sha256(s.encode()).hexdigest()
def lit(s): return "'"+s.replace("'","''")+"'"
def canonical(v): return json.dumps(v,sort_keys=True,separators=(',',':'),ensure_ascii=False)
def inner(sql):
    if len(re.findall(r'^begin;\s*$',sql,re.M))!=1 or len(re.findall(r'^commit;\s*$',sql,re.M))!=1: raise ValueError('transaction anchors changed')
    return re.sub(r'^commit;\s*$','',re.sub(r'^begin;\s*$','',sql,flags=re.M),flags=re.M)

def module_manifest():
    return """select jsonb_build_object(
 'functions',(select jsonb_agg(to_jsonb(p)-'oid' order by p.oid) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where %s),
 'classes',(select jsonb_agg(jsonb_build_object('name',c.relname,'attributes',to_jsonb(c)-array['oid','relfilenode','relpages','reltuples','relallvisible','relfrozenxid','relminmxid'],
 'columns',(select jsonb_agg(to_jsonb(a)-'attrelid' order by attnum) from pg_attribute a where attrelid=c.oid and attnum>0),
 'defaults',(select jsonb_agg(to_jsonb(a)-array['oid','adrelid'] order by adnum) from pg_attrdef a where adrelid=c.oid),
 'constraints',(select jsonb_agg(to_jsonb(a)-'oid' order by conname) from pg_constraint a where conrelid=c.oid),
 'indexes',(select jsonb_agg(to_jsonb(a) order by indexrelid) from pg_index a where indrelid=c.oid),
 'policies',(select jsonb_agg(to_jsonb(a)-'oid' order by polname) from pg_policy a where polrelid=c.oid)) order by c.relname)
 from pg_class c join pg_namespace n on n.oid=c.relnamespace where %s),
 'sequences',(select jsonb_agg(to_jsonb(s)||jsonb_build_object('seqstart',s.seqstart::text,'seqincrement',s.seqincrement::text,'seqmax',s.seqmax::text,'seqmin',s.seqmin::text,'seqcache',s.seqcache::text) order by s.seqrelid) from pg_sequence s join pg_class c on c.oid=s.seqrelid join pg_namespace n on n.oid=c.relnamespace where %s),
 'types',(select jsonb_agg(to_jsonb(t)-'oid' order by t.typname) from pg_type t join pg_namespace n on n.oid=t.typnamespace where n.nspname='private' and
 (t.typname like 'worker_document_change%%' or t.typname like '_worker_document_change%%' or t.typname like 'worker_document_apply_ticket%%' or t.typname like '_worker_document_apply_ticket%%')),
 'trigger',(select jsonb_agg(to_jsonb(t)-'oid') from pg_trigger t where tgrelid='public.worker_document_statuses'::regclass and tgname='zz_worker_document_change_guard')) as manifest"""%(PRED,REL_PRED,REL_PRED)

def base_assert(query,expected_digest):
    if not re.fullmatch('[0-9a-f]{64}',expected_digest): raise ValueError('server catalog SHA256 required')
    return "do $base$ declare actual jsonb;begin\nselect q.snapshot into actual from ("+query+")q;\nif encode(sha256(convert_to(actual::text,'UTF8')),'hex') is distinct from "+lit(expected_digest)+" then raise sqlstate '55000' using message='Document dependency catalog drift';end if;\nend $base$;\n"

def original_digest():
    parts=[]
    for table in ['worker_document_statuses','worker_document_status_history']:
        parts.append(lit(table)+",(select jsonb_build_object('count',count(*),'digest',encode(sha256(convert_to(coalesce(string_agg(h,'' order by h),''),'UTF8')),'hex')) from (select encode(sha256(convert_to(to_jsonb(t)::text,'UTF8')),'hex') h from public."+table+" t)s)")
    return 'select jsonb_build_object('+','.join(parts)+') as value'

def verify_new():
    return """do $new$ declare total int;begin
 if (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where %s)<>10 then raise exception 'Document function inventory changed';end if;
 if exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where %s and
 (pg_get_userbyid(p.proowner)<>'postgres' or p.proconfig is distinct from array['search_path=""'] or
 p.prosecdef is distinct from (p.proname<>'worker_document_change_snapshot') or
 exists(select 1 from aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a where
 a.privilege_type<>'EXECUTE' or (a.grantee<>p.proowner and not(n.nspname='public' and p.proname='worker_document_change' and a.grantee='authenticated'::regrole and not a.is_grantable))))) then raise exception 'Document function authority changed';end if;
 if has_function_privilege('anon','public.worker_document_change(text,jsonb)','EXECUTE') or has_function_privilege('service_role','public.worker_document_change(text,jsonb)','EXECUTE') then raise exception 'Document inherited endpoint access changed';end if;
 if exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and p.proname in (%s) and (has_function_privilege('anon',p.oid,'EXECUTE') or has_function_privilege('authenticated',p.oid,'EXECUTE') or has_function_privilege('service_role',p.oid,'EXECUTE'))) then raise exception 'Document inherited private access changed';end if;
 if not has_function_privilege('authenticated','public.worker_document_change(text,jsonb)','EXECUTE') then raise exception 'Document public access missing';end if;
 if (select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where %s)<>11 then raise exception 'Document relation inventory changed';end if;
 if exists(select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace where %s and
 (pg_get_userbyid(c.relowner)<>'postgres' or exists(select 1 from aclexplode(coalesce(c.relacl,acldefault(case when c.relkind='S' then 'S'::"char" else 'r'::"char" end,c.relowner))) a where a.grantee<>c.relowner))) then raise exception 'Document relation authority changed';end if;
 if (select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='private' and c.relkind='r' and c.relname in (%s) and c.relrowsecurity and not c.relforcerowsecurity)<>5 then raise exception 'Document RLS changed';end if;
 if (select count(*) from pg_trigger t where tgrelid='public.worker_document_statuses'::regclass and tgname='zz_worker_document_change_guard'
 and tgfoid='private.worker_document_change_guard()'::regprocedure and tgtype=31 and tgenabled='O' and not tgisinternal and tgconstraint=0
 and not tgdeferrable and not tginitdeferred and tgnargs=0 and tgattr::text='' and octet_length(tgargs)=0 and tgqual is null)<>1 then raise exception 'Document trigger changed';end if;
 if (select enabled from private.worker_document_change_rollout where singleton) is distinct from false or
 exists(select 1 from private.worker_document_changes) or exists(select 1 from private.worker_document_apply_tickets) or exists(select 1 from private.worker_document_change_events)
 then raise exception 'Document module not OFF/unused';end if;
end $new$;
"""%(PRED,PRED,','.join(lit(x)for x in NAMES),REL_PRED,REL_PRED,','.join(lit(x)for x in TABLES))

def prepare(capture,catalog,install,restore,output,nonce=None):
    before=capture.get('snapshot'); digest=capture.get('snapshot_sha256')
    if not isinstance(before,dict) or not isinstance(digest,str) or not re.fullmatch('[0-9a-f]{64}',digest): raise ValueError('server catalog SHA256 capture required')
    if sha(catalog)!=CATALOG_SHA: raise ValueError('catalog query source changed')
    if sha(install)!=INSTALL_SHA or sha(restore)!=RESTORE_SHA: raise ValueError('immutable session successor changed')
    if before.get('version')!=1 or before.get('role')!='postgres' or len(before.get('relations',[]))!=12 or not all(r.get('present')for r in before['relations']) or len(before.get('schemas',[]))!=4: raise ValueError('complete deployment-role catalog required')
    if not isinstance(before.get('role_authority'),dict) or len(before['role_authority'].get('roles',[]))!=4: raise ValueError('role authority snapshot required')
    if not isinstance(before.get('worker_document_bucket'),dict) or before['worker_document_bucket'].get('public') is not False: raise ValueError('private document bucket required')
    if not isinstance(before.get('functions'),list) or len(before['functions'])<3: raise ValueError('original function inventory required')
    query=catalog.strip().rstrip(';');nonce=nonce or uuid.uuid4().hex
    marker={'contract':'worker_document_change_off_guard_v1','source_sha256':INSTALL_SHA,'before_sha256':digest,'before_export_sha256':sha(canonical(before)),'deployment_id':nonce}
    base=base_assert(query,digest)
    prefix="-- REVIEW ONLY. No production authorization. OFF only; originals preserved.\nbegin;\nset local lock_timeout='3s';\nset local statement_timeout='60s';\nset local standard_conforming_strings=on;\nlock table public.worker_document_statuses,public.worker_document_status_history in share mode;\n"+base
    absent="do $absent$ begin if exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where "+PRED+") or exists(select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace where "+REL_PRED+") or exists(select 1 from pg_trigger where tgrelid='public.worker_document_statuses'::regclass and tgname='zz_worker_document_change_guard') then raise exception 'Document module exists; reconcile rather than reinstall';end if;end $absent$;\n"
    sql=prefix+absent+'create temp table sko_document_original_digests on commit drop as '+original_digest()+';\n'+inner(install)
    sql+="\n-- Limit only this newly-created public endpoint; preserve all existing ACLs.\nrevoke all on function public.worker_document_change(text,jsonb) from service_role;\nupdate private.worker_document_change_installation set catalog=private.worker_document_change_catalog() where singleton;\n"
    sql+=base+verify_new()
    sql+="do $originals$ declare after_value jsonb;begin select q.value into after_value from ("+original_digest()+")q;if after_value is distinct from (select value from sko_document_original_digests) then raise exception 'Original documents changed';end if;end $originals$;\n"
    sql+="do $receipt$ declare manifest jsonb; stamp jsonb;begin select q.manifest into manifest from ("+module_manifest()+")q;stamp:="+lit(canonical(marker))+"::jsonb||jsonb_build_object('module_sha256',encode(sha256(convert_to(manifest::text,'UTF8')),'hex'));execute format('comment on table private.worker_document_change_installation is %L',stamp::text);end $receipt$;\n"
    sql+="select obj_description('private.worker_document_change_installation'::regclass,'pg_class')::jsonb as committed_candidate_receipt;\ncommit;\n"
    output=pathlib.Path(output);output.mkdir(parents=True,exist_ok=False)
    (output/'install-off.guarded.sql.review-only').write_text(sql)
    restore_prefix=prefix+"do $receipt$ declare stamp jsonb; manifest jsonb;begin stamp:=obj_description('private.worker_document_change_installation'::regclass,'pg_class')::jsonb;if stamp- 'module_sha256' is distinct from "+lit(canonical(marker))+"::jsonb then raise exception 'Document deployment receipt mismatch';end if;select q.manifest into manifest from ("+module_manifest()+")q;if stamp->>'module_sha256' is distinct from encode(sha256(convert_to(manifest::text,'UTF8')),'hex') then raise exception 'Document module catalog changed';end if;end $receipt$;\n"
    undo=restore_prefix+"create temp table sko_document_original_digests on commit drop as "+original_digest()+";\n"+inner(restore)+base+"do $originals$ declare after_value jsonb;begin select q.value into after_value from ("+original_digest()+")q;if after_value is distinct from (select value from sko_document_original_digests) then raise exception 'Original documents changed';end if;end $originals$;\ncommit;\n"
    (output/'restore-unused.guarded.sql.review-only').write_text(undo)
    enable=restore_prefix+verify_new()+"do $enable$ begin perform 1 from private.worker_document_change_rollout where singleton and not enabled for update;if not found then raise exception 'Document activation state changed';end if;update private.worker_document_change_rollout set enabled=true where singleton;end $enable$;\nselect jsonb_build_object('enabled',enabled,'deployment_receipt',obj_description('private.worker_document_change_installation'::regclass,'pg_class')::jsonb) as activation_receipt from private.worker_document_change_rollout where singleton;\ncommit;\n"
    enable=enable.replace('-- REVIEW ONLY. No production authorization. OFF only; originals preserved.', '-- SEPARATE EXPLICIT APPROVAL REQUIRED. GLOBAL feature activation, not installation. No new uploads. Do not execute with an OFF-install approval.')
    (output/'enable-separately-approved.guarded.sql.review-only').write_text(enable)

    (output/'proposal.json').write_text(json.dumps({'marker':marker,'files':{'install-off.guarded.sql.review-only':sha(sql),'restore-unused.guarded.sql.review-only':sha(undo),'enable-separately-approved.guarded.sql.review-only':sha(enable)},'production_applied':False,'production_enabled':False,'business_rows_read_during_preparation':0},ensure_ascii=False,indent=2)+'\n')
    return output

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--before',required=True);p.add_argument('--catalog',required=True);p.add_argument('--candidate-dir',required=True);p.add_argument('--output',required=True);a=p.parse_args()
    d=pathlib.Path(a.candidate_dir)
    prepare(json.loads(pathlib.Path(a.before).read_text()),pathlib.Path(a.catalog).read_text(),(d/'install.sql.review-only').read_text(),(d/'restore-unused.sql.review-only').read_text(),a.output)
