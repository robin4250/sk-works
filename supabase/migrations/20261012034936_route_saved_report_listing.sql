-- Read saved visit documents without merging them into the checkout report.
create index if not exists route_visit_reports_creator_date_id_idx
  on private.route_visit_reports(created_by, report_date, created_at, id);

create or replace function public.list_saved_route_visit_reports(
  p_from_date date,
  p_until_date date,
  p_worker_id uuid default null,
  p_offset integer default 0,
  p_limit integer default 500
) returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare result jsonb;
begin
  if auth.uid() is null or not private.account_access_allowed() then
    raise exception 'account unavailable' using errcode = '42501';
  end if;
  if p_from_date is null or p_until_date is null
    or p_until_date <= p_from_date or p_until_date - p_from_date > 32
    or p_offset is null or p_offset < 0
    or p_limit is null or p_limit < 1 or p_limit > 500 then
    raise exception 'invalid report range' using errcode = '22023';
  end if;
  select coalesce(jsonb_agg(page.document order by page.report_date, page.created_at, page.id), '[]'::jsonb)
  into result
  from (
    select r.report_date, r.created_at, r.id, jsonb_build_object(
      'id', r.id, 'report_date', r.report_date, 'status', r.status,
      'created_at', r.created_at,
      'site_id', r.site_id, 'site_name', r.site_name,
      'route_name', ra.route_name,
      'source_clock_in_id', r.source_clock_in_id,
      'route_assignment_id', r.route_assignment_id,
      'route_stop_id', r.route_stop_id,
      'start_capture_id', r.start_capture_id,
      'end_capture_id', r.end_capture_id
    ) as document
    from private.route_visit_reports r
    left join public.route_assignments ra
      on ra.id = r.route_assignment_id and ra.company_id = r.company_id
    where r.created_by = auth.uid()
      and exists (
        select 1 from public.company_members cm
        where cm.company_id = r.company_id and cm.user_id = auth.uid()
      )
      and r.report_date >= p_from_date and r.report_date < p_until_date
      and r.status <> 'skipped'
      and (p_worker_id is null or exists (
        select 1 from jsonb_array_elements(r.workers) worker
        where worker->>'worker_id' = p_worker_id::text
      ))
    order by r.report_date, r.created_at, r.id
    offset p_offset limit p_limit
  ) page;
  return result;
end;
$$;

revoke all on function public.list_saved_route_visit_reports(date,date,uuid,integer,integer)
  from public, anon, authenticated;
grant execute on function public.list_saved_route_visit_reports(date,date,uuid,integer,integer)
  to authenticated;
