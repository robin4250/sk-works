-- Disposable fixture after the assigned-confirmation migration; never production.
begin;
insert into auth.users(id) values
 ('00000000-0000-0000-0000-000000000090'),
 ('00000000-0000-0000-0000-000000000091');
insert into public.companies(id)
values ('10000000-0000-0000-0000-000000000090');
insert into public.company_members(company_id, user_id, role)
values ('10000000-0000-0000-0000-000000000090', '00000000-0000-0000-0000-000000000090', 'viewer');
do $$begin
  if exists(select 1 from public.payroll_confirmers where company_id='10000000-0000-0000-0000-000000000090') then
    raise exception 'viewer seeded a confirmer';
  end if;
end $$;
update public.company_members set role='admin'
where company_id='10000000-0000-0000-0000-000000000090';
do $$begin
  if (select count(*) from public.payroll_confirmers where company_id='10000000-0000-0000-0000-000000000090') <> 1
     or not exists(select 1 from public.payroll_confirmers where company_id='10000000-0000-0000-0000-000000000090' and position=1 and user_id='00000000-0000-0000-0000-000000000090') then
    raise exception 'first administrator default missing';
  end if;
end $$;
insert into public.company_members(company_id,user_id,role)
values ('10000000-0000-0000-0000-000000000090','00000000-0000-0000-0000-000000000091','owner');
do $$begin
  if (select count(*) from public.payroll_confirmers where company_id='10000000-0000-0000-0000-000000000090') <> 1
     or not exists(select 1 from public.payroll_confirmers where company_id='10000000-0000-0000-0000-000000000090' and user_id='00000000-0000-0000-0000-000000000090') then
    raise exception 'later owner replaced configured confirmer';
  end if;
  if has_function_privilege('authenticated','private.seed_company_payroll_confirmer()','EXECUTE')
     or has_function_privilege('anon','private.seed_company_payroll_confirmer()','EXECUTE') then
    raise exception 'trigger callable by client';
  end if;
end $$;
rollback;
