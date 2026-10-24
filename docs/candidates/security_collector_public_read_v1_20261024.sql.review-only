-- REVIEW ONLY. Depends on the separately reviewed collector/proof registration.
-- One invoker RPC, no tables, gates, seeds, schema grants or private source changes.
begin;
set local lock_timeout='3s';
set local statement_timeout='30s';
set local search_path='';
do $collector_public_before$
declare p record;
begin
 if current_user<>'postgres' or not has_schema_privilege('authenticated','public','USAGE')
  or not has_schema_privilege('authenticated','private','USAGE') then
  raise sqlstate '55000' using message='collector_public_read_prerequisite_missing';
 end if;
 if exists(select 1 from pg_proc f join pg_namespace n on n.oid=f.pronamespace
  where n.nspname='public' and f.proname='master_security_collector_events') then
  raise sqlstate '55000' using message='collector_public_read_already_exists';
 end if;
 select f.*,l.lanname into p from pg_proc f join pg_language l on l.oid=f.prolang
  where f.oid=to_regprocedure('private.read_security_collector_events(text)');
 if not found or pg_get_userbyid(p.proowner)<>'postgres' or not p.prosecdef
  or p.provolatile<>'v' or p.lanname<>'plpgsql' or p.proretset
  or p.prorettype<>'jsonb'::regtype or p.proconfig is distinct from array['search_path=""']
  or md5(p.prosrc)<>'a62cc46b5c9fbcee3e38e9699e44bd00'
  or not has_function_privilege('authenticated',p.oid,'EXECUTE')
  or has_function_privilege('anon',p.oid,'EXECUTE')
  or has_function_privilege('service_role',p.oid,'EXECUTE') then
  raise sqlstate '55000' using message='collector_private_read_contract_differs';
 end if;
 if exists(select 1 from aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
  where a.grantee<>p.proowner and not(a.grantee='authenticated'::regrole
   and a.privilege_type='EXECUTE' and not a.is_grantable)) then
  raise sqlstate '55000' using message='collector_private_read_acl_differs';
 end if;
end $collector_public_before$;

create function public.master_security_collector_events(p_proof text)
returns jsonb language plpgsql volatile security invoker set search_path='' as $$
begin
 -- VOLATILE makes POST read/write. GET/HEAD are also explicitly refused before
 -- delegating, rather than relying on a later read-only transaction error.
 if current_setting('request.method',true) is distinct from 'POST' then
  raise sqlstate 'PT405' using message='post_required';
 end if;
 return private.read_security_collector_events(p_proof);
end $$;
revoke all on function public.master_security_collector_events(text)
 from public,anon,authenticated,service_role,sko_security_collector_ingest;
grant execute on function public.master_security_collector_events(text) to authenticated;

do $collector_public_after$
declare p record;
begin
 select f.*,l.lanname into p from pg_proc f join pg_language l on l.oid=f.prolang
  where f.oid='public.master_security_collector_events(text)'::regprocedure;
 if pg_get_userbyid(p.proowner)<>'postgres' or p.prosecdef or p.provolatile<>'v'
  or md5(p.prosrc)<>'974d888a3eedae6c4de80338abcfa754'
  or p.lanname<>'plpgsql' or p.proretset or p.prorettype<>'jsonb'::regtype
  or p.proargnames is distinct from array['p_proof']::text[]
  or p.proconfig is distinct from array['search_path=""']
  or not has_function_privilege('authenticated',p.oid,'EXECUTE')
  or has_function_privilege('anon',p.oid,'EXECUTE')
  or has_function_privilege('service_role',p.oid,'EXECUTE') then
  raise sqlstate '55000' using message='collector_public_read_contract_differs';
 end if;
 if exists(select 1 from aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
  where a.grantee<>p.proowner and not(a.grantee='authenticated'::regrole
   and a.privilege_type='EXECUTE' and not a.is_grantable)) then
  raise sqlstate '55000' using message='collector_public_read_acl_differs';
 end if;
end $collector_public_after$;
commit;
