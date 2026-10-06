-- Move payroll statement optional earnings/deductions to flexible named lists
-- and store the individual payment day used by the statement header.

alter table public.worker_payroll_settings
  add column if not exists custom_earnings jsonb not null default '[]'::jsonb,
  add column if not exists payment_day integer not null default 25;

alter table public.worker_payroll_settings
  drop constraint if exists worker_payroll_settings_custom_earnings_array_check,
  drop constraint if exists worker_payroll_settings_payment_day_check;

alter table public.worker_payroll_settings
  add constraint worker_payroll_settings_custom_earnings_array_check
    check (jsonb_typeof(custom_earnings)='array'),
  add constraint worker_payroll_settings_payment_day_check
    check (payment_day between 1 and 31);

-- Seed the currently displayed optional statement labels into the flexible lists.
update public.worker_payroll_settings s
set custom_earnings =
      coalesce(s.custom_earnings,'[]'::jsonb)
      || case when not exists (
           select 1 from jsonb_array_elements(coalesce(s.custom_earnings,'[]'::jsonb)) x
           where x->>'name'='勤続手当'
         ) then jsonb_build_array(jsonb_build_object('name','勤続手当','amount_yen',0))
         else '[]'::jsonb end
      || case when not exists (
           select 1 from jsonb_array_elements(coalesce(s.custom_earnings,'[]'::jsonb)) x
           where x->>'name'='役職手当'
         ) then jsonb_build_array(jsonb_build_object('name','役職手当','amount_yen',0))
         else '[]'::jsonb end
      || case when not exists (
           select 1 from jsonb_array_elements(coalesce(s.custom_earnings,'[]'::jsonb)) x
           where x->>'name'='家族手当'
         ) then jsonb_build_array(jsonb_build_object(
           'name','家族手当',
           'amount_yen',round(coalesce(s.family_monthly,0))::integer
         ))
         else '[]'::jsonb end
      || case when not exists (
           select 1 from jsonb_array_elements(coalesce(s.custom_earnings,'[]'::jsonb)) x
           where x->>'name'='働き方手当'
         ) then jsonb_build_array(jsonb_build_object('name','働き方手当','amount_yen',0))
         else '[]'::jsonb end,
    custom_deductions =
      coalesce(s.custom_deductions,'[]'::jsonb)
      || case when not exists (
           select 1 from jsonb_array_elements(coalesce(s.custom_deductions,'[]'::jsonb)) x
           where x->>'name'='介護保険料'
         ) then jsonb_build_array(jsonb_build_object('name','介護保険料','amount_yen',0))
         else '[]'::jsonb end
      || case when not exists (
           select 1 from jsonb_array_elements(coalesce(s.custom_deductions,'[]'::jsonb)) x
           where x->>'name'='厚生年金保険'
         ) then jsonb_build_array(jsonb_build_object('name','厚生年金保険','amount_yen',0))
         else '[]'::jsonb end
      || case when not exists (
           select 1 from jsonb_array_elements(coalesce(s.custom_deductions,'[]'::jsonb)) x
           where x->>'name'='雇用保険料'
         ) then jsonb_build_array(jsonb_build_object('name','雇用保険料','amount_yen',0))
         else '[]'::jsonb end
      || case when not exists (
           select 1 from jsonb_array_elements(coalesce(s.custom_deductions,'[]'::jsonb)) x
           where x->>'name'='SKO会費'
         ) then jsonb_build_array(jsonb_build_object('name','SKO会費','amount_yen',0))
         else '[]'::jsonb end,
    family_monthly=0;

create or replace function private.apply_payroll_custom_money()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  settings jsonb := '{}'::jsonb;
  custom_earnings_total integer := 0;
  custom_deductions_total integer := 0;
  previous_earnings_total integer := 0;
  fixed_deductions_total integer := 0;
  normalized_earnings jsonb := '[]'::jsonb;
  normalized_deductions jsonb := '[]'::jsonb;
  item jsonb;
  item_name text;
  item_amount integer;
  payment_day integer := 25;
begin
  if not new.automatic_calculation or new.workflow_state <> 'draft' then
    return new;
  end if;

  select coalesce(to_jsonb(s),'{}'::jsonb)
  into settings
  from public.worker_payroll_settings s
  where s.company_id=new.company_id
    and s.worker_id=new.worker_id;

  payment_day := greatest(
    least(coalesce((settings->>'payment_day')::integer,25),31),
    1
  );

  if tg_op='UPDATE' then
    previous_earnings_total :=
      coalesce((old.detail->>'custom_earnings_total')::integer,0);
  end if;

  if jsonb_typeof(settings->'custom_earnings')='array' then
    for item in
      select value
      from jsonb_array_elements(settings->'custom_earnings')
    loop
      item_name := nullif(trim(item->>'name'),'');
      item_amount := greatest(coalesce((item->>'amount_yen')::integer,0),0);
      if item_name is null then continue; end if;
      normalized_earnings := normalized_earnings || jsonb_build_array(
        jsonb_build_object('name',item_name,'amount_yen',item_amount)
      );
      custom_earnings_total := custom_earnings_total + item_amount;
    end loop;
  end if;

  if jsonb_typeof(settings->'custom_deductions')='array' then
    for item in
      select value
      from jsonb_array_elements(settings->'custom_deductions')
    loop
      item_name := nullif(trim(item->>'name'),'');
      item_amount := greatest(coalesce((item->>'amount_yen')::integer,0),0);
      if item_name is null then continue; end if;
      normalized_deductions := normalized_deductions || jsonb_build_array(
        jsonb_build_object('name',item_name,'amount_yen',item_amount)
      );
      custom_deductions_total := custom_deductions_total + item_amount;
    end loop;
  end if;

  fixed_deductions_total :=
      round(coalesce((settings->>'income_tax_monthly')::numeric,0))::integer
    + round(coalesce((settings->>'resident_tax_monthly')::numeric,0))::integer
    + round(coalesce((settings->>'social_insurance_monthly')::numeric,0))::integer
    + round(coalesce((settings->>'other_deduction_monthly')::numeric,0))::integer;

  new.gross_pay := greatest(
    coalesce(new.gross_pay,0) - previous_earnings_total + custom_earnings_total,
    0
  );
  new.deductions := greatest(
    fixed_deductions_total + custom_deductions_total,
    0
  );
  new.net_pay := greatest(new.gross_pay - new.deductions,0);
  new.detail := (
    coalesce(new.detail,'{}'::jsonb)
      - '勤続手当'
      - '役職手当'
      - '家族手当'
      - '働き方手当'
      - '介護保険料'
      - '厚生年金保険'
      - '雇用保険料'
      - 'SKB会費'
  ) || jsonb_build_object(
    'custom_earnings',normalized_earnings,
    'custom_deductions',normalized_deductions,
    'custom_earnings_total',custom_earnings_total,
    '支払日',payment_day
  );

  return new;
end
$$;

drop trigger if exists payroll_custom_deductions_guard
on public.payroll_statements;
drop function if exists private.apply_payroll_custom_deductions();

drop trigger if exists payroll_custom_money_guard
on public.payroll_statements;
create trigger payroll_custom_money_guard
before insert or update of gross_pay,deductions,detail,automatic_calculation,workflow_state
on public.payroll_statements
for each row
execute function private.apply_payroll_custom_money();

-- Re-run current automatic drafts through the new normalization without
-- changing finalized historical statements.
update public.payroll_statements
set detail=coalesce(detail,'{}'::jsonb)
where automatic_calculation
  and workflow_state='draft';
