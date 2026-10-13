-- Read-only explanation of the existing candidate policy. Does not recover
-- archived attendance, infer checkout or alter billing/payroll/finalization.
begin;
create function private.route_customer_day_quantity_diagnostics(
  p_worker_id uuid, p_work_date date
) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare cid uuid; result jsonb;
begin
  if auth.uid() is null or not private.account_access_allowed() then
    raise exception 'account unavailable' using errcode='42501';
  end if;
  select company_id into cid from public.workers where id=p_worker_id;
  if cid is null or p_work_date is null or not exists(
    select 1 from public.company_members m
    where m.company_id=cid and m.user_id=auth.uid()
  ) then
    raise exception 'worker unavailable' using errcode='42501';
  end if;
  -- Same completed, actor-owned, worker/day/company boundary as candidates.
  -- Counts contain no archived snapshot, worker names, prices or other actors.
  with reports as (
    select
      exists(select 1 from public.attendance_verifications a
        where a.company_id=cid and a.id=v.source_clock_in_id
        and a.event_type='clock_in') has_clock_in,
      exists(select 1 from public.attendance_verifications a
        where a.company_id=cid and a.source_clock_in_id=v.source_clock_in_id
        and a.event_type='clock_out') has_clock_out,
      exists(select 1 from public.sites s join public.customers c
        on c.id=s.customer_id and c.company_id=cid
        where s.id=v.site_id and s.company_id=cid) has_customer
    from private.route_visit_reports v
    where v.company_id=cid and v.created_by=auth.uid()
      and v.report_date=p_work_date and v.status='completed'
      and exists(select 1 from jsonb_array_elements(v.workers) w
        where w->>'worker_id'=p_worker_id::text)
  )
  select jsonb_build_object(
    'completed_report_count',count(*),
    'eligible_report_count',count(*) filter(where has_clock_out and has_customer),
    'unresolved_customer_count',count(*) filter(where has_clock_out and not has_customer),
    'missing_source_count',count(*) filter(where not has_clock_out and not has_clock_in),
    'waiting_checkout_count',count(*) filter(where not has_clock_out and has_clock_in)
  ) into result from reports;
  return result;
end $$;
revoke all on function private.route_customer_day_quantity_diagnostics(uuid,date)
  from public,anon,authenticated;
grant execute on function private.route_customer_day_quantity_diagnostics(uuid,date)
  to authenticated;
create function public.route_customer_day_quantity_diagnostics(
  p_worker_id uuid, p_work_date date
) returns jsonb language sql stable security invoker set search_path='' as $$
  select private.route_customer_day_quantity_diagnostics(p_worker_id,p_work_date);
$$;
revoke all on function public.route_customer_day_quantity_diagnostics(uuid,date)
  from public,anon,authenticated;
grant execute on function public.route_customer_day_quantity_diagnostics(uuid,date)
  to authenticated;
commit;
