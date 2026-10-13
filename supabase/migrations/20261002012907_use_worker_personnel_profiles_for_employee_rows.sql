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
          'blood_type',coalesce(p.blood_type,''),
          'role',coalesce(w.role,''),
          'phone',coalesce(w.phone,''),
          'address',coalesce(p.address,''),
          'emergency_name',coalesce(p.emergency_name,''),
          'emergency_relation',coalesce(p.emergency_relation,''),
          'emergency_phone',coalesce(p.emergency_phone,''),
          'emergency_address',coalesce(p.emergency_address,''),
          'created_at',w.created_at,
          'updated_at',greatest(w.updated_at,coalesce(p.updated_at,w.updated_at))
        )
        order by w.name
      )
      from public.workers w
      left join public.worker_personnel_profiles p
        on p.worker_id=w.id and p.company_id=w.company_id
      where w.company_id=v_company
        and w.status='active'
    ),
    '[]'::jsonb
  );
end
$$;

create or replace function public.current_worker_personnel_profile()
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  v_worker uuid;
begin
  select w.id into v_worker
  from public.workers w
  where w.user_id=auth.uid()
  limit 1;

  if v_worker is null then
    return null;
  end if;

  return private.worker_personnel_payload(v_worker)
    || jsonb_build_object('worker_id',v_worker);
end
$$;

revoke all on function public.current_worker_personnel_profile()
from public,anon;
grant execute on function public.current_worker_personnel_profile()
to authenticated;
