"""Compact execution envelope with database-canonical full-metadata fingerprints.
Uses the capture/RESTRICT/full-row digest design of prepare.py and supervisor guard.
"""
from pathlib import Path
import json,hashlib,argparse,re
import prepare as g
R=g.ROOT;lit=g.lit;jl=g.jl;arr=g.arr
BASE=g.CAPTURE.rstrip().removesuffix(';')
CAPTURE="select snapshot||jsonb_build_object('functions',(select jsonb_agg(f||jsonb_build_object('metadata_md5',md5((f->'metadata')::text),'except_source_md5',md5(((f->'metadata')-'prosrc')::text)))from jsonb_array_elements(snapshot->'functions')f),'tables_md5',md5((snapshot->'tables')::text),'dependency_tables_md5',md5((snapshot->'dependency_tables')::text),'schemas_md5',md5((snapshot->'schemas')::text),'default_acl_md5',md5((snapshot->'default_acl')::text))snapshot from ("+BASE+")x;"
SCHEMAS="select jsonb_agg(to_jsonb(ns)order by oid)from pg_namespace ns where nspname in('private','public','auth')"
DEFAULTS="select coalesce(jsonb_agg(to_jsonb(d)order by oid),'[]')from pg_default_acl d"
def check(q,h,tag):return 'if (select md5(('+q+')::text))is distinct from '+lit(h)+" then raise exception '"+tag+"';end if;"
def compose(s,body):
 if not s['module_absent']or not s['public_api_absent']or s['operator']!='postgres':raise ValueError('absent module and postgres required')
 if len(re.findall(r'^begin;\s*$',body,re.M))!=1 or len(re.findall(r'^commit;\s*$',body,re.M))!=1:raise ValueError('one product transaction required')
 depq=g.table_query(arr([t['name']for t in s['dependency_tables']]))
 originals=[dict(signature=f['signature'],definition=f['definition'],metadata_md5=f['metadata_md5'])for f in s['functions']if f['signature']in g.CHANGED]
 if len(originals)!=4:raise ValueError('four originals required')
 deps=[dict(signature=f['signature'],metadata_md5=f['metadata_md5'])for f in s['functions']]
 prefix=['begin;',"set local search_path='';set local lock_timeout='5s';set local statement_timeout='45s';",'lock table '+','.join(g.TABLES)+' in access exclusive mode;']
 before="do $before$ begin if current_user<>'postgres'or session_user<>'postgres'then raise exception 'adjustment_operator';end if;if to_regnamespace('document_adjustment_private')is not null then raise exception 'adjustment_schema_exists';end if;"
 before+=''.join('if to_regprocedure('+lit(x)+")is not null then raise exception 'adjustment_api_exists';end if;"for x in g.PUBLIC_API)
 before+=''.join(check('select to_jsonb(p)from pg_proc p where p.oid=to_regprocedure('+lit(f['signature'])+')',f['metadata_md5'],'adjustment_dependency_metadata_drift')for f in s['functions'])
 before+=check(g.TABLE_QUERY,s['tables_md5'],'adjustment_table_catalogue_drift')+check(depq,s['dependency_tables_md5'],'adjustment_dependency_table_drift')+check(SCHEMAS,s['schemas_md5'],'adjustment_schema_acl_drift')+check(DEFAULTS,s['default_acl_md5'],'adjustment_default_acl_drift')+'end $before$;'
 product=re.sub(r'^(?:begin|commit);\s*$','',body,flags=re.M)
 # All new relations, sequences, routine identities and original table catalogues covered.
 catalog="create function document_adjustment_private.guard_catalogue()returns jsonb language sql stable security definer set search_path='' as $cat$select jsonb_build_object('schema',(select to_jsonb(n)from pg_namespace n where nspname='document_adjustment_private'),'relations',("+g.table_query("array(select n.nspname||'.'||c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='document_adjustment_private'and c.relkind in('r','p'))")+"),'external_tables',("+g.TABLE_QUERY+"),'dependency_tables',("+depq+"),'sequences',(select jsonb_agg(to_jsonb(q)order by q.seqrelid)from pg_sequence q join pg_class c on c.oid=q.seqrelid join pg_namespace n on n.oid=c.relnamespace where n.nspname='document_adjustment_private'))$cat$;revoke all on function document_adjustment_private.guard_catalogue()from public,anon,authenticated,service_role;"
 funcs="select coalesce(jsonb_agg(jsonb_build_object('signature',p.oid::regprocedure::text,'metadata_md5',md5(to_jsonb(p)::text))order by p.oid),'[]')from pg_proc p where p.pronamespace='document_adjustment_private'::regnamespace or p.oid in(select to_regprocedure(s)from unnest("+arr(g.CHANGED+g.PUBLIC_API)+")s)"
 seq="select coalesce(jsonb_agg(jsonb_build_object('name',schemaname||'.'||sequencename,'last_value',last_value)order by sequencename),'[]')from pg_sequences where schemaname='document_adjustment_private'"
 receipt="create table document_adjustment_private.guarded_installation(singleton boolean primary key check(singleton),originals jsonb not null,dependencies jsonb not null,installed_functions jsonb not null,catalogue_md5 text not null,sequences jsonb not null);alter table document_adjustment_private.guarded_installation enable row level security;revoke all on document_adjustment_private.guarded_installation from public,anon,authenticated,service_role;"
 receipt+=catalog+'insert into document_adjustment_private.guarded_installation values(true,'+jl(originals)+','+jl(deps)+',('+funcs+'),md5(document_adjustment_private.guard_catalogue()::text),('+seq+'));'
 empty="for n in select c.relname from pg_class c where c.relnamespace='document_adjustment_private'::regnamespace and c.relkind in('r','p')and c.relname<>'guarded_installation'loop execute format('select exists(select 1 from document_adjustment_private.%I)',n)into used;if used then raise exception 'adjustment_used_restore_refused';end if;end loop;"
 post="do $post$ declare n text;used boolean;begin "+empty
 post+=''.join(check('select '+("to_jsonb(p)-'prosrc'"if f['signature']in g.CHANGED else 'to_jsonb(p)')+'from pg_proc p where p.oid=to_regprocedure('+lit(f['signature'])+')',f['except_source_md5']if f['signature']in g.CHANGED else f['metadata_md5'],'adjustment_original_metadata_changed')for f in s['functions'])
 # Remove exactly the module's two known triggers and its new FK triggers from comparison.
 for q,h in [(g.TABLE_QUERY,s['tables_md5']),(depq,s['dependency_tables_md5'])]:
  normalized="select jsonb_agg(jsonb_set(t,'{triggers}',coalesce((select jsonb_agg(v order by (v->>'oid')::oid)from jsonb_array_elements(coalesce(nullif(t->'triggers','null'::jsonb),'[]'::jsonb))v where v->>'tgname'not in('document_adjustments_finalize_invoice','document_adjustments_finalize_certificate')and not exists(select 1 from pg_constraint fk where fk.oid=(v->>'tgconstraint')::oid and fk.connamespace='document_adjustment_private'::regnamespace)),'null'::jsonb))order by t->>'name')from jsonb_array_elements(("+q+"))t"
  post+=check(normalized,h,'adjustment_unexpected_business_catalogue_change')
 post+=check(SCHEMAS,s['schemas_md5'],'adjustment_schema_acl_drift')+'end $post$;'
 access="do $access$ begin if exists(select 1 from pg_proc p cross join lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner)))a where(p.pronamespace='document_adjustment_private'::regnamespace or p.oid in(select to_regprocedure(x)from unnest("+arr(g.PUBLIC_API)+")x))and a.grantee<>p.proowner and not(p.oid in(select to_regprocedure(x)from unnest("+arr(g.PUBLIC_API)+")x)and a.grantee='authenticated'::regrole and a.privilege_type='EXECUTE'and not a.is_grantable))then raise exception 'adjustment_new_function_acl';end if;if exists(select 1 from pg_class c cross join lateral aclexplode(coalesce(c.relacl,acldefault(case when c.relkind='S'then 's'::\"char\"else 'r'::\"char\"end,c.relowner)))a where c.relnamespace='document_adjustment_private'::regnamespace and a.grantee<>c.relowner)then raise exception 'adjustment_new_relation_acl';end if;if has_schema_privilege('service_role','document_adjustment_private','USAGE')or has_schema_privilege('anon','document_adjustment_private','USAGE')or has_schema_privilege('authenticated','document_adjustment_private','USAGE')then raise exception 'adjustment_new_schema_acl';end if;end $access$;"
 install='\n'.join(['-- REVIEW ONLY. Full metadata fingerprints are database-canonical MD5s, not source-only hashes.']+prefix+[before,g.digest_block(True),product,receipt,post,access,g.digest_block(False),'commit;'])+'\n'
 restore=prefix+["lock table "+','.join('document_adjustment_private.'+t for t in re.findall(r'create table document_adjustment_private\.([a-z_0-9]+)',product))+",document_adjustment_private.guarded_installation in access exclusive mode;",g.digest_block(True)]
 guard="do $restore$ declare r document_adjustment_private.guarded_installation%rowtype;f jsonb;n text;used boolean;begin if current_user<>'postgres'or session_user<>'postgres'then raise exception 'adjustment_operator';end if;select * into strict r from document_adjustment_private.guarded_installation;"
 guard+=check(SCHEMAS,s['schemas_md5'],'adjustment_original_schema_acl_changed')
 guard+="if exists(select 1 from pg_proc p where p.pronamespace<>'document_adjustment_private'::regnamespace and p.oid not in(select to_regprocedure(x)from unnest("+arr(g.CHANGED+g.PUBLIC_API)+")x)and p.prosrc~*'document_adjustment_private[.]')then raise exception 'adjustment_external_runtime_dependency';end if;if md5(document_adjustment_private.guard_catalogue()::text)is distinct from r.catalogue_md5 or ("+funcs+")is distinct from r.installed_functions or ("+seq+")is distinct from r.sequences then raise exception 'adjustment_installed_catalogue_changed';end if;"+empty
 guard+="for f in select value from jsonb_array_elements(r.originals)loop execute f->>'definition';end loop;for f in select value from jsonb_array_elements(r.dependencies)loop if(select md5(to_jsonb(p)::text)from pg_proc p where p.oid=to_regprocedure(f->>'signature'))is distinct from f->>'metadata_md5'then raise exception 'adjustment_original_restore_failed';end if;end loop;end $restore$;"
 restore+=[guard,'drop trigger document_adjustments_finalize_invoice on public.invoices;drop trigger document_adjustments_finalize_certificate on public.payment_certificates;']+['drop function '+x+';'for x in reversed(g.PUBLIC_API)]
 # Reuse tested reverse RESTRICT teardown loops from full-envelope composer.
 _,full_restore=g.compose(s,body)
 for tag in ['drop_helpers','drop_tables','drop_triggers']:
  restore.append(re.search(r'do \$'+tag+r'\$[\s\S]*?end \$'+tag+r'\$;',full_restore).group())
 restore+=['drop schema document_adjustment_private restrict;', 'do $catalogue_restored$ begin '+check(g.TABLE_QUERY,s['tables_md5'],'adjustment_original_tables_not_restored')+check(depq,s['dependency_tables_md5'],'adjustment_dependency_tables_not_restored')+'end $catalogue_restored$;',g.digest_block(False),'commit;']
 return install,'\n'.join(restore)+'\n'
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--snapshot');p.add_argument('--body');a=p.parse_args();(R/'capture-compact.sql').write_text(CAPTURE)
 if a.snapshot:
  s=json.loads(Path(a.snapshot).read_text());s=s if isinstance(s,dict)and'functions'in s else s[0]['snapshot'];i,r=compose(s,Path(a.body).read_text());(R/'install-off.guarded.sql.review-only').write_text(i);(R/'restore-unused.guarded.sql.review-only').write_text(r)
  m={'input_sha256':hashlib.sha256(Path(a.body).read_bytes()).hexdigest(),'snapshot_sha256':hashlib.sha256(Path(a.snapshot).read_bytes()).hexdigest(),'function_count':len(s['functions']),'locked_business_tables':len(g.TABLES),'dependency_tables':len(s['dependency_tables']),'install_sha256':hashlib.sha256(i.encode()).hexdigest(),'restore_sha256':hashlib.sha256(r.encode()).hexdigest(),'install_bytes':len(i.encode()),'restore_bytes':len(r.encode()),'production_applied':False};(R/'manifest.json').write_text(json.dumps(m,indent=2));print(json.dumps(m))
