"""Offline-only production guard compiler. Does not connect to any database.

Root captures a fresh catalogue using capture.sql and reviews the compiled OFF
installer/never-used restore. No real row values, passwords or keys are captured.
"""
from pathlib import Path
import argparse, hashlib, json, re

ROOT = Path(__file__).resolve().parent
MODULE = 'security_management_issuer_private'
APIS = ['public.prepare_decoy_management_proof(uuid,jsonb,text)', 'public.claim_decoy_management_command(text)',
        'public.complete_decoy_management_command(uuid,uuid,text,text)', 'public.fail_decoy_management_command(uuid,uuid,text)']
CORE = ['private.require_reauthentication_session()', 'public.verify_secondary_password(text)',
        'public.is_current_user_master_admin()', 'private.account_access_allowed()',
        'private.account_deletion_barrier_key(uuid)', 'auth.uid()', 'auth.jwt()',
        'extensions.crypt(text,text)', 'extensions.digest(bytea,text)', 'extensions.gen_random_bytes(integer)']
TABLES = ['auth.users', 'auth.sessions', 'private.account_deletion_access_restrictions',
          'private.master_admins', 'public.company_members', 'public.user_secondary_credentials']

def lit(value): return "'" + value.replace("'", "''") + "'"
def arr(values): return 'array[' + ','.join(map(lit, values)) + ']::text[]'
def sqljson(value): return lit(json.dumps(value, ensure_ascii=False, separators=(',', ':'))) + '::jsonb'

# Reuses the existing financial guard's authorization-relevant catalogue shape;
# planner statistics, relpages and relfrozenxid are intentionally excluded.
def table_query(names):
 return f'''select coalesce(jsonb_agg(jsonb_build_object('name',s,'relation',(select jsonb_build_object('oid',c.oid,'owner',c.relowner,'acl',c.relacl,'rls',c.relrowsecurity,'force_rls',c.relforcerowsecurity,'kind',c.relkind,'options',c.reloptions,'persistence',c.relpersistence,'replica_identity',c.relreplident)from pg_class c where c.oid=to_regclass(s)), 'columns',(select jsonb_agg(to_jsonb(a)order by a.attnum)from pg_attribute a where a.attrelid=to_regclass(s)and a.attnum>0), 'defaults',(select jsonb_agg(to_jsonb(d)order by d.oid)from pg_attrdef d where d.adrelid=to_regclass(s)), 'constraints',(select jsonb_agg(to_jsonb(k)order by k.oid)from pg_constraint k where k.conrelid=to_regclass(s)), 'indexes',(select jsonb_agg(to_jsonb(i)order by i.indexrelid)from pg_index i where i.indrelid=to_regclass(s)), 'triggers',(select jsonb_agg(to_jsonb(t)order by t.oid)from pg_trigger t where t.tgrelid=to_regclass(s)), 'policies',(select jsonb_agg(to_jsonb(p)order by p.oid)from pg_policy p where p.polrelid=to_regclass(s)))order by s),'[]')from unnest({names})s'''

TABLE_QUERY = table_query(arr(TABLES))
SCHEMAS = "select jsonb_agg(to_jsonb(n)order by oid)from pg_namespace n where nspname in('public','private','auth','extensions')"
DEFAULTS = "select coalesce(jsonb_agg(to_jsonb(d)order by oid),'[]')from pg_default_acl d"
FUNCTIONS = f'''with recursive edges as (select p.oid caller,q.oid callee from pg_proc p join pg_namespace n on n.oid=p.pronamespace cross join lateral regexp_matches(p.prosrc,'(private|public|auth|extensions)\\.([a-zA-Z_][a-zA-Z_0-9]*)[[:space:]]*\\(','g')m join pg_namespace qn on qn.nspname=m[1]join pg_proc q on q.pronamespace=qn.oid and q.proname=m[2]where n.nspname in('private','public','auth','extensions')),reachable(oid)as(select to_regprocedure(s)::oid from unnest({arr(CORE)})s union select e.callee from reachable r join edges e on e.caller=r.oid)select coalesce(jsonb_agg(jsonb_build_object('signature',(select quote_ident(n.nspname)||'.'||quote_ident(p.proname)||'('||oidvectortypes(p.proargtypes)||')'from pg_namespace n where n.oid=p.pronamespace),'metadata',to_jsonb(p),'definition',pg_get_functiondef(p.oid))order by p.oid),'[]')from pg_proc p where p.oid in(select oid from reachable)'''
CAPTURE = f'''select jsonb_build_object('operator',current_user,'session_operator',session_user,'module_absent',to_regnamespace('{MODULE}')is null,'api_absent',not exists(select 1 from unnest({arr(APIS)})s where to_regprocedure(s)is not null),'functions',({FUNCTIONS}),'tables',({TABLE_QUERY}),'schemas',({SCHEMAS}),'defaults',({DEFAULTS}))snapshot;'''

