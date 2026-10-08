-- Depends on registered employee identity and company payroll confirmation policy migrations.
create function private.payroll_document_metadata(p_statement_id uuid) returns jsonb
language sql stable security definer set search_path='' as $$
 select jsonb_build_object(
 'pay_type',case
 when coalesce(nullif(ps.detail->>'pay_type',''),nullif(ps.detail->>'給与形態',''),nullif(ps.detail->>'給与方式','')) in ('monthly','月給') then 'monthly'
 when coalesce(nullif(ps.detail->>'pay_type',''),nullif(ps.detail->>'給与形態',''),nullif(ps.detail->>'給与方式','')) in ('hourly','時給') then 'hourly'
 when coalesce(nullif(ps.detail->>'pay_type',''),nullif(ps.detail->>'給与形態',''),nullif(ps.detail->>'給与方式','')) in ('daily','日給') then 'daily'
 else coalesce(pay_settings.pay_type,'daily') end,
 'rate_formula',coalesce(nullif(ps.detail->'rate_formula','null'::jsonb),pay_settings.rate_formula,'{}'::jsonb),
 'hourly_rate_yen',coalesce(nullif(ps.detail->'hourly_rate_yen','null'::jsonb),to_jsonb(pay_settings.hourly_rate_yen),'0'::jsonb),
 '社員番号',coalesce(nullif(ps.detail->>'社員番号',''),w.employee_number,''),
 '所属',coalesce(nullif(ps.detail->>'所属',''),w.department,''),
 '職種',coalesce(nullif(ps.detail->>'職種',''),w.role,''),
 '入社日',coalesce(nullif(ps.detail->>'入社日',''),w.hire_date::text,''),
 'payment_date',private.payroll_payment_date(ps.period_end,ps.company_id,case when ps.workflow_state='draft' then '{}'::jsonb else ps.detail end),
 '支払日',c.payroll_payment_day,
 'payroll_confirmations',coalesce((select jsonb_agg(jsonb_build_object('user_id',pc.user_id,'name',coalesce(nullif(up.display_name,''),'SKOユーザー'),'position',pc.position,
 'confirmed_at',case when rv.confirmed_revision=ps.revision then rv.confirmed_at end) order by pc.position)
 from public.payroll_confirmers pc left join public.user_profiles up on up.user_id=pc.user_id left join public.payroll_statement_reviews rv on rv.statement_id=ps.id and rv.reviewer_id=pc.user_id
 where pc.company_id=ps.company_id),'[]'::jsonb))
 from public.payroll_statements ps join public.workers w on w.id=ps.worker_id and w.company_id=ps.company_id join public.companies c on c.id=ps.company_id left join public.worker_payroll_settings pay_settings on pay_settings.worker_id=ps.worker_id and pay_settings.company_id=ps.company_id where ps.id=p_statement_id
$$;
revoke all on function private.payroll_document_metadata(uuid) from public,anon,authenticated;

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
      || jsonb_build_object('bank_account',coalesce(bank.bank_detail,'{}'::jsonb))
      || private.payroll_document_metadata(ps.id),
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


-- The existing manager visibility predicate is unchanged.
create or replace function private.payroll_review_workspace(p_period_start date default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  uid uuid:=auth.uid();
  cid uuid;
  role_text text;
  v_period_start date:=coalesce(
    p_period_start,
    date_trunc('month',(current_timestamp at time zone 'Asia/Tokyo')::date)::date
  );
  result jsonb;
begin
  if not private.account_access_allowed() then raise exception 'ログインが必要です'; end if;

  select cm.company_id,cm.role::text into cid,role_text
  from public.company_members cm
  where cm.user_id=uid
  limit 1;

  if cid is null then raise exception '会社への所属が必要です'; end if;
  if role_text not in ('owner','admin','manager','viewer') then
    raise exception '給料一覧を閲覧する権限がありません';
  end if;

  select jsonb_build_object(
    'role',role_text,
    'is_admin',role_text in ('owner','admin'),
    'can_confirm',exists(select 1 from public.payroll_confirmers pc where pc.company_id=cid and pc.user_id=uid) and (current_timestamp at time zone 'Asia/Tokyo')::date >= (v_period_start+interval '1 month - 1 day')::date,
    'period_start',v_period_start,
    'company_name',(select c.name from public.companies c where c.id=cid),
    'workers',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',w.id,
        'name',w.name,
        'visible_to_manager',coalesce(v.visible_to_manager,false)
      ) order by w.name)
      from public.workers w
      left join public.payroll_manager_worker_visibility v
        on v.company_id=w.company_id and v.worker_id=w.id
      where w.company_id=cid
        and w.status='active'
        and w.affiliation::text='employee'
    ),'[]'::jsonb),
    'statements',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',ps.id,
        'worker_id',ps.worker_id,
        'worker_name',w.name,
        'period_start',ps.period_start,
        'period_end',ps.period_end,
        'gross_pay',ps.gross_pay+coalesce(adj.additions_yen,0),
        'deductions',ps.deductions+coalesce(adj.deductions_yen,0),
        'net_pay',ps.gross_pay+coalesce(adj.additions_yen,0)
          -ps.deductions-coalesce(adj.deductions_yen,0),
        'detail',coalesce(ps.detail,'{}'::jsonb)
          ||coalesce(adj.adjustment_detail,'{}'::jsonb)||private.payroll_document_metadata(ps.id),
        'revision',ps.revision,
        'workflow_state',ps.workflow_state,
        'review_checked',coalesce(rv.checked_revision=ps.revision,false),
        'review_confirmed',coalesce(private.payroll_confirmed_all(ps.id),false),
        'reviewer_confirmed',coalesce(rv.confirmed_revision=ps.revision,false)
      ) order by w.name)
      from public.payroll_statements ps
      join public.workers w
        on w.id=ps.worker_id and w.company_id=ps.company_id
      left join public.payroll_manager_worker_visibility v
        on v.company_id=ps.company_id and v.worker_id=ps.worker_id
      left join public.payroll_statement_reviews rv
        on rv.statement_id=ps.id and rv.reviewer_id=uid
      left join lateral (
        with active as (
          select a.label_snapshot,a.direction,a.amount_yen
          from public.payroll_adjustments a
          where a.company_id=ps.company_id
            and a.worker_id=ps.worker_id
            and a.effective_date between ps.period_start and ps.period_end
            and a.cancelled_at is null
        ),
        totals as (
          select
            coalesce(sum(case when direction='addition' then amount_yen else 0 end),0)::integer additions_yen,
            coalesce(sum(case when direction='deduction' then amount_yen else 0 end),0)::integer deductions_yen
          from active
        ),
        grouped as (
          select label_snapshot,
            sum(case when direction='addition' then amount_yen else -amount_yen end)::integer signed_total
          from active
          group by label_snapshot
        )
        select t.additions_yen,t.deductions_yen,
          coalesce(
            (select jsonb_object_agg(g.label_snapshot,g.signed_total) from grouped g),
            '{}'::jsonb
          ) adjustment_detail
        from totals t
      ) adj on true
      where ps.company_id=cid
        and ps.period_start=v_period_start
        and w.affiliation::text='employee'
        and (
          role_text in ('owner','admin','viewer')
          or (role_text='manager' and coalesce(v.visible_to_manager,false))
        )
    ),'[]'::jsonb)
  ) into result;

  return result;
end;
$function$;


