alter table public.worker_payroll_settings
  add column if not exists paid_leave_granted_days numeric(6,2) not null default 0
    check (paid_leave_granted_days >= 0);

create table if not exists public.paid_leave_requests (
  id uuid primary key default gen_random_uuid(),
  batch_id uuid not null,
  company_id uuid not null references public.companies(id) on delete cascade,
  worker_id uuid not null references public.workers(id) on delete cascade,
  requested_by uuid not null references auth.users(id) on delete restrict,
  leave_date date not null,
  reason text,
  status text not null default 'pending'
    check (status in ('pending','approved','rejected','cancelled')),
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  review_note text,
  day_before_notified_at timestamptz,
  same_day_notified_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists paid_leave_requests_active_date_uniq
  on public.paid_leave_requests(company_id, worker_id, leave_date)
  where status in ('pending','approved');
create index if not exists paid_leave_requests_company_status_date_idx
  on public.paid_leave_requests(company_id, status, leave_date);
create index if not exists paid_leave_requests_worker_date_idx
  on public.paid_leave_requests(worker_id, leave_date desc);
create index if not exists paid_leave_requests_batch_idx
  on public.paid_leave_requests(batch_id);

alter table public.paid_leave_requests enable row level security;
revoke all on public.paid_leave_requests from anon, authenticated;
grant select on public.paid_leave_requests to authenticated;

drop policy if exists "paid leave self or management read"
  on public.paid_leave_requests;
create policy "paid leave self or management read"
on public.paid_leave_requests
for select
to authenticated
using (
  requested_by = (select auth.uid())
  or exists (
    select 1
    from public.company_members cm
    where cm.company_id = paid_leave_requests.company_id
      and cm.user_id = (select auth.uid())
      and cm.role::text in ('owner','admin','manager')
  )
);

create or replace function public.paid_leave_my_summary()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor uuid := auth.uid();
  v_worker_id uuid;
  v_company_id uuid;
  v_granted numeric := 0;
  v_used numeric := 0;
begin
  if v_actor is null then
    raise exception 'authentication required';
  end if;

  select w.id, w.company_id
  into v_worker_id, v_company_id
  from public.workers w
  join public.company_members cm
    on cm.company_id = w.company_id
   and cm.user_id = v_actor
  where w.user_id = v_actor
    and w.status = 'active'
  limit 1;

  if v_worker_id is null then
    raise exception 'worker profile not found';
  end if;

  select coalesce(wps.paid_leave_granted_days, 0)
  into v_granted
  from public.worker_payroll_settings wps
  where wps.worker_id = v_worker_id
  limit 1;
  v_granted := coalesce(v_granted, 0);

  select coalesce(count(*), 0)
  into v_used
  from public.paid_leave_requests r
  where r.company_id = v_company_id
    and r.worker_id = v_worker_id
    and r.status = 'approved';

  return jsonb_build_object(
    'worker_id', v_worker_id,
    'company_id', v_company_id,
    'granted_days', v_granted,
    'used_days', v_used,
    'remaining_days', greatest(v_granted - v_used, 0)
  );
end;
$$;

create or replace function public.submit_paid_leave_request(
  p_dates date[],
  p_reason text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_actor uuid := auth.uid();
  v_worker_id uuid;
  v_company_id uuid;
  v_batch_id uuid := gen_random_uuid();
  v_date date;
  v_today date := (now() at time zone 'Asia/Tokyo')::date;
  v_granted numeric := 0;
  v_used numeric := 0;
  v_pending numeric := 0;
  v_requested_count integer;
  v_recipient record;
begin
  if v_actor is null then
    raise exception 'authentication required';
  end if;
  if p_dates is null or cardinality(p_dates) < 1 then
    raise exception 'at least one leave date is required';
  end if;
  if cardinality(p_dates) > 31 then
    raise exception 'too many leave dates';
  end if;

  select w.id, w.company_id
  into v_worker_id, v_company_id
  from public.workers w
  join public.company_members cm
    on cm.company_id = w.company_id
   and cm.user_id = v_actor
  where w.user_id = v_actor
    and w.status = 'active'
  limit 1;

  if v_worker_id is null then
    raise exception 'worker profile not found';
  end if;

  select coalesce(wps.paid_leave_granted_days, 0)
  into v_granted
  from public.worker_payroll_settings wps
  where wps.worker_id = v_worker_id
  limit 1;
  v_granted := coalesce(v_granted, 0);

  select coalesce(count(*), 0)
  into v_used
  from public.paid_leave_requests r
  where r.worker_id = v_worker_id and r.status = 'approved';

  select coalesce(count(*), 0)
  into v_pending
  from public.paid_leave_requests r
  where r.worker_id = v_worker_id and r.status = 'pending';

  select count(distinct d)
  into v_requested_count
  from unnest(p_dates) as d;

  if v_used + v_pending + v_requested_count > v_granted then
    raise exception 'paid leave balance exceeded';
  end if;

  for v_date in select distinct d from unnest(p_dates) as d order by d
  loop
    if v_date <= v_today then
      raise exception 'paid leave request must use a future date';
    end if;
    if exists (
      select 1
      from public.paid_leave_requests r
      where r.company_id = v_company_id
        and r.worker_id = v_worker_id
        and r.leave_date = v_date
        and r.status in ('pending','approved')
    ) then
      raise exception 'paid leave already requested for %', v_date;
    end if;

    insert into public.paid_leave_requests(
      batch_id, company_id, worker_id, requested_by, leave_date, reason
    ) values (
      v_batch_id, v_company_id, v_worker_id, v_actor, v_date,
      nullif(trim(coalesce(p_reason,'')), '')
    );
  end loop;

  for v_recipient in
    select cm.user_id
    from public.company_members cm
    where cm.company_id = v_company_id
      and cm.role::text in ('owner','admin','manager')
  loop
    perform private.enqueue_notification(
      v_company_id,
      v_recipient.user_id,
      'approval',
      '有給申請があります',
      '有給申請が届きました。承認待ちから確認してください。',
      'paid_leave_request',
      v_batch_id
    );
  end loop;

  return v_batch_id;
end;
$$;

create or replace function public.pending_paid_leave_request_batches()
returns table(
  batch_id uuid,
  requested_by uuid,
  requested_by_name text,
  date_count bigint,
  first_date date,
  last_date date,
  reason text,
  submitted_at timestamptz
)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor uuid := auth.uid();
  v_company_id uuid;
begin
  select cm.company_id
  into v_company_id
  from public.company_members cm
  where cm.user_id = v_actor
    and cm.role::text in ('owner','admin','manager')
  limit 1;

  if v_company_id is null then
    raise exception 'management permission required';
  end if;

  return query
  select
    r.batch_id,
    r.requested_by,
    coalesce(w.name, 'SKOユーザー'),
    count(*),
    min(r.leave_date),
    max(r.leave_date),
    max(r.reason),
    min(r.created_at)
  from public.paid_leave_requests r
  left join public.workers w on w.id = r.worker_id
  where r.company_id = v_company_id
    and r.status = 'pending'
  group by r.batch_id, r.requested_by, w.name
  order by min(r.created_at);
end;
$$;

create or replace function public.paid_leave_request_dates(p_batch_id uuid)
returns table(leave_date date)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor uuid := auth.uid();
begin
  if not exists (
    select 1
    from public.paid_leave_requests r
    where r.batch_id = p_batch_id
      and (
        r.requested_by = v_actor
        or exists (
          select 1
          from public.company_members cm
          where cm.company_id = r.company_id
            and cm.user_id = v_actor
            and cm.role::text in ('owner','admin','manager')
        )
      )
  ) then
    raise exception 'paid leave request not accessible';
  end if;

  return query
  select r.leave_date
  from public.paid_leave_requests r
  where r.batch_id = p_batch_id
  order by r.leave_date;
end;
$$;

create or replace function public.decide_paid_leave_request(
  p_batch_id uuid,
  p_decision text,
  p_note text default null
)
returns text
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_actor uuid := auth.uid();
  v_company_id uuid;
  v_requested_by uuid;
  v_worker_id uuid;
  v_status text;
  v_granted numeric := 0;
  v_used numeric := 0;
  v_batch_count numeric := 0;
begin
  if p_decision not in ('approve','reject') then
    raise exception 'invalid decision';
  end if;

  select r.company_id, r.requested_by, r.worker_id
  into v_company_id, v_requested_by, v_worker_id
  from public.paid_leave_requests r
  where r.batch_id = p_batch_id
    and r.status = 'pending'
  limit 1
  for update;

  if v_company_id is null then
    raise exception 'pending paid leave request not found';
  end if;

  if not exists (
    select 1
    from public.company_members cm
    where cm.company_id = v_company_id
      and cm.user_id = v_actor
      and cm.role::text in ('owner','admin','manager')
  ) then
    raise exception 'management permission required';
  end if;

  if p_decision = 'approve' then
    select coalesce(wps.paid_leave_granted_days, 0)
    into v_granted
    from public.worker_payroll_settings wps
    where wps.worker_id = v_worker_id
    limit 1;
    v_granted := coalesce(v_granted, 0);

    select count(*)
    into v_used
    from public.paid_leave_requests r
    where r.worker_id = v_worker_id
      and r.status = 'approved';

    select count(*)
    into v_batch_count
    from public.paid_leave_requests r
    where r.batch_id = p_batch_id
      and r.status = 'pending';

    if v_used + v_batch_count > v_granted then
      raise exception 'paid leave balance exceeded';
    end if;

    v_status := 'approved';
  else
    v_status := 'rejected';
  end if;

  update public.paid_leave_requests
  set status = v_status,
      reviewed_by = v_actor,
      reviewed_at = now(),
      review_note = nullif(trim(coalesce(p_note,'')), ''),
      updated_at = now()
  where batch_id = p_batch_id and status = 'pending';

  perform private.enqueue_notification(
    v_company_id,
    v_requested_by,
    case when v_status = 'approved' then 'approval' else 'warning' end,
    case when v_status = 'approved'
      then '有給申請が承認されました'
      else '有給申請が却下されました'
    end,
    case when v_status = 'approved'
      then '申請した有給が承認されました。出勤表に反映されます。'
      else '有給申請が却下されました。内容を確認してください。'
    end,
    'paid_leave_request',
    p_batch_id
  );

  return v_status;
end;
$$;

create or replace function private.enqueue_paid_leave_reminders(p_mode text)
returns integer
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_today date := (now() at time zone 'Asia/Tokyo')::date;
  v_target date;
  v_row record;
  v_recipient record;
  v_count integer := 0;
begin
  if p_mode = 'day_before' then
    v_target := v_today + 1;
  elsif p_mode = 'same_day' then
    v_target := v_today;
  else
    raise exception 'invalid reminder mode';
  end if;

  for v_row in
    select r.id, r.company_id, r.worker_id, r.leave_date, w.name
    from public.paid_leave_requests r
    join public.workers w on w.id = r.worker_id
    where r.status = 'approved'
      and r.leave_date = v_target
      and (
        (p_mode = 'day_before' and r.day_before_notified_at is null)
        or
        (p_mode = 'same_day' and r.same_day_notified_at is null)
      )
  loop
    for v_recipient in
      select cm.user_id
      from public.company_members cm
      where cm.company_id = v_row.company_id
        and cm.role::text in ('owner','admin','manager')
    loop
      perform private.enqueue_notification(
        v_row.company_id,
        v_recipient.user_id,
        'info',
        case when p_mode = 'day_before'
          then v_row.name || 'さんは明日、有給でお休みです'
          else v_row.name || 'さんは本日、有給です'
        end,
        case when p_mode = 'day_before'
          then v_row.name || 'さんは明日、有給でお休みです'
          else v_row.name || 'さんは本日、有給です'
        end,
        'paid_leave_reminder',
        v_row.id
      );
    end loop;

    update public.paid_leave_requests
    set day_before_notified_at =
          case when p_mode = 'day_before' then now() else day_before_notified_at end,
        same_day_notified_at =
          case when p_mode = 'same_day' then now() else same_day_notified_at end,
        updated_at = now()
    where id = v_row.id;

    v_count := v_count + 1;
  end loop;

  return v_count;
end;
$$;

revoke execute on function public.paid_leave_my_summary() from public, anon;
revoke execute on function public.submit_paid_leave_request(date[],text) from public, anon;
revoke execute on function public.pending_paid_leave_request_batches() from public, anon;
revoke execute on function public.paid_leave_request_dates(uuid) from public, anon;
revoke execute on function public.decide_paid_leave_request(uuid,text,text) from public, anon;

grant execute on function public.paid_leave_my_summary() to authenticated;
grant execute on function public.submit_paid_leave_request(date[],text) to authenticated;
grant execute on function public.pending_paid_leave_request_batches() to authenticated;
grant execute on function public.paid_leave_request_dates(uuid) to authenticated;
grant execute on function public.decide_paid_leave_request(uuid,text,text) to authenticated;

revoke all on function private.enqueue_paid_leave_reminders(text)
  from public, anon, authenticated;

create extension if not exists pg_cron with schema pg_catalog;
grant usage on schema cron to postgres;
grant all privileges on all tables in schema cron to postgres;

select cron.unschedule(jobid)
from cron.job
where jobname in ('sko-paid-leave-day-before','sko-paid-leave-same-day');

select cron.schedule(
  'sko-paid-leave-day-before',
  '0 0 * * *',
  $$select private.enqueue_paid_leave_reminders('day_before');$$
);
select cron.schedule(
  'sko-paid-leave-same-day',
  '0 23 * * *',
  $$select private.enqueue_paid_leave_reminders('same_day');$$
);
