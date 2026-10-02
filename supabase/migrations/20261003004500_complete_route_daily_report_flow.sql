create unique index if not exists daily_reports_company_route_date_uq
on public.daily_reports(company_id,route_assignment_id,report_date)
where route_assignment_id is not null;

create or replace function public.daily_report_clocked_in_destinations(p_date date)
returns table(
  destination_kind text,
  destination_id uuid,
  destination_name text,
  site_id uuid,
  route_assignment_id uuid,
  worker_id uuid,
  worker_name text
)
language sql
security definer
set search_path to 'public','pg_temp'
as $$
  with membership as (
    select cm.company_id
    from public.company_members cm
    where cm.user_id=auth.uid()
    limit 1
  ),
  first_clock_in as (
    select distinct on (
      av.worker_id,
      coalesce(av.site_id,av.route_assignment_id)
    )
      av.worker_id,
      av.site_id,
      av.route_assignment_id,
      av.confirmed_at
    from public.attendance_verifications av
    join membership m on m.company_id=av.company_id
    where av.event_type='clock_in'
      and (av.confirmed_at at time zone 'Asia/Tokyo')::date=p_date
      and ((av.site_id is not null and av.route_assignment_id is null)
        or (av.site_id is null and av.route_assignment_id is not null))
    order by
      av.worker_id,
      coalesce(av.site_id,av.route_assignment_id),
      av.confirmed_at
  )
  select
    case when f.site_id is not null then 'site' else 'route' end,
    coalesce(f.site_id,f.route_assignment_id),
    coalesce(s.name,r.route_name,'未登録'),
    f.site_id,
    f.route_assignment_id,
    w.id,
    w.name
  from first_clock_in f
  join public.workers w on w.id=f.worker_id
  left join public.sites s on s.id=f.site_id
  left join public.route_assignments r on r.id=f.route_assignment_id
  order by 3,w.name;
$$;

revoke all on function public.daily_report_clocked_in_destinations(date) from public;
grant execute on function public.daily_report_clocked_in_destinations(date) to authenticated;

create or replace function public.save_daily_report_destination_draft(
  p_report_id uuid,
  p_site_id uuid,
  p_route_assignment_id uuid,
  p_report_date date,
  p_work_description text,
  p_workers jsonb
)
returns uuid
language plpgsql
security definer
set search_path to 'public','private','pg_temp'
as $$
declare
  v_user_id uuid:=auth.uid();
  v_company_id uuid;
  v_report_id uuid:=p_report_id;
  v_report_status text;
  v_edit_request_id uuid;
  v_worker jsonb;
  v_worker_id uuid;
