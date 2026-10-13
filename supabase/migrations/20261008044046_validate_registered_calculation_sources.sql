-- Preserve existing owner/admin/manager authorization and refresh behavior.
-- Only registered tenant/site/party associations may be saved.
CREATE OR REPLACE FUNCTION private.select_site_calculation_source(p_site_id uuid, p_output_type text, p_trade_company_id uuid, p_source text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  cid uuid;
  v_customer uuid;
  v_day date;
  r record;
begin
  cid:=private.current_company_admin_id();
  if cid is null then raise exception '管理者のみ操作できます。'; end if;
  if p_output_type not in ('invoice','payment_certificate','payroll') then
    raise exception '計算対象を確認してください。';
  end if;
  if p_source not in ('site','trade_company') then
    raise exception '計算元を選択してください。';
  end if;
  if not exists(select 1 from public.sites s where s.id=p_site_id and s.company_id=cid) then
    raise exception '現場が見つかりません。';
  end if;
  -- Every saved association must belong to this tenant, including a site choice.
  if not exists(select 1 from public.trade_companies tc
      where tc.id=p_trade_company_id and tc.company_id=cid) then
    raise exception '取引会社が見つかりません。';
  end if;
  if not exists(
    select 1 from public.trade_companies tc
    join public.sites s on s.id=p_site_id and s.company_id=tc.company_id
    where tc.id=p_trade_company_id and tc.company_id=cid
      and case when p_output_type='invoice' then
        tc.trade_role in ('customer','both') and tc.customer_id is not null
        and s.customer_id=tc.customer_id
        and exists(select 1 from public.customers c
          where c.id=tc.customer_id and c.company_id=cid)
      else
        tc.trade_role in ('subcontractor','both') and tc.partner_company_id is not null
        -- Subcontractor settings may be selected before the first attendance.
        -- There is no registered site-to-partner mapping; validate the actual
        -- tenant-owned partner master rather than inventing an attendance prerequisite.
        and exists(select 1 from public.partner_companies pc
          where pc.id=tc.partner_company_id and pc.company_id=cid)
      end
  ) then
    raise exception 'この現場・帳票に登録された取引会社を選択してください。';
  end if;

  insert into public.site_calculation_source_preferences(
    company_id,site_id,output_type,trade_company_id,source,selected_by,selected_at
  )
  values(cid,p_site_id,p_output_type,p_trade_company_id,p_source,auth.uid(),now())
  on conflict(company_id,site_id,output_type) do update
  set trade_company_id=excluded.trade_company_id,
      source=excluded.source,
      selected_by=auth.uid(),
      selected_at=now();

  select s.customer_id into v_customer
  from public.sites s
  where s.id=p_site_id and s.company_id=cid;

  for r in
    select distinct ae.work_date
    from public.attendance_entries ae
    where ae.company_id=cid and ae.site_id=p_site_id
  loop
    v_day:=r.work_date;
    if p_output_type='invoice' then
      perform private.refresh_automatic_invoice(cid,v_customer,v_day);
    elsif p_output_type='payment_certificate' then
      for r in
        select distinct w.partner_company_id as partner_id
        from public.attendance_entries ae
        join public.workers w on w.id=ae.worker_id and w.company_id=ae.company_id
        where ae.company_id=cid and ae.site_id=p_site_id
          and w.partner_company_id is not null
          and date_trunc('month',ae.work_date)=date_trunc('month',v_day)
      loop
        perform private.refresh_automatic_payment_certificate(cid,r.partner_id,v_day);
      end loop;
    elsif p_output_type='payroll' then
      for r in
        select distinct ae.worker_id
        from public.attendance_entries ae
        where ae.company_id=cid and ae.site_id=p_site_id
          and date_trunc('month',ae.work_date)=date_trunc('month',v_day)
      loop
        perform private.refresh_automatic_payroll(cid,r.worker_id,v_day);
      end loop;
    end if;
  end loop;
end
$function$
;

CREATE OR REPLACE FUNCTION private.trade_company_calculation_conflicts(p_trade_company_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
      select s.id as site_id,s.name as site_name,s.customer_id,
        exists(select 1 from public.attendance_entries ae
          join public.workers w on w.id=ae.worker_id and w.company_id=ae.company_id
          where ae.company_id=cid and ae.site_id=s.id
            and w.partner_company_id=tc.partner_company_id) as has_partner
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
      where tc.trade_role in ('customer','both') and rs.customer_id=tc.customer_id
      union all
      select rs.site_id,rs.site_name,'payment_certificate'::text
      from relevant_sites rs
      where tc.trade_role in ('subcontractor','both') and rs.has_partner
      union all
      select rs.site_id,rs.site_name,'payroll'::text
      from relevant_sites rs
      where tc.trade_role in ('subcontractor','both') and rs.has_partner
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
              or coalesce(fs.billing_monthly_rate_yen,0)>0
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
              or coalesce(fs.billing_monthly_rate_yen,0)>0
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
$function$
;
revoke all on function private.select_site_calculation_source(uuid,text,uuid,text) from public,anon,authenticated;
revoke all on function private.trade_company_calculation_conflicts(uuid) from public,anon,authenticated;
