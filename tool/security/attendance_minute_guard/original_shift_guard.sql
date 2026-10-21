create or replace function private.validate_attendance_shift_evidence()
returns trigger language plpgsql security invoker set search_path='' as $$
declare
  v_start public.attendance_verifications%rowtype;
  v_report public.daily_reports%rowtype;
  v_date date;
begin
  -- Evidence chronology/ownership cannot be rewritten. Management corrects by
  -- replacing complete shifts, and photograph/report linking stays available.
  if TG_OP='UPDATE' then
    if row(NEW.id,NEW.company_id,NEW.worker_id,NEW.site_id,NEW.route_assignment_id,
           NEW.event_type,NEW.confirmed_at,NEW.source_clock_in_id,NEW.work_date)
       is distinct from
       row(OLD.id,OLD.company_id,OLD.worker_id,OLD.site_id,OLD.route_assignment_id,
           OLD.event_type,OLD.confirmed_at,OLD.source_clock_in_id,OLD.work_date) then
      raise exception 'attendance evidence chronology is immutable';
    end if;
    -- Preserve existing vehicle FK ON DELETE SET NULL while preventing edits.
    if NEW.vehicle_id is distinct from OLD.vehicle_id and not (
      NEW.vehicle_id is null and OLD.vehicle_id is not null and not exists (
        select 1 from public.vehicles v where v.id=OLD.vehicle_id
      )
    ) then raise exception 'attendance evidence vehicle is immutable'; end if;
    v_date := coalesce(NEW.work_date,(NEW.confirmed_at at time zone 'Asia/Tokyo')::date);
  else
    v_date := (NEW.confirmed_at at time zone 'Asia/Tokyo')::date;
  end if;

  if NEW.vehicle_id is not null and not exists (
    select 1 from public.vehicles v where v.id=NEW.vehicle_id and v.company_id=NEW.company_id
  ) then raise exception 'attendance vehicle does not belong to company'; end if;

  if NEW.source_clock_in_id is not null then
    if NEW.event_type <> 'clock_out' or NEW.source_clock_in_id=NEW.id then
      raise exception 'only clock out can reference its clock in';
    end if;
    -- SECURITY INVOKER: source visibility is governed by the existing RLS.
    select * into v_start from public.attendance_verifications
      where id=NEW.source_clock_in_id;
    if not found or v_start.event_type <> 'clock_in'
       or row(v_start.company_id,v_start.worker_id,v_start.site_id,v_start.route_assignment_id,v_start.vehicle_id)
          is distinct from row(NEW.company_id,NEW.worker_id,NEW.site_id,NEW.route_assignment_id,NEW.vehicle_id)
       or NEW.confirmed_at < v_start.confirmed_at then
      raise exception 'clock out source is unavailable or inconsistent';
    end if;
    v_date := coalesce(v_start.work_date,(v_start.confirmed_at at time zone 'Asia/Tokyo')::date);
    if v_start.work_date is null and v_start.daily_report_id is not null then
      select * into v_report from public.daily_reports where id=v_start.daily_report_id;
      if not found or row(v_report.company_id,v_report.site_id,v_report.route_assignment_id)
         is distinct from row(NEW.company_id,NEW.site_id,NEW.route_assignment_id) then
        raise exception 'clock in report is inconsistent';
      end if;
      v_date := v_report.report_date;
    end if;
    if TG_OP='INSERT' and exists (
      select 1 from public.attendance_verifications a
      where a.company_id=NEW.company_id and a.worker_id=NEW.worker_id
        and a.site_id is not distinct from NEW.site_id
        and a.route_assignment_id is not distinct from NEW.route_assignment_id
        and a.confirmed_at >= v_start.confirmed_at
        and a.confirmed_at <= NEW.confirmed_at
        and a.event_type='clock_out' and a.source_clock_in_id is null
    ) then
      raise exception 'clock in is already closed or its evidence is ambiguous';
    end if;
  end if;

  if NEW.daily_report_id is not null then
    select * into v_report from public.daily_reports where id=NEW.daily_report_id;
    if not found or row(v_report.company_id,v_report.site_id,v_report.route_assignment_id)
       is distinct from row(NEW.company_id,NEW.site_id,NEW.route_assignment_id)
       or (NEW.source_clock_in_id is not null and v_report.report_date <> v_date)
       or (NEW.work_date is not null and TG_OP='UPDATE' and v_report.report_date <> NEW.work_date) then
      raise exception 'attendance report date or destination is inconsistent';
    end if;
    -- Existing management RPC associates a next-morning end with the report day.
    if NEW.source_clock_in_id is null then v_date := v_report.report_date; end if;
  end if;
  if TG_OP='UPDATE' and NEW.event_type='clock_in' and exists (
    select 1 from public.attendance_verifications child
    where child.source_clock_in_id=NEW.id and child.work_date is distinct from v_date
  ) then
    raise exception 'clock in report cannot change its closed shift date';
  end if;
  if TG_OP='INSERT' then NEW.work_date := v_date; end if;
  return NEW;
end $$;
