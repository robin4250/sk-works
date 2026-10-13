-- Normalize the displayed company-fee label to the current SKO wording.
update public.worker_payroll_settings s
set custom_deductions = coalesce((
  select jsonb_agg(
    jsonb_build_object('name',q.name,'amount_yen',q.amount_yen)
    order by q.first_pos
  )
  from (
    select
      case when x.value->>'name'='SKB会費'
        then 'SKO会費'
        else x.value->>'name'
      end as name,
      sum(greatest(coalesce((x.value->>'amount_yen')::integer,0),0))::integer
        as amount_yen,
      min(x.ordinality) as first_pos
    from jsonb_array_elements(coalesce(s.custom_deductions,'[]'::jsonb))
      with ordinality as x(value, ordinality)
    where nullif(trim(x.value->>'name'),'') is not null
    group by
      case when x.value->>'name'='SKB会費'
        then 'SKO会費'
        else x.value->>'name'
      end
  ) q
),'[]'::jsonb);

update public.payroll_statements
set detail=coalesce(detail,'{}'::jsonb)
where automatic_calculation
  and workflow_state='draft';
