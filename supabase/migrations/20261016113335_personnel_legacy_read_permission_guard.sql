begin;
set local lock_timeout='5s';
-- Cooperating migration owners serialize this exact authorization change.
-- Production review must also exclude other function DDL writers; a catalog
-- snapshot guard is not a universal lock against arbitrary external DDL.
select pg_advisory_xact_lock(hashtextextended('sko.personnel-legacy-read-permission-guard',0));
do $guard$
begin
 if exists(select 1 from pg_proc p where p.oid=to_regprocedure('private.employee_personnel_rows()')
   and md5(p.prosrc)='3dd173b3ba0768718bbc6f326ea1fb18'
   and pg_get_userbyid(p.proowner)='postgres' and p.proacl is null
   and p.prosecdef and p.provolatile='s' and p.prokind='f' and not p.proretset
   and p.prorettype='jsonb'::regtype and p.proconfig=ARRAY['search_path=""']::text[]
   and p.prolang=(select oid from pg_language where lanname='plpgsql'))
 and exists(select 1 from pg_proc p where p.oid=to_regprocedure('public.employee_personnel_rows()')
   and md5(p.prosrc)='1c119e25281012769df17297a56b1fe7'
   and pg_get_userbyid(p.proowner)='postgres' and not p.prosecdef
   and p.proacl=ARRAY['postgres=X/postgres','authenticated=X/postgres','service_role=X/postgres']::aclitem[]
   and p.provolatile='v' and p.prorettype='jsonb'::regtype
   and p.proconfig=ARRAY['search_path=""']::text[]
   and p.prolang=(select oid from pg_language where lanname='sql'))
 then return;
 end if;
 raise exception 'personnel_legacy_rpc_baseline_drift: capture and review a fresh protected authorization snapshot' using errcode='55000';
end
$guard$;
-- Only the authorization condition and denial SQLSTATE change. CREATE OR REPLACE
-- preserves the function owner/ACL; the public API and JSON payload are untouched.
CREATE OR REPLACE FUNCTION private.employee_personnel_rows()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_user uuid:=auth.uid();
  v_company uuid;
begin
  select cm.company_id into v_company
  from public.company_members cm
  where cm.user_id=v_user
    and cm.role::text in ('owner','admin','manager')
  limit 1;
  if v_company is null
     or not private.account_access_allowed()
     or not private.has_company_feature(v_company,'can_manage_people') then
    raise exception '社員情報の閲覧権限がありません' using errcode='42501';
  end if;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'worker_id',w.id,'name',w.name,
      'kind',case when w.affiliation::text='partner_company'
        then 'partnerWorker' else 'employee' end,
      'blood_type',coalesce(p.blood_type,''),
      'role',coalesce(w.role,''),
    'employee_number',coalesce(w.employee_number,''),
    'department',coalesce(w.department,''),
    'hire_date',coalesce(w.hire_date::text,''),
      'phone',coalesce(w.phone,''),
      'address',coalesce(p.address,''),
      'emergency_name',coalesce(p.emergency_name,''),
      'emergency_relation',coalesce(p.emergency_relation,''),
      'emergency_phone',coalesce(p.emergency_phone,''),
      'emergency_address',coalesce(p.emergency_address,''),
      'family_composition',coalesce(p.family_composition,''),
      'family_members',coalesce((
        select jsonb_agg(jsonb_build_object(
          'id',fm.id,'name',fm.name,'relation',fm.relation,
          'birth_date',fm.birth_date,'is_dependent',fm.is_dependent
        ) order by fm.birth_date nulls last,fm.name)
        from public.worker_family_members fm
        where fm.worker_id=w.id and fm.company_id=w.company_id
      ),'[]'::jsonb),
      'created_at',w.created_at,
      'updated_at',greatest(w.updated_at,coalesce(p.updated_at,w.updated_at))
    ) order by w.name)
    from public.workers w
    left join public.worker_personnel_profiles p
      on p.worker_id=w.id and p.company_id=w.company_id
    where w.company_id=v_company and w.status='active'
  ),'[]'::jsonb);
end
$function$
;
commit;
