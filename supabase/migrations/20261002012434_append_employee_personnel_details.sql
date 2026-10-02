create or replace function public.append_employee_personnel_details(
  p_delivery_id uuid,
  p_worker_ids uuid[]
)
returns void
language plpgsql
security definer
set search_path=''
as $$
declare
  v_user uuid := auth.uid();
  v_company uuid;
  v_name text;
  w record;
  e record;
  v_phone text;
  v_emergency_phone text;
begin
  select m.company_id, c.name into v_company, v_name
  from public.company_members m
  join public.companies c on c.id=m.company_id
  where m.user_id=v_user and m.role::text in ('owner','admin')
  limit 1;

  if v_company is null then
    raise exception '会社の管理者だけが操作できます';
  end if;

  if not exists(
    select 1
    from private.document_deliveries d
    where d.id=p_delivery_id
      and d.sender_company_id=v_company
      and d.sent_by=v_user
  ) then
    raise exception '送信データを確認できません';
  end if;

  for w in
    select *
    from public.workers
    where company_id=v_company
      and id=any(p_worker_ids)
      and status='active'
  loop
    select *
    into e
    from public.employee_registration_invites eri
    where eri.worker_id=w.id
      and eri.company_id=v_company
      and eri.status='approved'
    order by eri.approved_at desc nulls last, eri.created_at desc
    limit 1;

    v_phone := coalesce(w.phone,'');
    if v_phone like '+81%' then
      v_phone := '0' || regexp_replace(substr(v_phone,4), '^[-[:space:]]+', '');
    end if;

    v_emergency_phone := coalesce(e.emergency_phone,'');
    if v_emergency_phone like '+81%' then
      v_emergency_phone :=
        '0' || regexp_replace(substr(v_emergency_phone,4), '^[-[:space:]]+', '');
    end if;

    insert into private.company_data_delivery_items(
      delivery_id,
      payload_kind,
      payload,
      company_path
    )
    values(
      p_delivery_id,
      'personnel_detail',
      jsonb_build_object(
        'source_worker_id',w.id,
        'name',w.name,
        'kind',case
          when w.affiliation::text='partner_company' then 'partnerWorker'
          else 'employee'
        end,
        'blood_type',coalesce(e.blood_type,''),
        'role',coalesce(w.role,''),
        'phone',v_phone,
        'address',coalesce(e.address,''),
        'emergency_name',coalesce(e.emergency_name,''),
        'emergency_relation',coalesce(e.emergency_relation,''),
        'emergency_phone',v_emergency_phone,
        'emergency_address',coalesce(e.emergency_address,'')
      ),
      jsonb_build_array(v_name)
    );
  end loop;
end
$$;

revoke all on function public.append_employee_personnel_details(uuid,uuid[])
from public,anon;
grant execute on function public.append_employee_personnel_details(uuid,uuid[])
to authenticated;
