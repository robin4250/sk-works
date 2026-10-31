#!/usr/bin/env python3
"""Offline review-only administrator document correction deployment capsule."""
import argparse, hashlib, json, pathlib, re, uuid

CANDIDATE_SHA='8e7dcb4b2fcc3fe77ada3c5d39333d1cb0802858690fd59584d216436868b04a'
CATALOG_SHA='a98c37ad6b76d8db46e30bcb840288c51ba87ab201f63891af367a946f8be8af'
NAMES=['worker_document_admin_correction_immutable','worker_document_admin_correction_retains','worker_document_admin_correction_ticket_guard']
TABLES=['worker_document_admin_correction_state','worker_document_admin_corrections','worker_document_admin_correction_tickets','worker_document_admin_correction_photos']
POLICIES=['worker_document_admin_archive_no_overwrite','worker_document_admin_archive_no_delete']
PRED="((n.nspname='private' and p.proname in("+','.join("'"+x+"'" for x in NAMES)+"))or(n.nspname='public' and p.proname='worker_document_admin_self_correction'))"
REL="n.nspname='private' and c.relname like 'worker_document_admin_correction%'"
def sha(s):return hashlib.sha256(s.encode()).hexdigest()
def lit(s):return "'"+s.replace("'","''")+"'"
def canon(v):return json.dumps(v,sort_keys=True,separators=(',',':'),ensure_ascii=False)
def inner(s):
 if len(re.findall(r'^begin;\s*$',s,re.M))!=1 or len(re.findall(r'^commit;\s*$',s,re.M))!=1:raise ValueError('transaction anchors changed')
 return re.sub(r'^commit;\s*$','',re.sub(r'^begin;\s*$','',s,flags=re.M),flags=re.M)
def base_assert(query,digest):
 return "do $base$ declare guarded_snapshot jsonb;begin select q.snapshot into guarded_snapshot from("+query+")q;if encode(sha256(convert_to(guarded_snapshot::text,'UTF8')),'hex') is distinct from "+lit(digest)+" then raise exception 'Administrator document dependency drift';end if;end $base$;\n"
def originals():
 return "select jsonb_build_object("+','.join(lit(t)+",(select jsonb_build_object('count',count(*),'sha256',encode(sha256(convert_to(coalesce(string_agg(h,'' order by h),''),'UTF8')),'hex')) from(select encode(sha256(convert_to(to_jsonb(v)::text,'UTF8')),'hex') h from public."+t+" v)q)" for t in ['worker_document_statuses','worker_document_status_history'])+") as value"
def manifest():
 return """select jsonb_build_object(
 'functions',(select jsonb_agg(to_jsonb(p)-'oid' order by p.oid) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where %s),
 'relations',(select jsonb_agg(jsonb_build_object('name',c.relname,'class',to_jsonb(c)-array['oid','relfilenode','relpages','reltuples','relallvisible','relfrozenxid','relminmxid'],
 'columns',(select jsonb_agg(to_jsonb(a)-'attrelid' order by attnum) from pg_attribute a where attrelid=c.oid and attnum>0),
 'defaults',(select jsonb_agg(to_jsonb(a)-array['oid','adrelid'] order by adnum) from pg_attrdef a where adrelid=c.oid),
 'constraints',(select jsonb_agg(to_jsonb(a)-'oid' order by conname) from pg_constraint a where conrelid=c.oid),
 'indexes',(select jsonb_agg(to_jsonb(a) order by indexrelid) from pg_index a where indrelid=c.oid),
 'triggers',(select jsonb_agg(to_jsonb(a)-'oid' order by tgname) from pg_trigger a where tgrelid=c.oid),
 'policies',(select jsonb_agg(to_jsonb(a)-'oid' order by polname) from pg_policy a where polrelid=c.oid)) order by c.relname)
 from pg_class c join pg_namespace n on n.oid=c.relnamespace where %s),
 'types',(select jsonb_agg(to_jsonb(t)-'oid' order by typname) from pg_type t join pg_namespace n on n.oid=t.typnamespace where n.nspname='private' and (t.typname like 'worker_document_admin_correction%%' or t.typname like '_worker_document_admin_correction%%')),
 'trigger',(select jsonb_agg(to_jsonb(t)-'oid') from pg_trigger t where tgrelid='public.worker_document_statuses'::regclass and tgname='zzz_worker_document_admin_correction_ticket'),
 'storage_policies',(select jsonb_agg(to_jsonb(p)-'oid' order by polname) from pg_policy p where polrelid='storage.objects'::regclass and polname in ('worker_document_admin_archive_no_overwrite','worker_document_admin_archive_no_delete'))) as value"""%(PRED,REL)
