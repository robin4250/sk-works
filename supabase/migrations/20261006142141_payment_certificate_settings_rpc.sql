-- Stable RPC contract for payment certificate settings.
create or replace function private.partner_payment_settings_workspace()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare cid uuid;
begin
  cid:=private.current_company_admin_id();
  if cid is null then raise exception '管理者のみ操作できます。'; end if;

  return coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'partner_company_id',p.id,
        'partner_company_name',p.name,
        'daily_rate_yen',coalesce(s.daily_rate_yen,0),
        'overtime_hour_rate_yen',coalesce(s.overtime_hour_rate_yen,0),
        'early_hour_rate_yen',coalesce(s.early_hour_rate_yen,0),
        'night_hour_rate_yen',coalesce(s.night_hour_rate_yen,0)
      )
      order by p.name
    )
    from public.partner_companies p
    left join public.partner_payment_settings s
      on s.company_id=p.company_id and s.partner_company_id=p.id
    where p.company_id=cid and p.status='active'
  ),'[]'::jsonb);
end
$$;

create or replace function private.save_partner_payment_setting(
  p_partner_company_id uuid,
  p_daily_rate_yen integer,
  p_overtime_hour_rate_yen integer,
  p_early_hour_rate_yen integer,
  p_night_hour_rate_yen integer
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare cid uuid;
begin
  cid:=private.current_company_admin_id();
  if cid is null then raise exception '管理者のみ操作できます。'; end if;

  if not exists(
    select 1 from public.partner_companies
    where id=p_partner_company_id and company_id=cid and status='active'
  ) then
    raise exception '協力会社が見つかりません。';
  end if;

  if least(
    coalesce(p_daily_rate_yen,0),
    coalesce(p_overtime_hour_rate_yen,0),
    coalesce(p_early_hour_rate_yen,0),
    coalesce(p_night_hour_rate_yen,0)
  ) < 0 then
    raise exception '金額は0以上で入力してください。';
  end if;

  insert into public.partner_payment_settings(
    company_id,partner_company_id,daily_rate_yen,
    overtime_hour_rate_yen,early_hour_rate_yen,night_hour_rate_yen,updated_at
  )
  values(
    cid,p_partner_company_id,coalesce(p_daily_rate_yen,0),
    coalesce(p_overtime_hour_rate_yen,0),coalesce(p_early_hour_rate_yen,0),
    coalesce(p_night_hour_rate_yen,0),now()
  )
  on conflict(company_id,partner_company_id) do update
  set daily_rate_yen=excluded.daily_rate_yen,
      overtime_hour_rate_yen=excluded.overtime_hour_rate_yen,
      early_hour_rate_yen=excluded.early_hour_rate_yen,
      night_hour_rate_yen=excluded.night_hour_rate_yen,
      updated_at=now();
end
$$;

create or replace function public.partner_payment_settings_workspace()
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select private.partner_payment_settings_workspace()
$$;

create or replace function public.save_partner_payment_setting(
  p_partner_company_id uuid,
  p_daily_rate_yen integer,
  p_overtime_hour_rate_yen integer,
  p_early_hour_rate_yen integer,
  p_night_hour_rate_yen integer
)
returns void
language sql
security definer
set search_path = ''
as $$
  select private.save_partner_payment_setting(
    p_partner_company_id,p_daily_rate_yen,p_overtime_hour_rate_yen,
    p_early_hour_rate_yen,p_night_hour_rate_yen
  )
$$;

revoke all on function private.partner_payment_settings_workspace()
from public,anon,authenticated;
revoke all on function private.save_partner_payment_setting(uuid,integer,integer,integer,integer)
from public,anon,authenticated;

revoke all on function public.partner_payment_settings_workspace()
from public,anon;
revoke all on function public.save_partner_payment_setting(uuid,integer,integer,integer,integer)
from public,anon;

grant execute on function public.partner_payment_settings_workspace()
to authenticated;
grant execute on function public.save_partner_payment_setting(uuid,integer,integer,integer,integer)
to authenticated;
