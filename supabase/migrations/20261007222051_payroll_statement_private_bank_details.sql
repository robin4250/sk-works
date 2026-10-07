-- Retain existing self-only calculation RPC and join only its worker/company bank row.
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
    order by b.updated_at desc nulls last
    limit 1
  ) bank on true
  where w.user_id = v_user_id
  order by ps.period_end desc;
end;
$function$;

revoke execute on function public.my_payroll_statement_rows_with_adjustments() from public,anon;
grant execute on function public.my_payroll_statement_rows_with_adjustments() to authenticated;