def verify_new():
 return """do $module$ begin
 if(select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where %s)<>4 then raise exception 'Correction function inventory changed';end if;
 if exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where %s and
 (pg_get_userbyid(proowner)<>'postgres' or not prosecdef or proconfig is distinct from array['search_path=""'] or
 exists(select 1 from aclexplode(coalesce(proacl,acldefault('f',proowner))) a where a.privilege_type<>'EXECUTE' or a.is_grantable or
 (a.grantee<>proowner and not(a.grantee='authenticated'::regrole and (n.nspname='public' or proname='worker_document_admin_correction_retains'))))))
 then raise exception 'Correction function authority changed';end if;
 if not has_function_privilege('authenticated','public.worker_document_admin_self_correction(text,jsonb)','EXECUTE') or
 not has_function_privilege('authenticated','private.worker_document_admin_correction_retains(text)','EXECUTE') or
 has_function_privilege('anon','public.worker_document_admin_self_correction(text,jsonb)','EXECUTE') or
 has_function_privilege('service_role','public.worker_document_admin_self_correction(text,jsonb)','EXECUTE') or
 has_function_privilege('authenticated','private.worker_document_admin_correction_immutable()','EXECUTE') or
 has_function_privilege('authenticated','private.worker_document_admin_correction_ticket_guard()','EXECUTE')
 then raise exception 'Correction inherited authority changed';end if;
 if(select count(*) from pg_class c join pg_namespace n on n.oid=relnamespace where %s)<>9 then raise exception 'Correction relation inventory changed';end if;
 if exists(select 1 from pg_class c join pg_namespace n on n.oid=relnamespace where %s and
 (pg_get_userbyid(relowner)<>'postgres' or exists(select 1 from aclexplode(coalesce(relacl,acldefault('r',relowner))) a where a.grantee<>relowner))) then raise exception 'Correction relation authority changed';end if;
 if(select count(*) from pg_class c join pg_namespace n on n.oid=relnamespace where n.nspname='private' and relname in(%s) and relkind='r' and relrowsecurity and not relforcerowsecurity)<>4 then raise exception 'Correction RLS changed';end if;
 if(select count(*) from pg_trigger t where tgrelid='public.worker_document_statuses'::regclass and tgname='zzz_worker_document_admin_correction_ticket' and tgfoid='private.worker_document_admin_correction_ticket_guard()'::regprocedure and tgtype=19 and tgenabled='O' and not tgisinternal and tgconstraint=0 and not tgdeferrable and not tginitdeferred and tgnargs=0 and tgattr::text='' and octet_length(tgargs)=0 and tgqual is null)<>1 then raise exception 'Correction trigger changed';end if;
 if(select count(*) from pg_policy p where polrelid='storage.objects'::regclass and polname in('worker_document_admin_archive_no_overwrite','worker_document_admin_archive_no_delete') and not polpermissive and polroles=array['authenticated'::regrole::oid] and polcmd in('w','d'))<>2 then raise exception 'Correction Storage restrictions changed';end if;
 if(select count(*) from private.worker_document_admin_correction_state)<>1 or
 (select enabled from private.worker_document_admin_correction_state where singleton) is distinct from false or
 exists(select 1 from private.worker_document_admin_corrections) or exists(select 1 from private.worker_document_admin_correction_tickets) or exists(select 1 from private.worker_document_admin_correction_photos) then raise exception 'Correction module not OFF and unused';end if;
 end $module$;
 """%(PRED,PRED,REL,REL,','.join(lit(t) for t in TABLES))
