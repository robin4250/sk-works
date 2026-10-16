begin;
set local lock_timeout='5s';
-- Review-only production candidate. Coordinate all function-DDL writers and
-- obtain the protected-backup/recovery review and explicit approval first.
select pg_advisory_xact_lock(hashtextextended('sko.personnel-write-permission-guard',0));
do $guard$
begin
 if exists(select 1 from pg_proc p where p.oid=to_regprocedure('private.can_edit_worker_personnel(uuid)')
   and md5(p.prosrc)='ead531bcf8b745788cd01371ac405014'
   and pg_get_userbyid(p.proowner)='postgres' and p.proacl is null
   and p.prosecdef and p.provolatile='s' and p.prokind='f' and not p.proretset
   and p.prorettype='boolean'::regtype and p.proconfig=ARRAY['search_path=""']::text[]
   and p.prolang=(select oid from pg_language where lanname='sql'))
 and exists(select 1 from pg_proc p where p.oid=to_regprocedure('public.save_worker_personnel_profile(uuid,jsonb)')
   and md5(p.prosrc)='c11956bf0845ab725312928c2422a7ab'
   and pg_get_userbyid(p.proowner)='postgres' and p.prosecdef
   and p.proacl=ARRAY['postgres=X/postgres','authenticated=X/postgres','service_role=X/postgres']::aclitem[]
   and p.provolatile='v' and p.prorettype='jsonb'::regtype
   and p.proconfig=ARRAY['search_path=""']::text[])
 then return;
 end if;
 raise exception 'personnel_write_baseline_drift: capture and review a fresh protected authorization snapshot' using errcode='55000';
end
$guard$;
-- The only replaced object. Existing save, payload application, approvals and
-- notifications are untouched. In particular, approval assignees keep their
-- separate is_worker_personnel_approver path, which does not call this helper.
create or replace function private.can_edit_worker_personnel(p_worker_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select private.account_access_allowed() is true and exists(
   select 1 from public.workers w
   where w.id=p_worker_id
     and (w.user_id=auth.uid() or exists(
       select 1 from public.company_members cm
       where cm.company_id=w.company_id and cm.user_id=auth.uid()
         and cm.role::text in ('owner','admin','manager')
         and private.has_company_feature(w.company_id,'can_manage_people') is true
     ))
 );
$$;
commit;
