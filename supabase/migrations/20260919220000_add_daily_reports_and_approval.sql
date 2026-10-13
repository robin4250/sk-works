create table if not exists public.daily_reports (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  site_id uuid not null references public.sites(id) on delete cascade,
  report_date date not null,
  work_description text,
  status text not null default 'draft'
    check (status in ('draft', 'signed')),
  signer_name text,
  signature_json jsonb,
  signed_at timestamptz,
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(company_id, site_id, report_date)
);

create table if not exists public.daily_report_workers (
  report_id uuid not null references public.daily_reports(id) on delete cascade,
  worker_id uuid not null references public.workers(id) on delete cascade,
  overtime_hours numeric(7,2) not null default 0,
  early_hours numeric(7,2) not null default 0,
  night_hours numeric(7,2) not null default 0,
  allowance_amount integer not null default 0,
  allowance_label text,
  primary key(report_id, worker_id)
);

create table if not exists public.daily_report_edit_requests (
  id uuid primary key default gen_random_uuid(),
  report_id uuid not null references public.daily_reports(id) on delete cascade,
  company_id uuid not null references public.companies(id) on delete cascade,
  requested_by uuid not null references auth.users(id) on delete cascade,
  reason text,
  status text not null default 'pending'
    check (status in ('pending','approved','rejected','used')),
  approvals_required integer not null default 2
    check (approvals_required between 1 and 5),
  created_at timestamptz not null default now(),
  resolved_at timestamptz
);

create table if not exists public.daily_report_edit_approvals (
  request_id uuid not null references public.daily_report_edit_requests(id) on delete cascade,
  approver_user_id uuid not null references auth.users(id) on delete cascade,
  decision text not null check (decision in ('approve','reject')),
  decided_at timestamptz not null default now(),
  primary key(request_id, approver_user_id)
);

create index if not exists daily_reports_company_date_idx
  on public.daily_reports(company_id, report_date desc);

create index if not exists daily_report_edit_requests_company_status_idx
  on public.daily_report_edit_requests(company_id, status, created_at desc);

alter table public.daily_reports enable row level security;
alter table public.daily_report_workers enable row level security;
alter table public.daily_report_edit_requests enable row level security;
alter table public.daily_report_edit_approvals enable row level security;

drop policy if exists "company members can read daily reports" on public.daily_reports;
create policy "company members can read daily reports"
on public.daily_reports for select to authenticated
using (
  exists (
    select 1 from public.company_members cm
    where cm.company_id = daily_reports.company_id
      and cm.user_id = auth.uid()
  )
);

drop policy if exists "company members can read daily report workers" on public.daily_report_workers;
create policy "company members can read daily report workers"
on public.daily_report_workers for select to authenticated
using (
  exists (
    select 1
    from public.daily_reports dr
    join public.company_members cm on cm.company_id = dr.company_id
    where dr.id = daily_report_workers.report_id
      and cm.user_id = auth.uid()
  )
);

drop policy if exists "members can read own report edit requests" on public.daily_report_edit_requests;
create policy "members can read own report edit requests"
on public.daily_report_edit_requests for select to authenticated
using (
  requested_by = auth.uid()
  or exists (
    select 1 from public.company_members cm
    where cm.company_id = daily_report_edit_requests.company_id
      and cm.user_id = auth.uid()
      and cm.role::text in ('owner','admin','manager')
  )
);

drop policy if exists "members can read report edit approvals" on public.daily_report_edit_approvals;
create policy "members can read report edit approvals"
on public.daily_report_edit_approvals for select to authenticated
using (
  exists (
    select 1
    from public.daily_report_edit_requests req
    join public.company_members cm on cm.company_id = req.company_id
    where req.id = daily_report_edit_approvals.request_id
      and cm.user_id = auth.uid()
  )
);

revoke insert, update, delete on public.daily_reports from authenticated;
revoke insert, update, delete on public.daily_report_workers from authenticated;
revoke insert, update, delete on public.daily_report_edit_requests from authenticated;
revoke insert, update, delete on public.daily_report_edit_approvals from authenticated;

