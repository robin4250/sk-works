-- Mirrors production migration 20261004132201.
create or replace function private.trade_company_calculation_conflicts(p_trade_company_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare cid uuid; tc public.trade_companies%rowtype;
begin
  cid:=private.current_company_admin_id();
  if cid is null then raise exception '管理者のみ操作できます。'; end if;
  select * into tc
  from public.trade_companies
  where id=p_trade_company_id and company_id=cid;
  if tc.id is null then raise exception '取引会社が見つかりません。'; end if;

  return coalesce((
    with relevant_sites as (
      select s.id as site_id,s.name as site_name
      from public.sites s
      where s.company_id=cid
        and (
          (tc.customer_id is not null and s.customer_id=tc.customer_id)
          or
          (tc.partner_company_id is not null and exists(
            select 1
            from public.attendance_entries ae
            join public.workers w
              on w.id=ae.worker_id and w.company_id=ae.company_id
            where ae.company_id=cid
              and ae.site_id=s.id
              and w.partner_company_id=tc.partner_company_id
          ))
        )
    ),
    outputs as (
      select rs.site_id,rs.site_name,'invoice'::text as output_type
      from relevant_sites rs
      where tc.trade_role in ('customer','both')
      union all
      select rs.site_id,rs.site_name,'payment_certificate'::text
      from relevant_sites rs
      where tc.trade_role in ('subcontractor','both')
      union all
      select rs.site_id,rs.site_name,'payroll'::text
      from relevant_sites rs
      where tc.trade_role in ('subcontractor','both')
    )
    select jsonb_agg(
      jsonb_build_object(
        'site_id',o.site_id,
        'site_name',o.site_name,
        'output_type',o.output_type,
        'site_setting_configured',
          case
            when o.output_type='invoice' then
              coalesce(fs.billing_unit_price_yen,0)>0
              or (coalesce(fs.billing_square_meter_unit_price_yen,0)>0
                  and coalesce(fs.billing_square_meter_quantity,0)>0)
              or coalesce(fs.billing_contract_amount_yen,0)>0
            else
              coalesce(fs.worker_daily_rate_yen,0)>0
              or coalesce(fs.overtime_hour_rate_yen,0)>0
              or coalesce(fs.early_hour_rate_yen,0)>0
          end,
        'trade_company_setting_configured',
          coalesce(ct.contract_method,'none')<>'none',
        'conflict',
          (
            coalesce(ct.contract_method,'none')<>'none'
            and
            case
              when o.output_type='invoice' then
                coalesce(fs.billing_unit_price_yen,0)>0
                or (coalesce(fs.billing_square_meter_unit_price_yen,0)>0
                    and coalesce(fs.billing_square_meter_quantity,0)>0)
                or coalesce(fs.billing_contract_amount_yen,0)>0
              else
                coalesce(fs.worker_daily_rate_yen,0)>0
                or coalesce(fs.overtime_hour_rate_yen,0)>0
                or coalesce(fs.early_hour_rate_yen,0)>0
            end
          ),
        'selected_source',pref.source
      )
      order by o.site_name,o.output_type
    )
    from outputs o
    left join public.site_financial_settings fs
      on fs.company_id=cid and fs.site_id=o.site_id
    left join public.trade_company_contracts ct
      on ct.company_id=cid and ct.trade_company_id=tc.id
    left join public.site_calculation_source_preferences pref
      on pref.company_id=cid
      and pref.site_id=o.site_id
      and pref.output_type=o.output_type
      and pref.trade_company_id=tc.id
  ),'[]'::jsonb);
end
$$;

revoke all on function private.trade_company_calculation_conflicts(uuid)
from public,anon,authenticated;

create or replace function public.trade_company_calculation_conflicts(
  p_trade_company_id uuid
)
returns jsonb
language sql
set search_path=''
as $$ select private.trade_company_calculation_conflicts(p_trade_company_id) $$;

revoke all on function public.trade_company_calculation_conflicts(uuid)
from public,anon;
grant execute on function public.trade_company_calculation_conflicts(uuid)
to authenticated;
