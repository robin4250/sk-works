begin;
set local lock_timeout='5s';
-- Fail closed on concurrent/drifted authorization definitions. Table locks keep
-- a policy edit from racing the checked snapshot; no data or identities change.
lock table public.worker_personnel_profiles,public.worker_family_members in access exclusive mode;
do $guard$
begin
 if (select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace
     where n.nspname='public' and c.relname in ('worker_personnel_profiles','worker_family_members')
       and c.relkind='r' and c.relrowsecurity and not c.relforcerowsecurity)=2
 and (select count(*) from pg_policies p where p.schemaname='public'
   and p.tablename in ('worker_personnel_profiles','worker_family_members'))=2
 and exists(select 1 from pg_policies p where p.schemaname='public'
   and p.tablename='worker_personnel_profiles' and p.policyname='personnel profile read'
   and p.permissive='PERMISSIVE' and p.cmd='SELECT' and p.roles=ARRAY['public']::name[]
   and md5(p.qual)='1f1384d90020f684fa997e8fa582e8a2' and p.with_check is null)
 and exists(select 1 from pg_policies p where p.schemaname='public'
   and p.tablename='worker_family_members' and p.policyname='worker family members read'
   and p.permissive='PERMISSIVE' and p.cmd='SELECT' and p.roles=ARRAY['public']::name[]
   and md5(p.qual)='ebbb5d4863aefdbb313b26d24cf61a6d' and p.with_check is null)
 and exists(select 1 from pg_proc p where p.oid=to_regprocedure('private.personnel_view_allowed(uuid)')
   and md5(p.prosrc)='e884314c5119e72345e7614802432b15'
   and pg_get_userbyid(p.proowner)='postgres' and not p.prosecdef
   and p.provolatile='s' and p.prokind='f' and not p.proretset
   and p.prorettype='boolean'::regtype
   and p.prolang=(select oid from pg_language where lanname='sql')
   and p.proconfig=ARRAY['search_path=""']::text[]
   and p.proacl=ARRAY['postgres=X/postgres','authenticated=X/postgres']::aclitem[])
 then return;
 end if;
 raise exception 'personnel_permission_baseline_drift: capture and review a fresh protected authorization snapshot before applying' using errcode='55000';
end
$guard$;
-- Match the existing canonical employee-personnel read RPC, including its
-- intentional read-only viewer scope, while retaining employees' own records.
-- No INSERT/UPDATE/DELETE grants, helpers, business rows or payroll are changed.
drop policy "personnel profile read" on public.worker_personnel_profiles;
create policy "personnel profile read" on public.worker_personnel_profiles
for select to authenticated using (
  private.account_access_allowed()
  and exists (
    select 1 from public.workers w
    where w.id=worker_personnel_profiles.worker_id
      and w.company_id=worker_personnel_profiles.company_id
      and (w.user_id=auth.uid()
        or (private.personnel_view_allowed(worker_personnel_profiles.company_id)
          and (w.status::text='active' or exists (
            select 1 from public.company_members m
            where m.company_id=worker_personnel_profiles.company_id
              and m.user_id=auth.uid()
              and m.role::text in ('owner','admin','manager')
          ))))
  )
);
drop policy "worker family members read" on public.worker_family_members;
create policy "worker family members read" on public.worker_family_members
for select to authenticated using (
  private.account_access_allowed()
  and exists (
    select 1 from public.workers w
    where w.id=worker_family_members.worker_id
      and w.company_id=worker_family_members.company_id
      and (w.user_id=auth.uid()
        or (private.personnel_view_allowed(worker_family_members.company_id)
          and (w.status::text='active' or exists (
            select 1 from public.company_members m
            where m.company_id=worker_family_members.company_id
              and m.user_id=auth.uid()
              and m.role::text in ('owner','admin','manager')
          ))))
  )
);
commit;
