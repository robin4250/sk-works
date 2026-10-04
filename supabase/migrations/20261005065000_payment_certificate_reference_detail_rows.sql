-- Reference-form detail feed for payment certificates.
-- Keeps direct workers reads closed and exposes only the current company's
-- selected certificate breakdown to management users.

create or replace function public.payment_certificate_detail_rows(
  p_certificate_id uuid
)
returns table(
  site_name text,
  work_content text,
  quantity_label text,
  unit_price_yen integer,
  amount_yen integer
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_company_id uuid;
  v_partner_id uuid;
  v_start date;
  v_end date;
  v_daily integer := 0;
  v_overtime integer := 0;
  v_early integer := 0;
  v_night integer := 0;
begin
  if v_uid is null then
    raise exception 'authentication required';
  end if;

  select pc.company_id, pc.partner_company_id, pc.period_start, pc.period_end
    into v_company_id, v_partner_id, v_start, v_end
  from public.payment_certificates pc
  where pc.id = p_certificate_id;

  if v_company_id is null then
    raise exception 'payment certificate not found';
  end if;

  if not exists (
    select 1
    from public.company_members cm
    where cm.company_id = v_company_id
      and cm.user_id = v_uid
      and cm.role::text in ('owner','admin','manager')
  ) then
    raise exception 'payment certificate permission required';
  end if;

  select
    coalesce(pps.daily_rate_yen,0),
    coalesce(pps.overtime_hour_rate_yen,0),
    coalesce(pps.early_hour_rate_yen,0),
    coalesce(pps.night_hour_rate_yen,0)
    into v_daily, v_overtime, v_early, v_night
  from public.partner_payment_settings pps
  where pps.company_id = v_company_id
    and pps.partner_company_id = v_partner_id;

  return query
  with source as (
    select
      coalesce(nullif(s.formal_name,''),s.name,'現場未設定') as site_name,
      coalesce(a.work_category,'一般') as work_category,
      sum(coalesce(a.base_man_days,0)) as man_days,
      sum(coalesce(a.overtime_hours,0)) as overtime_hours,
      sum(coalesce(a.early_hours,0)) as early_hours,
      sum(coalesce(a.night_hours,0)) as night_hours
    from public.attendance_entries a
    join public.workers w
      on w.id=a.worker_id
     and w.company_id=a.company_id
    left join public.sites s
      on s.id=a.site_id
     and s.company_id=a.company_id
    where a.company_id=v_company_id
      and w.partner_company_id=v_partner_id
      and a.work_date between v_start and v_end
    group by
      coalesce(nullif(s.formal_name,''),s.name,'現場未設定'),
      coalesce(a.work_category,'一般')
  ),
  lines as (
    select site_name, work_category as work_content,
           trim(to_char(man_days,'FM999999990.##'))||'人' as quantity_label,
           v_daily as unit_price_yen,
           round(man_days*v_daily)::integer as amount_yen,
           1 as sort_order
    from source where man_days<>0
    union all
    select site_name, '残業',
           trim(to_char(overtime_hours,'FM999999990.##'))||'H',
           v_overtime,
           round(overtime_hours*v_overtime)::integer,
           2
    from source where overtime_hours<>0
    union all
    select site_name, '早出',
           trim(to_char(early_hours,'FM999999990.##'))||'H',
           v_early,
           round(early_hours*v_early)::integer,
           3
    from source where early_hours<>0
    union all
    select site_name, '夜間作業',
           trim(to_char(night_hours,'FM999999990.##'))||'H',
           v_night,
           round(night_hours*v_night)::integer,
           4
    from source where night_hours<>0
  )
  select l.site_name,l.work_content,l.quantity_label,l.unit_price_yen,l.amount_yen
  from lines l
  order by l.site_name,l.sort_order,l.work_content;
end;
$$;

revoke all on function public.payment_certificate_detail_rows(uuid)
from public, anon;
grant execute on function public.payment_certificate_detail_rows(uuid)
to authenticated;