create or replace function public.daily_report_clocked_in_workers(
  p_date date
)
returns table(
  site_id uuid,
  site_name text,
  worker_id uuid,
  worker_name text
)
language sql
security definer
set search_path = public, pg_temp
as $$
  with membership as (
    select cm.company_id
    from public.company_members cm
    where cm.user_id = auth.uid()
    limit 1
  ),
  first_clock_in as (
    select distinct on (av.worker_id, av.site_id)
      av.worker_id,
      av.site_id,
      av.confirmed_at
    from public.attendance_verifications av
    join membership m on m.company_id = av.company_id
    where av.event_type = 'clock_in'
      and (av.confirmed_at at time zone 'Asia/Tokyo')::date = p_date
    order by av.worker_id, av.site_id, av.confirmed_at
  )
  select
    s.id,
    s.name,
    w.id,
    w.name
  from first_clock_in f
  join public.sites s on s.id = f.site_id
  join public.workers w on w.id = f.worker_id
  order by s.name, w.name;
$$;

create or replace function public.save_daily_report_draft(
  p_report_id uuid,
  p_site_id uuid,
  p_report_date date,
  p_work_description text,
  p_workers jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_company_id uuid;
  v_report_id uuid := p_report_id;
  v_report_status text;
  v_edit_request_id uuid;
  v_worker jsonb;
  v_worker_id uuid;
begin
  if v_user_id is null then
    raise exception 'authentication required';
  end if;

  select cm.company_id
  into v_company_id
  from public.company_members cm
  where cm.user_id = v_user_id
  limit 1;

  if v_company_id is null then
    raise exception 'company membership not found';
  end if;

  if not exists (
    select 1 from public.sites s
    where s.id = p_site_id
      and s.company_id = v_company_id
  ) then
    raise exception 'site does not belong to company';
  end if;

  if v_report_id is not null then
    select dr.status
    into v_report_status
    from public.daily_reports dr
    where dr.id = v_report_id
      and dr.company_id = v_company_id
    for update;

    if not found then
      raise exception 'daily report not found';
    end if;

    if v_report_status = 'signed' then
      select req.id
      into v_edit_request_id
      from public.daily_report_edit_requests req
      where req.report_id = v_report_id
        and req.requested_by = v_user_id
        and req.status = 'approved'
      order by req.created_at desc
      limit 1
      for update;

      if v_edit_request_id is null then
        raise exception 'signed report requires approved edit request';
      end if;

      update public.daily_report_edit_requests
      set status = 'used',
          resolved_at = coalesce(resolved_at, now())
      where id = v_edit_request_id;
    end if;

    update public.daily_reports
    set site_id = p_site_id,
        report_date = p_report_date,
        work_description = p_work_description,
        status = 'draft',
        signer_name = null,
        signature_json = null,
        signed_at = null,
        updated_by = v_user_id,
        updated_at = now()
    where id = v_report_id;
  else
    insert into public.daily_reports(
      company_id,
      site_id,
      report_date,
      work_description,
      status,
      created_by,
      updated_by
    )
    values(
      v_company_id,
      p_site_id,
      p_report_date,
      p_work_description,
      'draft',
      v_user_id,
      v_user_id
    )
    on conflict(company_id, site_id, report_date) do update
    set work_description = excluded.work_description,
        updated_by = v_user_id,
        updated_at = now()
    returning id, status into v_report_id, v_report_status;

    if v_report_status = 'signed' then
      raise exception 'signed report requires edit approval';
    end if;
  end if;

  delete from public.daily_report_workers
  where report_id = v_report_id;

  for v_worker in
    select value from jsonb_array_elements(coalesce(p_workers, '[]'::jsonb))
  loop
    v_worker_id := (v_worker ->> 'worker_id')::uuid;

    if not exists (
      select 1 from public.workers w
      where w.id = v_worker_id
        and w.company_id = v_company_id
    ) then
      raise exception 'worker does not belong to company';
    end if;

    insert into public.daily_report_workers(
      report_id,
      worker_id,
      overtime_hours,
      early_hours,
      night_hours,
      allowance_amount,
      allowance_label
    )
    values(
      v_report_id,
      v_worker_id,
      greatest(coalesce((v_worker ->> 'overtime_hours')::numeric, 0), 0),
      greatest(coalesce((v_worker ->> 'early_hours')::numeric, 0), 0),
      greatest(coalesce((v_worker ->> 'night_hours')::numeric, 0), 0),
      greatest(coalesce((v_worker ->> 'allowance_amount')::integer, 0), 0),
      nullif(trim(coalesce(v_worker ->> 'allowance_label', '')), '')
    );
  end loop;

  return v_report_id;
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
set search_path = public, private, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_company_id uuid;
  v_site_id uuid;
  v_date date;
  v_detail record;
  v_entry_id uuid;
begin
  if v_user_id is null then
    raise exception 'authentication required';
  end if;

  select dr.company_id, dr.site_id, dr.report_date
  into v_company_id, v_site_id, v_date
  from public.daily_reports dr
  join public.company_members cm
    on cm.company_id = dr.company_id
   and cm.user_id = v_user_id
  where dr.id = p_report_id
  for update;

  if v_company_id is null then
    raise exception 'daily report not found';
  end if;

  if nullif(trim(coalesce(p_signer_name, '')), '') is null then
    raise exception 'signer name is required';
  end if;

  if p_signature_json is null or p_signature_json = '[]'::jsonb then
    raise exception 'signature is required';
  end if;

  update public.daily_reports
  set status = 'signed',
      signer_name = trim(p_signer_name),
      signature_json = p_signature_json,
      signed_at = now(),
      updated_by = v_user_id,
      updated_at = now()
  where id = p_report_id;

  for v_detail in
    select *
    from public.daily_report_workers
    where report_id = p_report_id
  loop
    select ae.id
    into v_entry_id
    from public.attendance_entries ae
    where ae.company_id = v_company_id
      and ae.worker_id = v_detail.worker_id
      and ae.site_id = v_site_id
      and ae.work_date = v_date
    order by ae.created_at
    limit 1;

    if v_entry_id is null then
      insert into public.attendance_entries(
        company_id,
        work_date,
        worker_id,
        site_id,
        base_man_days,
        overtime_hours,
        early_hours,
        night_hours,
        allowance_amount,
        notes,
        created_by,
        updated_by
      )
      values(
        v_company_id,
        v_date,
        v_detail.worker_id,
        v_site_id,
        1,
        v_detail.overtime_hours,
        v_detail.early_hours,
        v_detail.night_hours,
        v_detail.allowance_amount,
        v_detail.allowance_label,
        v_user_id,
        v_user_id
      );
    else
      update public.attendance_entries
      set base_man_days = 1,
          overtime_hours = v_detail.overtime_hours,
          early_hours = v_detail.early_hours,
          night_hours = v_detail.night_hours,
          allowance_amount = v_detail.allowance_amount,
          notes = v_detail.allowance_label,
          updated_by = v_user_id,
          updated_at = now()
      where id = v_entry_id;
    end if;

    v_entry_id := null;
  end loop;
end;
$$;

create or replace function public.request_daily_report_edit(
  p_report_id uuid,
  p_reason text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_company_id uuid;
  v_request_id uuid;
  v_approver record;
begin
  if v_user_id is null then
    raise exception 'authentication required';
  end if;

  select dr.company_id
  into v_company_id
  from public.daily_reports dr
  join public.company_members cm
    on cm.company_id = dr.company_id
   and cm.user_id = v_user_id
  where dr.id = p_report_id
    and dr.status = 'signed';

  if v_company_id is null then
    raise exception 'signed daily report not found';
  end if;

  insert into public.daily_report_edit_requests(
    report_id,
    company_id,
    requested_by,
    reason
  )
  values(
    p_report_id,
    v_company_id,
    v_user_id,
    nullif(trim(coalesce(p_reason, '')), '')
  )
  returning id into v_request_id;

  for v_approver in
    select cm.user_id
    from public.company_members cm
    where cm.company_id = v_company_id
      and cm.user_id <> v_user_id
      and cm.role::text in ('admin','manager')
  loop
    perform private.enqueue_notification(
      v_company_id,
      v_approver.user_id,
      'approval',
      '日報の修正承認',
      '確定済み日報の修正申請があります。',
      'daily_report_edit_request',
      v_request_id
    );
  end loop;

  return v_request_id;
end;
$$;

create or replace function public.decide_daily_report_edit(
  p_request_id uuid,
  p_decision text
)
returns text
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_company_id uuid;
  v_requested_by uuid;
  v_required integer;
  v_approve_count integer;
  v_status text;
begin
  if v_user_id is null then
    raise exception 'authentication required';
  end if;

  if p_decision not in ('approve','reject') then
    raise exception 'invalid decision';
  end if;

  select req.company_id, req.requested_by, req.approvals_required, req.status
  into v_company_id, v_requested_by, v_required, v_status
  from public.daily_report_edit_requests req
  where req.id = p_request_id
  for update;

  if v_company_id is null or v_status <> 'pending' then
    raise exception 'pending request not found';
  end if;

  if not exists (
    select 1 from public.company_members cm
    where cm.company_id = v_company_id
      and cm.user_id = v_user_id
      and cm.role::text in ('admin','manager')
  ) then
    raise exception 'approval permission required';
  end if;

  if v_requested_by = v_user_id then
    raise exception 'requester cannot approve own request';
  end if;

  insert into public.daily_report_edit_approvals(
    request_id,
    approver_user_id,
    decision
  )
  values(
    p_request_id,
    v_user_id,
    p_decision
  )
  on conflict(request_id, approver_user_id) do update
  set decision = excluded.decision,
      decided_at = now();

  if p_decision = 'reject' then
    update public.daily_report_edit_requests
    set status = 'rejected',
        resolved_at = now()
    where id = p_request_id;

    perform private.enqueue_notification(
      v_company_id,
      v_requested_by,
      'warning',
      '日報修正申請が却下されました',
      '確定済み日報の修正申請が却下されました。',
      'daily_report_edit_request',
      p_request_id
    );
    return 'rejected';
  end if;

  select count(*)
  into v_approve_count
  from public.daily_report_edit_approvals
  where request_id = p_request_id
    and decision = 'approve';

  if v_approve_count >= v_required then
    update public.daily_report_edit_requests
    set status = 'approved',
        resolved_at = now()
    where id = p_request_id;

    perform private.enqueue_notification(
      v_company_id,
      v_requested_by,
      'approval',
      '日報を編集できます',
      '2名の承認が完了しました。日報を開いて編集してください。',
      'daily_report_edit_request',
      p_request_id
    );
    return 'approved';
  end if;

  return 'pending';
end;
$$;

revoke execute on function public.daily_report_clocked_in_workers(date) from public, anon;
revoke execute on function public.save_daily_report_draft(uuid, uuid, date, text, jsonb) from public, anon;
revoke execute on function public.sign_daily_report(uuid, text, jsonb) from public, anon;
revoke execute on function public.request_daily_report_edit(uuid, text) from public, anon;
revoke execute on function public.decide_daily_report_edit(uuid, text) from public, anon;

grant execute on function public.daily_report_clocked_in_workers(date) to authenticated;
grant execute on function public.save_daily_report_draft(uuid, uuid, date, text, jsonb) to authenticated;
grant execute on function public.sign_daily_report(uuid, text, jsonb) to authenticated;
grant execute on function public.request_daily_report_edit(uuid, text) to authenticated;
grant execute on function public.decide_daily_report_edit(uuid, text) to authenticated;