def catalogue():
 functions = f"select coalesce(jsonb_agg(to_jsonb(p)order by p.oid),'[]')from pg_proc p where p.pronamespace='{MODULE}'::regnamespace or p.oid in(select to_regprocedure(s)from unnest({arr(APIS)})s)"
 tables = table_query(f"array(select n.nspname||'.'||c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='{MODULE}'and c.relkind in('r','p'))")
 sequences = f"select coalesce(jsonb_agg(jsonb_build_object('relation',to_jsonb(c)-array['relpages','reltuples','relallvisible','relfrozenxid','relminmxid'],'sequence',to_jsonb(q))order by c.oid),'[]')from pg_sequence q join pg_class c on c.oid=q.seqrelid where c.relnamespace='{MODULE}'::regnamespace"
 return f"select jsonb_build_object('schema',(select to_jsonb(n)from pg_namespace n where nspname='{MODULE}'),'functions',({functions}),'tables',({tables}),'sequences',({sequences}))"

SEQUENCE_VALUES = f"select coalesce(jsonb_agg(jsonb_build_object('name',sequencename,'last_value',last_value)order by sequencename),'[]')from pg_sequences where schemaname='{MODULE}'"

def unchanged(snapshot):
 checks = []
 for routine in snapshot['functions']:
  checks.append(f"if(select to_jsonb(p)from pg_proc p where p.oid=to_regprocedure({lit(routine['signature'])}))is distinct from {sqljson(routine['metadata'])} then raise exception 'management_core_catalogue_drift';end if;")
 for query, value, label in [(TABLE_QUERY, snapshot['tables'], 'table'), (SCHEMAS, snapshot['schemas'], 'schema'), (DEFAULTS, snapshot['defaults'], 'default_acl')]:
  checks.append(f"if({query})is distinct from {sqljson(value)} then raise exception 'management_{label}_catalogue_drift';end if;")
 return ''.join(checks)

