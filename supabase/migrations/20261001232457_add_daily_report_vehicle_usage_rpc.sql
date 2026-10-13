create or replace function private.save_daily_report_vehicle_usage(
  p_report_id uuid,
  p_worker_id uuid,
  p_vehicle_id uuid,
  p_route_assignment_id uuid,
  p_odometer_km numeric
)
returns void
language plpgsql
security definer
set search_path=''
as $$
declare
  v_user uuid:=auth.uid();
  v_company uuid;
  v_status text;
  v_current numeric;
begin
  if v_user is null then raise exception 'ログインが必要です'; end if;

  select m.company_id into v_company
  from public.company_members m
  where m.user_id=v_user
  limit 1;
  if v_company is null then raise exception '会社への所属が必要です'; end if;

  select d.status into v_status
  from public.daily_reports d
  where d.id=p_report_id and d.company_id=v_company
  limit 1;
  if v_status is null then raise exception '日報を確認できません'; end if;
  if v_status<>'draft' then raise exception '確定済み日報は直接変更できません'; end if;

  if not exists(
    select 1 from public.daily_report_workers w
    where w.report_id=p_report_id and w.worker_id=p_worker_id
  ) then
    raise exception '日報の社員情報を確認できません';
  end if;

  if p_vehicle_id is not null and not exists(
    select 1 from public.vehicles v
    where v.id=p_vehicle_id and v.company_id=v_company and v.is_active=true
  ) then
    raise exception '車両を確認できません';
  end if;

  if p_route_assignment_id is not null and not exists(
    select 1 from public.route_assignments r
    where r.id=p_route_assignment_id
      and r.company_id=v_company
      and r.is_active=true
  ) then
    raise exception 'ルートを確認できません';
  end if;

  if p_odometer_km is not null and p_odometer_km<0 then
    raise exception '走行距離を確認してください';
  end if;

  if p_vehicle_id is not null and p_odometer_km is not null then
    select v.odometer_km into v_current
    from public.vehicles v
    where v.id=p_vehicle_id and v.company_id=v_company
    for update;

    if p_odometer_km<v_current then
      raise exception '現在の走行距離より小さい数値は登録できません';
    end if;

    update public.vehicles
    set odometer_km=p_odometer_km,
        updated_by=v_user,
        updated_at=now()
    where id=p_vehicle_id and company_id=v_company;
  end if;

  update public.daily_report_workers
  set vehicle_id=p_vehicle_id,
      route_assignment_id=p_route_assignment_id,
      odometer_km=p_odometer_km
  where report_id=p_report_id and worker_id=p_worker_id;
end
$$;

create or replace function public.save_daily_report_vehicle_usage(
  p_report_id uuid,
  p_worker_id uuid,
  p_vehicle_id uuid,
  p_route_assignment_id uuid,
  p_odometer_km numeric
)
returns void
language sql
set search_path=''
as $$
  select private.save_daily_report_vehicle_usage(
    p_report_id,p_worker_id,p_vehicle_id,p_route_assignment_id,p_odometer_km
  )
$$;

revoke all on function public.save_daily_report_vehicle_usage(
  uuid,uuid,uuid,uuid,numeric
) from public,anon;
grant execute on function public.save_daily_report_vehicle_usage(
  uuid,uuid,uuid,uuid,numeric
) to authenticated;
