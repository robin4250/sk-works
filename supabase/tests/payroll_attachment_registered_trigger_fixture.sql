-- Captured registered trigger definitions, metadata-only 2026-10-09. Disposable fixture only.
CREATE OR REPLACE FUNCTION private.validate_attendance_shift_evidence()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
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
end $function$
;
DROP TRIGGER IF EXISTS attendance_shift_evidence_guard ON public.attendance_verifications;
CREATE TRIGGER attendance_shift_evidence_guard BEFORE INSERT OR UPDATE ON attendance_verifications FOR EACH ROW EXECUTE FUNCTION private.validate_attendance_shift_evidence();
CREATE OR REPLACE FUNCTION private.clear_daily_report_signatures_on_workers()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  update public.daily_reports set representative_signature_json=null, representative_signer_name=null,
    supervisor_signature_json=null, supervisor_signer_name=null
  where id=coalesce(new.report_id, old.report_id) and status='draft';
  return coalesce(new,old);
end;
$function$
;
DROP TRIGGER IF EXISTS clear_daily_report_signatures_on_workers ON public.daily_report_workers;
CREATE TRIGGER clear_daily_report_signatures_on_workers AFTER INSERT OR DELETE OR UPDATE ON daily_report_workers FOR EACH ROW EXECUTE FUNCTION private.clear_daily_report_signatures_on_workers();
CREATE OR REPLACE FUNCTION private.clear_daily_report_signatures_on_draft()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  if new.status = 'draft' and (
    new.work_description is distinct from old.work_description or
    new.site_id is distinct from old.site_id or new.report_date is distinct from old.report_date or
    new.signature_json is null and old.signature_json is not null
  ) then
    new.representative_signature_json := null;
    new.representative_signer_name := null;
    new.supervisor_signature_json := null;
    new.supervisor_signer_name := null;
  end if;
  return new;
end;
$function$
;
DROP TRIGGER IF EXISTS clear_daily_report_signatures_on_draft ON public.daily_reports;
CREATE TRIGGER clear_daily_report_signatures_on_draft BEFORE UPDATE ON daily_reports FOR EACH ROW EXECUTE FUNCTION private.clear_daily_report_signatures_on_draft();
CREATE OR REPLACE FUNCTION private.report_refresh_payroll()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare a record; begin
 if old.status is distinct from new.status then
   for a in select distinct company_id,worker_id,work_date from public.attendance_entries
     where source_report_id=new.id order by company_id,worker_id,work_date loop
     perform private.refresh_automatic_payroll(a.company_id,a.worker_id,a.work_date);
   end loop;
 end if;
 return null;
end;
$function$
;
DROP TRIGGER IF EXISTS report_refresh_payroll ON public.daily_reports;
CREATE TRIGGER report_refresh_payroll AFTER UPDATE ON daily_reports FOR EACH ROW EXECUTE FUNCTION private.report_refresh_payroll();CREATE OR REPLACE FUNCTION private.link_daily_report_attendance_evidence(p_report_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
    and coalesce(a.work_date,(a.confirmed_at at time zone 'Asia/Tokyo')::date)=v_date
    and a.photo_storage_path is not null
    and a.daily_report_id is null;

  get diagnostics v_count=row_count;
  return v_count;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.link_daily_report_attendance_evidence(p_report_id uuid)
 RETURNS integer
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select private.link_daily_report_attendance_evidence(p_report_id) $function$
;
