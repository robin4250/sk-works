-- Unlimited named custom deductions for individual payroll settings.
alter table public.worker_payroll_settings
  add column if not exists custom_deductions jsonb not null default '[]'::jsonb;

alter table public.worker_payroll_settings
  drop constraint if exists worker_payroll_settings_custom_deductions_array_check;

alter table public.worker_payroll_settings
  add constraint worker_payroll_settings_custom_deductions_array_check
  check (jsonb_typeof(custom_deductions)='array');

create or replace function private.apply_payroll_custom_deductions()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  settings jsonb := '{}'::jsonb;
  custom_total integer := 0;
  fixed_total integer := 0;
  normalized jsonb := '[]'::jsonb;
  item jsonb;
  item_name text;
  item_amount integer;
begin
  if not new.automatic_calculation or new.workflow_state <> 'draft' then
    return new;
  end if;

  select coalesce(to_jsonb(s),'{}'::jsonb)
  into settings
  from public.worker_payroll_settings s
  where s.company_id=new.company_id
    and s.worker_id=new.worker_id;

  fixed_total :=
      round(coalesce((settings->>'income_tax_monthly')::numeric,0))::integer
    + round(coalesce((settings->>'resident_tax_monthly')::numeric,0))::integer
    + round(coalesce((settings->>'social_insurance_monthly')::numeric,0))::integer
    + round(coalesce((settings->>'other_deduction_monthly')::numeric,0))::integer;

  if jsonb_typeof(settings->'custom_deductions')='array' then
    for item in
      select value
      from jsonb_array_elements(settings->'custom_deductions')
    loop
      item_name := nullif(trim(item->>'name'),'');
      item_amount := greatest(coalesce((item->>'amount_yen')::integer,0),0);
      if item_name is null or item_amount <= 0 then
        continue;
      end if;
      custom_total := custom_total + item_amount;
      normalized := normalized || jsonb_build_array(
        jsonb_build_object(
          'name', item_name,
          'amount_yen', item_amount
        )
      );
    end loop;
  end if;

  new.deductions := greatest(fixed_total + custom_total,0);
  new.net_pay := greatest(new.gross_pay - new.deductions,0);
  new.detail := coalesce(new.detail,'{}'::jsonb)
    || jsonb_build_object('custom_deductions', normalized);

  return new;
end
$$;

drop trigger if exists payroll_custom_deductions_guard
on public.payroll_statements;

create trigger payroll_custom_deductions_guard
before insert or update of gross_pay,deductions,detail,automatic_calculation,workflow_state
on public.payroll_statements
for each row
execute function private.apply_payroll_custom_deductions();

-- Recalculate current automatic drafts immediately.
update public.payroll_statements ps
set updated_at=now()
where ps.automatic_calculation
  and ps.workflow_state='draft';
