create or replace function private.employee_personnel_rows()
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  v_user uuid:=auth.uid();
  v_company uuid;
begin
  select cm.company_id into v_company
  from public.company_members cm
  where cm.user_id=v_user
    and cm.role::text in ('owner','admin','manager')
  limit 1;

  if v_company is null then
    raise exception '社員情報の閲覧権限がありません';
  end if;

  return coalesce(
    (
      select jsonb_agg(
        jsonb_build_object(
          'worker_id',w.id,
          'name',w.name,
          'kind',case
            when w.affiliation::text='partner_company' then 'partnerWorker'
            else 'employee'
          end,
          'blood_type',coalesce(eri.blood_type,''),
          'role',coalesce(w.role,''),
          'phone',coalesce(w.phone,eri.phone_e164,''),
          'address',coalesce(eri.address,''),
          'emergency_name',coalesce(eri.emergency_name,''),
          'emergency_relation',coalesce(eri.emergency_relation,''),
          'emergency_phone',coalesce(eri.emergency_phone,''),
          'emergency_address',coalesce(eri.emergency_address,''),
          'created_at',w.created_at,
          'updated_at',w.updated_at
        )
        order by w.name
      )
      from public.workers w
      left join lateral (
        select eri.*
        from public.employee_registration_invites eri
        where eri.worker_id=w.id
          and eri.company_id=w.company_id
          and eri.status='approved'
        order by eri.approved_at desc nulls last, eri.created_at desc
        limit 1
      ) eri on true
      where w.company_id=v_company
        and w.status='active'
    ),
    '[]'::jsonb
  );
end
$$;

create or replace function public.employee_personnel_rows()
returns jsonb
language sql
set search_path=''
as $$ select private.employee_personnel_rows() $$;

revoke all on function public.employee_personnel_rows() from public,anon;
grant execute on function public.employee_personnel_rows() to authenticated;
