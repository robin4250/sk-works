-- Definition rollback only. No attendance or Storage data changes.
CREATE OR REPLACE FUNCTION private.link_daily_report_attendance_evidence(p_report_id uuid)
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
$function$;

