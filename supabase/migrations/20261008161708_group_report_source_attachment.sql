-- Depends at runtime on the staged group proxy checkout migration (#765).
-- No gate activation, original evidence edits, report edits or notifications.
create function private.attach_group_report_sources(
  p_daily_report_id uuid, p_anchor_source_clock_in_id uuid,
  p_source_clock_in_ids uuid[])
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  a public.attendance_verifications%rowtype;
  d public.daily_reports%rowtype;
  s public.attendance_verifications%rowtype;
  o public.attendance_verifications%rowtype;
  v_ids uuid[]; v_count integer; v_needs_change boolean:=false;
begin
  if auth.uid() is null or not private.account_access_allowed() then
    raise exception 'report attendance access unavailable' using errcode='42501';
  end if;
  if p_daily_report_id is null or p_anchor_source_clock_in_id is null
     or cardinality(p_source_clock_in_ids) is null
     or cardinality(p_source_clock_in_ids) not between 1 and 100
     or array_position(p_source_clock_in_ids,null) is not null then
    raise exception 'invalid report attendance selection';
  end if;
  select array_agg(id order by id) into v_ids
    from(select distinct unnest(p_source_clock_in_ids) id) selected;
  if cardinality(v_ids)<>cardinality(p_source_clock_in_ids) then
    raise exception 'duplicate report attendance selection';
  end if;
  -- This existing helper enforces current membership, active own-worker anchor,
  -- site-only source, canonical work date, account guard and staged gate ON.
  a:=private.group_checkout_anchor(p_anchor_source_clock_in_id);
  select * into d from public.daily_reports where id=p_daily_report_id for update;
  if not found or row(d.company_id,d.site_id,d.route_assignment_id,d.report_date)
     is distinct from row(a.company_id,a.site_id,a.route_assignment_id,a.work_date)
     or not (d.created_by is not distinct from auth.uid()
             or d.updated_by is not distinct from auth.uid()) then
    raise exception 'saved report is unavailable for this attendance group' using errcode='42501';
  end if;
  -- The own anchor must be in the saved roster, even if callers only attach
  -- other participants. Manual roster rows without evidence remain untouched.
  perform 1 from public.daily_report_workers
    where report_id=d.id and worker_id=a.worker_id for share;
  if not found then raise exception 'anchor worker is absent from saved report'; end if;
  perform 1 from public.attendance_verifications
    where id=any(v_ids) order by id for update;
  get diagnostics v_count=row_count;
  if v_count<>cardinality(v_ids) then raise exception 'report attendance source unavailable'; end if;
  -- Validate every selection before changing anything. No chronology guesses,
  -- unmatched manual out, worker replacement or existing report reassignment.
  for s in select * from public.attendance_verifications where id=any(v_ids) order by id loop
    if s.event_type<>'clock_in' or s.work_date is null
       or row(s.company_id,s.site_id,s.route_assignment_id,s.work_date)
          is distinct from row(a.company_id,a.site_id,a.route_assignment_id,a.work_date)
       or not exists(select 1 from public.workers w where w.id=s.worker_id
          and w.company_id=a.company_id and w.status='active') then
      raise exception 'selected source is outside this attendance group';
    end if;
    perform 1 from public.daily_report_workers
      where report_id=d.id and worker_id=s.worker_id for share;
    if not found then raise exception 'attendance worker is absent from saved report'; end if;
    select * into o from public.attendance_verifications
      where source_clock_in_id=s.id and event_type='clock_out' for update;
    if not found or row(o.company_id,o.worker_id,o.site_id,o.route_assignment_id,o.work_date,o.vehicle_id)
       is distinct from row(s.company_id,s.worker_id,s.site_id,s.route_assignment_id,s.work_date,s.vehicle_id)
       or o.confirmed_at<s.confirmed_at then
      raise exception 'selected shift has no consistent completed checkout';
    end if;
    if (s.daily_report_id is not null and s.daily_report_id<>d.id)
       or (o.daily_report_id is not null and o.daily_report_id<>d.id) then
      raise exception 'attendance already belongs to another report';
    end if;
    v_needs_change:=v_needs_change or s.daily_report_id is null or o.daily_report_id is null;
  end loop;
  if v_needs_change and (d.status='signed' or d.signed_at is not null) then
    raise exception 'signed report requires edit approval';
  end if;
  -- Existing triggers still enforce company/date/source/GPS/proxy invariants.
  -- Idempotent retries (including signed reports) execute no UPDATE at all.
  if v_needs_change then
    update public.attendance_verifications set daily_report_id=d.id
      where daily_report_id is null
        and (id=any(v_ids) or source_clock_in_id=any(v_ids));
  end if;
  return jsonb_build_object('daily_report_id',d.id,'source_clock_in_ids',to_jsonb(v_ids));
end $$;
revoke all on function private.attach_group_report_sources(uuid,uuid,uuid[]) from public,anon;
grant execute on function private.attach_group_report_sources(uuid,uuid,uuid[]) to authenticated;

create function public.attach_group_report_sources(
  p_daily_report_id uuid, p_anchor_source_clock_in_id uuid,
  p_source_clock_in_ids uuid[])
returns jsonb language sql security invoker set search_path='' as $$
  select private.attach_group_report_sources(p_daily_report_id,p_anchor_source_clock_in_id,p_source_clock_in_ids)
$$;
revoke all on function public.attach_group_report_sources(uuid,uuid,uuid[]) from public,anon;
grant execute on function public.attach_group_report_sources(uuid,uuid,uuid[]) to authenticated;
