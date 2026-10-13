-- Preserve historical pay-mode metadata; enrich only the current user worker/company RPC.
CREATE OR REPLACE FUNCTION public.my_payroll_statement_rows_with_adjustments()
 RETURNS TABLE(id uuid, period_start date, period_end date, gross_pay integer, deductions integer, net_pay integer, detail jsonb, issued_at timestamp with time zone, company_name text, worker_name text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then
    raise exception 'authentication required';
  end if;

  return query
  select
    ps.id,
    ps.period_start,
    ps.period_end,
    ps.gross_pay + coalesce(adj.additions_yen, 0),
    ps.deductions + coalesce(adj.deductions_yen, 0),
    (
      ps.gross_pay
      + coalesce(adj.additions_yen, 0)
      - ps.deductions
      - coalesce(adj.deductions_yen, 0)
    )::integer,
    coalesce(ps.detail, '{}'::jsonb)
      || jsonb_build_object(
        'pay_type',case
          when coalesce(nullif(ps.detail->>'pay_type',''),nullif(ps.detail->>'給与形態',''),nullif(ps.detail->>'給与方式','')) in ('monthly','月給') then 'monthly'
          when coalesce(nullif(ps.detail->>'pay_type',''),nullif(ps.detail->>'給与形態',''),nullif(ps.detail->>'給与方式','')) in ('hourly','時給') then 'hourly'
          when coalesce(nullif(ps.detail->>'pay_type',''),nullif(ps.detail->>'給与形態',''),nullif(ps.detail->>'給与方式','')) in ('daily','日給') then 'daily'
          else coalesce(pay_settings.pay_type,'daily') end,
        'rate_formula',coalesce(nullif(ps.detail->'rate_formula','null'::jsonb),pay_settings.rate_formula,'{}'::jsonb),
        'hourly_rate_yen',coalesce(nullif(ps.detail->'hourly_rate_yen','null'::jsonb),to_jsonb(pay_settings.hourly_rate_yen),'0'::jsonb)
      )
      || coalesce(adj.adjustment_detail, '{}'::jsonb)
      || jsonb_build_object('bank_account',coalesce(bank.bank_detail,'{}'::jsonb)),
    ps.issued_at,
    c.name,
    w.name
  from public.payroll_statements ps
  join public.workers w
    on w.id = ps.worker_id
   and w.company_id = ps.company_id
  join public.companies c
    on c.id = ps.company_id
  left join public.worker_payroll_settings pay_settings
    on pay_settings.worker_id=ps.worker_id and pay_settings.company_id=ps.company_id
  left join lateral (
    with active as (
      select
        a.label_snapshot,
        a.direction,
        a.amount_yen
      from public.payroll_adjustments a
      where a.company_id = ps.company_id
        and a.worker_id = ps.worker_id
        and a.effective_date between ps.period_start and ps.period_end
        and a.cancelled_at is null
    ),
    totals as (
      select
        coalesce(
          sum(case when direction = 'addition' then amount_yen else 0 end),
          0
        )::integer as additions_yen,
        coalesce(
          sum(case when direction = 'deduction' then amount_yen else 0 end),
          0
        )::integer as deductions_yen
      from active
    ),
    grouped as (
      select
        label_snapshot,
        sum(
          case
            when direction = 'addition' then amount_yen
            else -amount_yen
          end
        )::integer as signed_total
      from active
      group by label_snapshot
    )
    select
      t.additions_yen,
      t.deductions_yen,
      coalesce(
        (
          select jsonb_object_agg(g.label_snapshot, g.signed_total)
          from grouped g
        ),
        '{}'::jsonb
      ) as adjustment_detail
    from totals t
  ) adj on true
  left join lateral (
    select jsonb_build_object(
      'bank_name',b.bank_name,'branch_name',b.branch_name,
      'account_type',b.account_type,'account_number',b.account_number,
      'account_holder',b.account_holder
    ) as bank_detail
    from public.worker_private_bank_accounts b
    where b.worker_id=ps.worker_id and b.company_id=ps.company_id
      and private.account_access_allowed()
    order by b.updated_at desc nulls last
    limit 1
  ) bank on true
  where w.user_id = v_user_id
  order by ps.period_end desc;
end;
$function$;

revoke execute on function public.my_payroll_statement_rows_with_adjustments() from public,anon;
grant execute on function public.my_payroll_statement_rows_with_adjustments() to authenticated;

CREATE OR REPLACE FUNCTION private.refresh_automatic_payroll(cid uuid, wid uuid, day date)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  start_day date:=date_trunc('month',day)::date;
  end_day date:=(date_trunc('month',day)+interval '1 month - 1 day')::date;
  settings jsonb; a record; current_statement public.payroll_statements%rowtype;
  total numeric:=0; v_deductions numeric:=0; v_custom_deductions numeric:=0; count_rows int:=0;
  category text; allowance text; allowance_index int; seen text[]:='{}'; token text;
  line_detail jsonb; fingerprint text; saved_id uuid; saved_revision int;
  pref record;
  fixed_trade_seen uuid[]:='{}';
  trade_amount numeric;
begin
  if auth.uid() is null then return; end if;
  perform pg_advisory_xact_lock(hashtextextended(cid::text||wid::text||start_day::text,0));
  select * into current_statement
  from public.payroll_statements
  where company_id=cid and worker_id=wid and period_start=start_day and period_end=end_day
  for update;
  if found and (not current_statement.automatic_calculation or current_statement.workflow_state<>'draft') then return; end if;

  select to_jsonb(s) into settings
  from public.worker_payroll_settings s
  where s.company_id=cid and s.worker_id=wid;

  select md5(
    coalesce((settings-'updated_at')::text,'')||
    coalesce((
      select jsonb_agg(to_jsonb(ae)-'updated_at'-'created_at' order by ae.work_date,ae.id)::text
      from public.attendance_entries ae
      where ae.company_id=cid and ae.worker_id=wid
        and ae.work_date between start_day and end_day
        and ae.work_date<=(current_timestamp at time zone 'Asia/Tokyo')::date
    ),'')||
    coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'site_id',scsp.site_id,'source',scsp.source,
          'trade_company_id',scsp.trade_company_id,
          'contract',to_jsonb(ct)-'updated_at'
        )
        order by scsp.site_id
      )::text
      from public.site_calculation_source_preferences scsp
      left join public.trade_company_contracts ct
        on ct.company_id=scsp.company_id and ct.trade_company_id=scsp.trade_company_id
      where scsp.company_id=cid and scsp.output_type='payroll'
    ),'')
  )
  into fingerprint;

  for a in
    select ae.*
    from public.attendance_entries ae
    where ae.company_id=cid and ae.worker_id=wid
      and ae.work_date between start_day and end_day
      and ae.work_date<=(current_timestamp at time zone 'Asia/Tokyo')::date
    order by ae.work_date,ae.id
  loop
    count_rows:=count_rows+1;
    trade_amount:=0;
    pref:=null;

    select scsp.source,tc.id as trade_company_id,
           coalesce(ct.contract_method,'none') as contract_method,
           coalesce(ct.daily_rate_yen,0) as daily_rate_yen,
           coalesce(ct.monthly_rate_yen,0) as monthly_rate_yen,
           coalesce(ct.square_meter_unit_price_yen,0) as square_meter_unit_price_yen,
           coalesce(ct.square_meter_quantity,0) as square_meter_quantity,
           coalesce(ct.contract_amount_yen,0) as contract_amount_yen
    into pref
    from public.site_calculation_source_preferences scsp
    join public.trade_companies tc
      on tc.id=scsp.trade_company_id and tc.company_id=cid
    left join public.trade_company_contracts ct
      on ct.company_id=cid and ct.trade_company_id=tc.id
    where scsp.company_id=cid and scsp.site_id=a.site_id
      and scsp.output_type='payroll'
    limit 1;

    if pref.source='trade_company' then
      if pref.contract_method='daily' then
        trade_amount:=round(coalesce(a.base_man_days,0)*pref.daily_rate_yen);
      elsif pref.contract_method='monthly' then
        if not pref.trade_company_id=any(fixed_trade_seen) then
          fixed_trade_seen:=array_append(fixed_trade_seen,pref.trade_company_id);
          trade_amount:=pref.monthly_rate_yen;
        end if;
      elsif pref.contract_method='square_meter' then
        if not pref.trade_company_id=any(fixed_trade_seen) then
          fixed_trade_seen:=array_append(fixed_trade_seen,pref.trade_company_id);
          trade_amount:=round(pref.square_meter_quantity*pref.square_meter_unit_price_yen);
        end if;
      elsif pref.contract_method='contract' then
        if not pref.trade_company_id=any(fixed_trade_seen) then
          fixed_trade_seen:=array_append(fixed_trade_seen,pref.trade_company_id);
          trade_amount:=pref.contract_amount_yen;
        end if;
      end if;
      total:=total+trade_amount;
    else
      category:=a.work_category;
      total:=total
        + round(coalesce(a.base_man_days,0) * coalesce((settings->>(category||'_daily'))::numeric,0))
        + round(coalesce(a.overtime_hours,0) * coalesce((settings->>(category||'_overtime'))::numeric,0))
        + round(coalesce(a.early_hours,0) * coalesce((settings->>(category||'_early'))::numeric,0));
    end if;

    foreach allowance in array coalesce(a.allowance_names,'{}'::text[]) loop
      token:=a.work_date::text||':'||allowance;
      if token=any(seen) then continue; end if;
      seen:=array_append(seen,token);
      allowance_index:=null;
      if settings is not null then
        select min(i) into allowance_index
        from generate_series(1,3)i
        where nullif(trim(settings->>('allowance_name_'||i)),'')=allowance;
      end if;
      if allowance_index is not null then
        total:=total+round(coalesce((settings->>('allowance_'||allowance_index))::numeric,0));
      end if;
    end loop;
  end loop;

  if count_rows=0 then
    if current_statement.id is not null and current_statement.workflow_state='draft' and current_statement.automatic_calculation then
      delete from public.payroll_statements where id=current_statement.id;
    end if;
    return;
  end if;

  if settings is not null then
    total:=total+round(coalesce((settings->>'family_monthly')::numeric,0))
      +round(coalesce((settings->>'transport_monthly')::numeric,0));
    select coalesce(sum(greatest(coalesce((item->>'amount_yen')::numeric,0),0)),0)
    into v_custom_deductions
    from jsonb_array_elements(coalesce(settings->'custom_deductions','[]'::jsonb)) item
    where nullif(trim(item->>'name'),'') is not null;

    v_deductions:=round(coalesce((settings->>'income_tax_monthly')::numeric,0))
      +round(coalesce((settings->>'resident_tax_monthly')::numeric,0))
      +round(coalesce((settings->>'social_insurance_monthly')::numeric,0))
      +round(coalesce((settings->>'other_deduction_monthly')::numeric,0))
      +round(v_custom_deductions);
  end if;

  total:=greatest(coalesce(total,0),0);
  v_deductions:=greatest(coalesce(v_deductions,0),0);
  -- Capture the calculation settings with the generated draft; history is not relabeled later.
  line_detail:=jsonb_build_object(
    'pay_type',coalesce(settings->>'pay_type','daily'),
    'rate_formula',coalesce(settings->'rate_formula','{}'::jsonb),
    'hourly_rate_yen',coalesce(settings->'hourly_rate_yen','0'::jsonb),
    '出勤に基づく支給額',greatest(total-v_deductions,0),
    '計算元選択あり',exists(
      select 1 from public.site_calculation_source_preferences scsp
      where scsp.company_id=cid and scsp.output_type='payroll'
        and scsp.source='trade_company'
        and exists(
          select 1 from public.attendance_entries ae
          where ae.company_id=cid and ae.worker_id=wid
            and ae.site_id=scsp.site_id
            and ae.work_date between start_day and end_day
        )
    )
  );

  if current_statement.id is null then
    insert into public.payroll_statements(
      company_id,worker_id,period_start,period_end,gross_pay,deductions,net_pay,
      detail,workflow_state,approver_ids,automatic_calculation,calculation_blocked,calculation_fingerprint
    )
    values(
      cid,wid,start_day,end_day,total::int,v_deductions::int,greatest(total-v_deductions,0)::int,
      line_detail,'draft',private.payroll_approver_ids(cid),true,false,fingerprint
    )
    returning id,revision into saved_id,saved_revision;
  elsif current_statement.gross_pay is distinct from total::int
      or current_statement.deductions is distinct from v_deductions::int
      or current_statement.net_pay is distinct from greatest(total-v_deductions,0)::int
      or current_statement.detail is distinct from line_detail
      or current_statement.calculation_fingerprint is distinct from fingerprint
      or current_statement.calculation_blocked then
    update public.payroll_statements
    set gross_pay=total::int,
        deductions=v_deductions::int,
        net_pay=greatest(total-v_deductions,0)::int,
        detail=line_detail,
        calculation_fingerprint=fingerprint,
        calculation_blocked=false,
        approved_ids='{}',
        revision=revision+1,
        updated_at=now()
    where id=current_statement.id
    returning id,revision into saved_id,saved_revision;
  end if;

  if saved_id is not null then
    insert into public.payroll_audit(company_id,statement_id,revision,action,actor_id)
    values(cid,saved_id,saved_revision,'automatic_recalculation',auth.uid());
  end if;
end;
$function$;