def prepare(capture,catalog,candidate,output,nonce=None):
 if sha(catalog)!=CATALOG_SHA or sha(candidate)!=CANDIDATE_SHA:raise ValueError('pinned source changed')
 snap=capture.get('snapshot');digest=capture.get('snapshot_sha256')
 if not isinstance(snap,dict) or not isinstance(digest,str) or not re.fullmatch('[0-9a-f]{64}',digest):raise ValueError('full server catalog/hash required')
 if snap.get('role')!='postgres' or len(snap.get('relations',[]))!=17 or not all(r.get('present') for r in snap['relations'] if not r['name'].startswith('private.worker_document_')) or len(snap.get('schemas',[]))!=4:raise ValueError('complete deployment-role dependency catalog required')
 if snap.get('version')!=2 or int(snap.get('server_version_num',0))//10000!=17:raise ValueError('PostgreSQL17 catalog/version required')
 legacy=[r for r in snap['relations'] if r['name'].startswith('private.worker_document_')]
 if len(legacy)!=5 or sum(bool(r.get('present')) for r in legacy) not in (0,5):raise ValueError('partial old request module requires independent review')
 if snap.get('worker_document_bucket',{}).get('public') is not False:raise ValueError('private document bucket required')
 marker={'contract':'worker_document_admin_self_correction_guard_v1','source_sha256':CANDIDATE_SHA,'before_sha256':digest,'before_export_sha256':sha(canon(snap)),'deployment_id':nonce or uuid.uuid4().hex,'activated':False}
 query=catalog.strip().rstrip(';');base=base_assert(query,digest)
 prefix="-- REVIEW ONLY; no production approval; preserves originals.\nbegin;\nset local lock_timeout='3s';\nset local statement_timeout='60s';\nset local standard_conforming_strings=on;\nlock table public.worker_document_statuses,public.worker_document_status_history in share mode;\n"+base
 absent="do $absent$ begin if exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where "+PRED+") or exists(select 1 from pg_class c join pg_namespace n on n.oid=relnamespace where "+REL+") or exists(select 1 from pg_type t join pg_namespace n on n.oid=typnamespace where n.nspname='private' and (typname like 'worker_document_admin_correction%' or typname like '_worker_document_admin_correction%')) or exists(select 1 from pg_trigger where tgrelid='public.worker_document_statuses'::regclass and tgname='zzz_worker_document_admin_correction_ticket') or exists(select 1 from pg_policy where polrelid='storage.objects'::regclass and polname in('worker_document_admin_archive_no_overwrite','worker_document_admin_archive_no_delete')) then raise exception 'Correction module exists; reconcile rather than reinstall';end if;end $absent$;\n"
 preserved="do $originals$ declare after_digest jsonb;begin select q.value into after_digest from("+originals()+")q;if after_digest is distinct from(select value from sko_admin_original_digests) then raise exception 'Original documents changed';end if;end $originals$;\n"
 stamp="do $stamp$ declare m jsonb;v jsonb;begin select q.value into m from("+manifest()+")q;v:="+lit(canon(marker))+"::jsonb||jsonb_build_object('module_sha256',encode(sha256(convert_to(m::text,'UTF8')),'hex'));execute format('comment on table private.worker_document_admin_correction_state is %L',v::text);end $stamp$;\n"
 install=prefix+absent+'create temp table sko_admin_original_digests on commit drop as '+originals()+';\n'+inner(candidate)+base+verify_new()+preserved+stamp+"select obj_description('private.worker_document_admin_correction_state'::regclass,'pg_class')::jsonb as receipt;\ncommit;\n"
 receipt="do $receipt$ declare s jsonb;m jsonb;begin s:=obj_description('private.worker_document_admin_correction_state'::regclass,'pg_class')::jsonb;if s-'module_sha256' is distinct from "+lit(canon(marker))+"::jsonb then raise exception 'Correction installation receipt changed or activated';end if;select q.value into m from("+manifest()+")q;if s->>'module_sha256' is distinct from encode(sha256(convert_to(m::text,'UTF8')),'hex') then raise exception 'Correction module catalog drift';end if;end $receipt$;\n"
 protected=prefix+receipt+verify_new()+'create temp table sko_admin_original_digests on commit drop as '+originals()+';\n'
 drop="drop trigger zzz_worker_document_admin_correction_ticket on public.worker_document_statuses;\ndrop policy worker_document_admin_archive_no_overwrite on storage.objects;\ndrop policy worker_document_admin_archive_no_delete on storage.objects;\ndrop trigger worker_document_admin_correction_immutable on private.worker_document_admin_corrections;\ndrop trigger worker_document_admin_correction_photos_immutable on private.worker_document_admin_correction_photos;\ndrop function public.worker_document_admin_self_correction(text,jsonb);\ndrop function private.worker_document_admin_correction_ticket_guard();\ndrop function private.worker_document_admin_correction_retains(text);\ndrop function private.worker_document_admin_correction_immutable();\ndrop table private.worker_document_admin_correction_tickets,private.worker_document_admin_correction_photos,private.worker_document_admin_corrections,private.worker_document_admin_correction_state;\n"
 restore=protected+drop+base+preserved+'commit;\n'
 enable=protected+"do $enable$ declare s jsonb;begin perform 1 from private.worker_document_admin_correction_state where singleton and not enabled for update;if not found then raise exception 'Correction activation state changed';end if;update private.worker_document_admin_correction_state set enabled=true where singleton;s:=obj_description('private.worker_document_admin_correction_state'::regclass,'pg_class')::jsonb||jsonb_build_object('activated',true);execute format('comment on table private.worker_document_admin_correction_state is %L',s::text);end $enable$;\n"+preserved+"select jsonb_build_object('enabled',enabled,'receipt',obj_description('private.worker_document_admin_correction_state'::regclass,'pg_class')::jsonb) as activation_receipt from private.worker_document_admin_correction_state;\ncommit;\n"
 enable=enable.replace('-- REVIEW ONLY; no production approval; preserves originals.','-- SEPARATE EXPLICIT GLOBAL ON APPROVAL REQUIRED; not authorized by OFF install.')
 out=pathlib.Path(output);out.mkdir(parents=True,exist_ok=False)
 for name,body in [('install-off.guarded.sql.review-only',install),('restore-unused.guarded.sql.review-only',restore),('enable-separately-approved.guarded.sql.review-only',enable)]: (out/name).write_text(body)
 (out/'proposal.json').write_text(json.dumps({'marker':marker,'files':{n:sha((out/n).read_text()) for n in ['install-off.guarded.sql.review-only','restore-unused.guarded.sql.review-only','enable-separately-approved.guarded.sql.review-only']},'production_applied':False,'production_enabled':False,'business_rows_read_during_preparation':0},indent=2)+'\n')
 return out
if __name__=='__main__':
 a=argparse.ArgumentParser();a.add_argument('--before',required=True);a.add_argument('--catalog',required=True);a.add_argument('--candidate',required=True);a.add_argument('--output',required=True);x=a.parse_args()
 prepare(json.loads(pathlib.Path(x.before).read_text()),pathlib.Path(x.catalog).read_text(),pathlib.Path(x.candidate).read_text(),x.output)