def compose(snapshot, source):
 if snapshot['operator'] != 'postgres' or snapshot['session_operator'] != 'postgres' or not snapshot['module_absent'] or not snapshot['api_absent']:
  raise ValueError('fresh postgres/module/API absent snapshot required')
 if len(re.findall(r'^begin;\s*$', source, re.M)) != 1 or len(re.findall(r'^commit;\s*$', source, re.M)) != 1:
  raise ValueError('one reviewed source transaction required')
 if not all(any(r['signature'].replace(' ', '') == p.replace(' ', '') for r in snapshot['functions']) for p in CORE):
  raise ValueError('core dependency missing from snapshot')
 body = re.sub(r'^(begin|commit);\s*$', '', source, flags=re.M)
 runtime_pattern = MODULE + r'[.]|(^|[^a-zA-Z_0-9])(public[.])?(' + '|'.join(p.split('.')[1].split('(')[0] for p in APIS) + r')[[:space:]]*[(]'
 pre = f"if current_user<>'postgres'or session_user<>'postgres'or to_regnamespace('{MODULE}')is not null then raise exception 'management_guard_operator_or_schema';end if;"
 pre += ''.join(f"if to_regprocedure({lit(p)})is not null then raise exception 'management_guard_api_exists';end if;" for p in APIS)
 pre += unchanged(snapshot)
 install = ["-- ROOT REVIEW ONLY. Never enables or provisions a real deployment.", 'begin;', "set local search_path='';set local lock_timeout='5s';set local statement_timeout='45s';", f'do $before$ begin {pre}end $before$;', body]
 install += [f"create table {MODULE}.guarded_installation(singleton boolean primary key check(singleton),baseline jsonb not null,installed_catalogue jsonb not null,sequence_values jsonb not null);alter table {MODULE}.guarded_installation enable row level security;revoke all on {MODULE}.guarded_installation from public,anon,authenticated,service_role;"]
 access = f'''do $access$ declare f record;acl_row record;allowed oid;begin
 if exists(select 1 from pg_namespace n cross join lateral aclexplode(coalesce(n.nspacl,acldefault('n',n.nspowner)))a where n.nspname='{MODULE}'and a.grantee<>n.nspowner)then raise exception 'management_module_schema_acl';end if;
 if exists(select 1 from pg_class c cross join lateral aclexplode(coalesce(c.relacl,acldefault(case when c.relkind='S'then'S'::"char"else'r'::"char"end,c.relowner)))a where c.relnamespace='{MODULE}'::regnamespace and c.relkind in('r','p','S')and(a.grantee<>c.relowner or(c.relkind<>'S'and not c.relrowsecurity)))then raise exception 'management_module_relation_acl';end if;
 for f in select p.* from pg_proc p where p.pronamespace='{MODULE}'::regnamespace or p.oid in(select to_regprocedure(s)from unnest({arr(APIS)})s)loop
  allowed:=case when f.oid in(to_regprocedure('{APIS[0]}'),to_regprocedure('{APIS[1]}'))then'authenticated'::regrole::oid when f.oid in(to_regprocedure('{APIS[2]}'),to_regprocedure('{APIS[3]}'))then'service_role'::regrole::oid else null end;
  for acl_row in select * from aclexplode(coalesce(f.proacl,acldefault('f',f.proowner)))loop if acl_row.grantee<>f.proowner and(acl_row.grantee is distinct from allowed or acl_row.privilege_type<>'EXECUTE'or acl_row.is_grantable)then raise exception 'management_module_function_acl';end if;end loop;
  if allowed is not null and not has_function_privilege(allowed,f.oid,'EXECUTE')then raise exception 'management_module_api_grant_missing';end if;
 end loop;
 if exists(select 1 from {MODULE}.deployments)or exists(select 1 from {MODULE}.proofs)or exists(select 1 from {MODULE}.commands)or exists(select 1 from {MODULE}.audit)then raise exception 'management_install_not_off_empty';end if;
end $access$;'''
 install += [access, f"do $after$ begin {unchanged(snapshot)}end $after$;", f"insert into {MODULE}.guarded_installation values(true,{sqljson(snapshot)},({catalogue()}),({SEQUENCE_VALUES}));", 'commit;']
 restore = ['-- ROOT REVIEW ONLY. Never-configured/never-used restoration, not used-data recovery.', 'begin;', "set local search_path='';set local lock_timeout='5s';set local statement_timeout='45s';", f"lock table {MODULE}.deployments,{MODULE}.proofs,{MODULE}.commands,{MODULE}.audit,{MODULE}.guarded_installation in access exclusive mode;"]
 restore += [f'''do $unused$ declare saved {MODULE}.guarded_installation%rowtype;f jsonb;begin
 if current_user<>'postgres'or session_user<>'postgres'then raise exception 'management_restore_operator';end if;
 select * into strict saved from {MODULE}.guarded_installation;
 if({catalogue()})is distinct from saved.installed_catalogue or({SEQUENCE_VALUES})is distinct from saved.sequence_values then raise exception 'management_installed_catalogue_changed';end if;
 if exists(select 1 from {MODULE}.deployments)or exists(select 1 from {MODULE}.proofs)or exists(select 1 from {MODULE}.commands)or exists(select 1 from {MODULE}.audit)then raise exception 'management_used_restore_refused';end if;
 if exists(select 1 from pg_proc p where p.pronamespace<>'{MODULE}'::regnamespace and p.oid not in(select to_regprocedure(s)from unnest({arr(APIS)})s)and p.prosrc~*{lit(runtime_pattern)})then raise exception 'management_external_runtime_dependency';end if;
 for f in select value from jsonb_array_elements(saved.baseline->'functions')loop if(select to_jsonb(p)from pg_proc p where p.oid=to_regprocedure(f->>'signature'))is distinct from f->'metadata'then raise exception 'management_core_catalogue_drift';end if;end loop;
 {unchanged(snapshot)}
end $unused$;''']
 restore += ['drop function ' + p + ' restrict;' for p in reversed(APIS)]
 restore += [f"drop trigger management_audit_immutable on {MODULE}.audit;drop trigger management_command_immutable on {MODULE}.commands;drop trigger management_proof_immutable on {MODULE}.proofs;"]
 restore += [f'''do $drop_helpers$ declare f record;progress boolean;remaining integer;begin loop progress:=false;
 for f in select p.oid::regprocedure::text signature from pg_proc p where p.pronamespace='{MODULE}'::regnamespace loop begin execute 'drop function '||f.signature||' restrict';progress:=true;exception when dependent_objects_still_exist then null;end;end loop;
 select count(*)into remaining from pg_proc where pronamespace='{MODULE}'::regnamespace;exit when remaining=0;if not progress then raise exception 'management_unknown_helper_dependency';end if;end loop;end $drop_helpers$;''']
 restore += [f'drop table {MODULE}.{n} restrict;' for n in ['guarded_installation', 'audit', 'commands', 'proofs', 'deployments']]
 restore += [f'drop schema {MODULE} restrict;', f'do $restored$ begin {unchanged(snapshot)}end $restored$;', 'commit;']
 return '\n'.join(install) + '\n', '\n'.join(restore) + '\n'

if __name__ == '__main__':
 p=argparse.ArgumentParser();p.add_argument('--snapshot');p.add_argument('--body');p.add_argument('--outdir',default=str(ROOT));a=p.parse_args();out=Path(a.outdir);out.mkdir(parents=True,exist_ok=True);(out/'capture-management-issuer.sql').write_text(CAPTURE)
 if a.snapshot:
  if not a.body: p.error('--body required with --snapshot')
  snapshot=json.loads(Path(a.snapshot).read_text());snapshot=snapshot.get('snapshot',snapshot)
  source=Path(a.body).read_text();install,restore=compose(snapshot,source);(out/'install-off.guarded.sql.review-only').write_text(install);(out/'restore-unused.guarded.sql.review-only').write_text(restore)
  (out/'guard-manifest.json').write_text(json.dumps({'source_sha256':hashlib.sha256(source.encode()).hexdigest(),'install_sha256':hashlib.sha256(install.encode()).hexdigest(),'restore_sha256':hashlib.sha256(restore.encode()).hexdigest(),'production_applied':False},indent=2)+'\n')