begin
  if v_user_id is null then raise exception 'authentication required'; end if;

  select cm.company_id into v_company_id
  from public.company_members cm
  where cm.user_id=v_user_id
  limit 1;
  if v_company_id is null then raise exception 'company membership not found'; end if;

  if ((p_site_id is null) = (p_route_assignment_id is null)) then
    raise exception 'select exactly one workplace destination';
  end if;

  if p_site_id is not null and not exists(
    select 1 from public.sites s
    where s.id=p_site_id and s.company_id=v_company_id
  ) then
    raise exception 'site does not belong to company';
  end if;

  if p_route_assignment_id is not null and not exists(
    select 1 from public.route_assignments r
    where r.id=p_route_assignment_id
      and r.company_id=v_company_id
      and r.is_active=true
  ) then
    raise exception 'route does not belong to company';
  end if;

  if v_report_id is not null then
    select dr.status into v_report_status
    from public.daily_reports dr
    where dr.id=v_report_id and dr.company_id=v_company_id
    for update;
    if not found then raise exception 'daily report not found'; end if;

    if v_report_status='signed' then
      select req.id into v_edit_request_id
      from public.daily_report_edit_requests req
      where req.report_id=v_report_id
        and req.requested_by=v_user_id
        and req.status='approved'
      order by req.created_at desc
      limit 1
      for update;
      if v_edit_request_id is null then
        raise exception 'signed report requires approved edit request';
      end if;
      update public.daily_report_edit_requests
      set status='used',resolved_at=coalesce(resolved_at,now())
      where id=v_edit_request_id;
    end if;

    update public.daily_reports
    set site_id=p_site_id,
        route_assignment_id=p_route_assignment_id,
        report_date=p_report_date,
        work_description=p_work_description,
        status='draft',
        signer_name=null,
        signature_json=null,
        signed_at=null,
        representative_signature_json=null,
        representative_signer_name=null,
        supervisor_signature_json=null,
        supervisor_signer_name=null,
        updated_by=v_user_id,
        updated_at=now()
    where id=v_report_id;
  else
    select dr.id,dr.status
    into v_report_id,v_report_status
    from public.daily_reports dr
    where dr.company_id=v_company_id
      and dr.report_date=p_report_date
      and dr.site_id is not distinct from p_site_id
      and dr.route_assignment_id is not distinct from p_route_assignment_id
    limit 1
    for update;

    if v_report_id is not null then
      if v_report_status='signed' then
        raise exception 'signed report requires edit approval';
      end if;
      update public.daily_reports
      set work_description=p_work_description,
          updated_by=v_user_id,
          updated_at=now()
      where id=v_report_id;
    else
      insert into public.daily_reports(
        company_id,site_id,route_assignment_id,report_date,
        work_description,status,created_by,updated_by
      )
      values(
        v_company_id,p_site_id,p_route_assignment_id,p_report_date,
        p_work_description,'draft',v_user_id,v_user_id
      )
      returning id into v_report_id;
    end if;
  end if;

  delete from public.daily_report_workers where report_id=v_report_id;

  for v_worker in
    select value from jsonb_array_elements(coalesce(p_workers,'[]'::jsonb))
  loop
    v_worker_id:=(v_worker->>'worker_id')::uuid;

    if nullif(v_worker->>'work_category','') is not null
       and v_worker->>'work_category' not in ('day','night','holiday','holiday_night')
    then
      raise exception 'invalid work category';
    end if;

    if (
      select count(distinct trim(v))
      from unnest(string_to_array(coalesce(v_worker->>'allowance_label',''),E'\n')) v
      where trim(v)<>''
    ) > 3 then
      raise exception 'maximum three daily allowances';
    end if;

    if not exists(
      select 1 from public.workers w
      where w.id=v_worker_id and w.company_id=v_company_id
    ) then
      raise exception 'worker does not belong to company';
    end if;

    insert into public.daily_report_workers(
      report_id,worker_id,overtime_hours,early_hours,night_hours,
      allowance_amount,allowance_label,work_category
    )
    values(
      v_report_id,v_worker_id,
      greatest(coalesce((v_worker->>'overtime_hours')::numeric,0),0),
      greatest(coalesce((v_worker->>'early_hours')::numeric,0),0),
      greatest(coalesce((v_worker->>'night_hours')::numeric,0),0),
      greatest(coalesce((v_worker->>'allowance_amount')::integer,0),0),
      nullif(trim(coalesce(v_worker->>'allowance_label','')),''),
      nullif(v_worker->>'work_category','')
    );
  end loop;

  return v_report_id;
end;
$$;

revoke all on function public.save_daily_report_destination_draft(uuid,uuid,uuid,date,text,jsonb) from public;
grant execute on function public.save_daily_report_destination_draft(uuid,uuid,uuid,date,text,jsonb) to authenticated;

create or replace function private.link_daily_report_attendance_evidence(p_report_id uuid)
returns integer
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_user uuid:=auth.uid();
  v_company uuid;
  v_site uuid;
  v_route uuid;
  v_date date;
  v_count integer;
  v_start timestamptz;
  v_end timestamptz;
begin
  select d.company_id,d.site_id,d.route_assignment_id,d.report_date
  into v_company,v_site,v_route,v_date
  from public.daily_reports d
  where d.id=p_report_id
  limit 1;

  if v_company is null then raise exception '日報を確認できません'; end if;
  if not exists(
    select 1 from public.company_members m
    where m.company_id=v_company and m.user_id=v_user
  ) then raise exception '日報を確認する権限がありません'; end if;

  v_start:=v_date::timestamp at time zone 'Asia/Tokyo';
  v_end:=(v_date+1)::timestamp at time zone 'Asia/Tokyo';

  update public.attendance_verifications a
  set daily_report_id=p_report_id
  where a.company_id=v_company
    and a.site_id is not distinct from v_site
    and a.route_assignment_id is not distinct from v_route
    and a.confirmed_at>=v_start
    and a.confirmed_at<v_end
    and a.photo_storage_path is not null
    and a.daily_report_id is null;

  get diagnostics v_count=row_count;
  return v_count;
