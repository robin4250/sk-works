create or replace function private.sync_payroll_attendance_detail(
  cid uuid,
  wid uuid,
  day date
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  start_day date := date_trunc('month', day)::date;
  end_day date := (date_trunc('month', day) + interval '1 month - 1 day')::date;
  v_work_days numeric := 0;
  v_holiday_days numeric := 0;
  v_overtime numeric := 0;
  v_early numeric := 0;
  v_night numeric := 0;
  v_paid_leave numeric := 0;
begin
  select
    coalesce(sum(coalesce(ae.base_man_days,0)),0),
    coalesce(sum(case when ae.work_category in ('holiday','holiday_night') then coalesce(ae.base_man_days,0) else 0 end),0),
    coalesce(sum(coalesce(ae.overtime_hours,0)),0),
    coalesce(sum(coalesce(ae.early_hours,0)),0),
    coalesce(sum(coalesce(ae.night_hours,0)),0)
  into v_work_days,v_holiday_days,v_overtime,v_early,v_night
  from public.attendance_entries ae
  where ae.company_id=cid
    and ae.worker_id=wid
    and ae.work_date between start_day and end_day;

  select coalesce(count(*),0)
  into v_paid_leave
  from public.paid_leave_requests pl
  where pl.company_id=cid
    and pl.worker_id=wid
    and pl.leave_date between start_day and end_day
    and pl.status='approved';

  update public.payroll_statements ps
  set detail=coalesce(ps.detail,'{}'::jsonb) || jsonb_build_object(
        '出勤日数',v_work_days,
        '休出日数',v_holiday_days,
        '残業時間',v_overtime,
        '早出時間',v_early,
        '夜間時間',v_night,
        '有給日数',v_paid_leave
      ),
      updated_at=now()
  where ps.company_id=cid
    and ps.worker_id=wid
    and ps.period_start=start_day
    and ps.period_end=end_day
    and ps.automatic_calculation
    and ps.workflow_state='draft';
end;
$$;

revoke all on function private.sync_payroll_attendance_detail(uuid,uuid,date)
from public, anon, authenticated;

create or replace function private.attendance_sync_payroll_detail()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op <> 'INSERT' then
    perform private.sync_payroll_attendance_detail(old.company_id,old.worker_id,old.work_date);
  end if;
  if tg_op <> 'DELETE' then
    perform private.sync_payroll_attendance_detail(new.company_id,new.worker_id,new.work_date);
  end if;
  return null;
end;
$$;

drop trigger if exists attendance_sync_payroll_detail on public.attendance_entries;
create trigger attendance_sync_payroll_detail
after insert or update or delete on public.attendance_entries
for each row execute function private.attendance_sync_payroll_detail();

create or replace function private.paid_leave_sync_payroll_detail()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op <> 'INSERT' then
    perform private.sync_payroll_attendance_detail(old.company_id,old.worker_id,old.leave_date);
  end if;
  if tg_op <> 'DELETE' then
    perform private.sync_payroll_attendance_detail(new.company_id,new.worker_id,new.leave_date);
  end if;
  return null;
end;
$$;

drop trigger if exists paid_leave_sync_payroll_detail on public.paid_leave_requests;
create trigger paid_leave_sync_payroll_detail
after insert or update or delete on public.paid_leave_requests
for each row execute function private.paid_leave_sync_payroll_detail();
