create or replace function public.submit_retrospective_paid_leave_request(
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
  if v_actor is null then raise exception 'authentication required'; end if;
  if p_dates is null or cardinality(p_dates) < 1 then
    raise exception 'at least one leave date is required';
  end if;
  if cardinality(p_dates) > 31 then raise exception 'too many leave dates'; end if;
  select w.id,w.company_id into v_worker_id,v_company_id
  from public.workers w
  join public.company_members cm
    on cm.company_id=w.company_id and cm.user_id=v_actor
  where w.user_id=v_actor and w.status='active'
  limit 1;
  if v_worker_id is null then raise exception 'worker profile not found'; end if;
  select coalesce(wps.paid_leave_granted_days,0) into v_granted
  from public.worker_payroll_settings wps
  where wps.worker_id=v_worker_id limit 1;
  v_granted := coalesce(v_granted,0);
  select count(*) into v_used from public.paid_leave_requests r
  where r.worker_id=v_worker_id and r.status='approved';
  select count(*) into v_pending from public.paid_leave_requests r
  where r.worker_id=v_worker_id and r.status='pending';
  select count(distinct d) into v_requested_count from unnest(p_dates) as d;
  if v_used+v_pending+v_requested_count > v_granted then
    raise exception 'paid leave balance exceeded';
  end if;
  for v_date in select distinct d from unnest(p_dates) as d order by d
  loop
    if v_date > v_today then
      raise exception 'future paid leave must use normal paid leave request';
    end if;
    if exists (
      select 1 from public.attendance_entries ae
      where ae.worker_id=v_worker_id and ae.work_date=v_date
    ) then
      raise exception 'attendance exists for %, use attendance correction first',v_date;
    end if;
    if exists (
      select 1 from public.paid_leave_requests r
      where r.company_id=v_company_id and r.worker_id=v_worker_id
        and r.leave_date=v_date and r.status in ('pending','approved')
    ) then
      raise exception 'paid leave already requested for %',v_date;
    end if;
    insert into public.paid_leave_requests(
      batch_id,company_id,worker_id,requested_by,leave_date,reason
    ) values (
      v_batch_id,v_company_id,v_worker_id,v_actor,v_date,
      nullif(trim(coalesce(p_reason,'')),'')
    );
  end loop;
  for v_recipient in
    select cm.user_id from public.company_members cm
    where cm.company_id=v_company_id
      and cm.role::text in ('owner','admin','manager')
  loop
    perform private.enqueue_notification(
      v_company_id,v_recipient.user_id,'approval',
      '有給への勤務修正申請があります',
      '休みから有給への勤務修正申請が届きました。承認待ちから確認してください。',
      'paid_leave_request',v_batch_id
    );
  end loop;
  return v_batch_id;
end;
$$;
revoke execute on function public.submit_retrospective_paid_leave_request(date[],text)
  from public, anon;
grant execute on function public.submit_retrospective_paid_leave_request(date[],text)
  to authenticated;