end;
$$;

create or replace function public.sign_daily_report(
  p_report_id uuid,
  p_signer_name text,
  p_signature_json jsonb
)
returns void
language plpgsql
security definer
set search_path to 'public','private','pg_temp'
as $$
declare
  v_user_id uuid:=auth.uid();
  v_company_id uuid;
  v_site_id uuid;
  v_route_id uuid;
  v_date date;
  v_detail record;
  v_entry_id uuid;
begin
  if v_user_id is null then raise exception 'authentication required'; end if;

  select dr.company_id,dr.site_id,dr.route_assignment_id,dr.report_date
  into v_company_id,v_site_id,v_route_id,v_date
  from public.daily_reports dr
  join public.company_members cm
    on cm.company_id=dr.company_id and cm.user_id=v_user_id
  where dr.id=p_report_id
  for update;

  if v_company_id is null then raise exception 'daily report not found'; end if;
  if nullif(trim(coalesce(p_signer_name,'')),'') is null then
    raise exception 'signer name is required';
  end if;
  if p_signature_json is null or p_signature_json='[]'::jsonb then
    raise exception 'signature is required';
  end if;

  update public.daily_reports
  set status='signed',
      signer_name=trim(p_signer_name),
      signature_json=p_signature_json,
      signed_at=now(),
      updated_by=v_user_id,
      updated_at=now()
  where id=p_report_id;

  delete from public.attendance_entries ae
  where ae.source_report_id=p_report_id
    and (
      ae.site_id is distinct from v_site_id
      or ae.route_assignment_id is distinct from v_route_id
      or ae.work_date<>v_date
      or not exists(
        select 1 from public.daily_report_workers rw
        where rw.report_id=p_report_id and rw.worker_id=ae.worker_id
      )
    );

  for v_detail in
    select * from public.daily_report_workers
    where report_id=p_report_id
  loop
    select ae.id into v_entry_id
    from public.attendance_entries ae
    where ae.company_id=v_company_id
      and ae.worker_id=v_detail.worker_id
      and ae.site_id is not distinct from v_site_id
      and ae.route_assignment_id is not distinct from v_route_id
      and ae.work_date=v_date
      and ae.source_report_id=p_report_id
    order by ae.created_at
    limit 1;

    if v_entry_id is null then
      if exists(
        select 1 from public.attendance_entries ae
        where ae.company_id=v_company_id
          and ae.worker_id=v_detail.worker_id
          and ae.site_id is not distinct from v_site_id
          and ae.route_assignment_id is not distinct from v_route_id
          and ae.work_date=v_date
          and ae.source_report_id is distinct from p_report_id
      ) then
        raise exception '同じ日・勤務先の別の出勤記録があります。管理者が確認してください。';
      end if;

      insert into public.attendance_entries(
        company_id,work_date,worker_id,site_id,route_assignment_id,
        base_man_days,overtime_hours,early_hours,night_hours,
        allowance_amount,notes,work_category,allowance_names,
        source_report_id,created_by,updated_by
      )
      values(
        v_company_id,v_date,v_detail.worker_id,v_site_id,v_route_id,
        1,v_detail.overtime_hours,v_detail.early_hours,v_detail.night_hours,
        v_detail.allowance_amount,v_detail.allowance_label,v_detail.work_category,
        array(
          select distinct trim(v)
          from unnest(string_to_array(coalesce(v_detail.allowance_label,''),E'\n')) v
          where trim(v)<>''
        ),
        p_report_id,v_user_id,v_user_id
      );
    else
      update public.attendance_entries
      set base_man_days=1,
          overtime_hours=v_detail.overtime_hours,
          early_hours=v_detail.early_hours,
          night_hours=v_detail.night_hours,
          allowance_amount=v_detail.allowance_amount,
          notes=v_detail.allowance_label,
          work_category=v_detail.work_category,
          allowance_names=array(
            select distinct trim(v)
            from unnest(string_to_array(coalesce(v_detail.allowance_label,''),E'\n')) v
            where trim(v)<>''
          ),
          source_report_id=p_report_id,
          updated_by=v_user_id,
          updated_at=now()
      where id=v_entry_id and source_report_id=p_report_id;
    end if;

    v_entry_id:=null;
  end loop;
end;
$$;
