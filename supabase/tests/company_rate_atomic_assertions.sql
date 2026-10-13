-- Disposable harness assertions: production RPCs, constrained second-step failure.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',false);
select public.save_company_rate_settings_with_units(10,3,1500,1400,2000,18000,'手当',500,null,0,null,0,' 回 ','日','時間');
do $$begin
 if not exists(select 1 from public.company_rate_settings where company_id='10000000-0000-0000-0000-000000000001'
 and overtime_hour_rate_yen=1500 and allowance_1_amount_yen=500 and allowance_1_unit='回' and allowance_2_unit='日') then
 raise exception 'atomic initial save failed'; end if;
end $$;
-- A late failure after the old rates RPC must rollback both the company and rate row.
alter table public.company_rate_settings add constraint test_unit_failure check(allowance_1_unit<>'FAIL');
do $$begin
 begin
  perform public.save_company_rate_settings_with_units(8,7,9999,9999,9999,9999,'変更',999,null,0,null,0,'FAIL','日','時間');
  raise exception 'expected second-step failure did not occur';
 exception when check_violation then null; end;
 if (select tax_rate from public.companies where id='10000000-0000-0000-0000-000000000001')<>10 or
 (select default_welfare_rate from public.companies where id='10000000-0000-0000-0000-000000000001')<>3 or
 not exists(select 1 from public.company_rate_settings where company_id='10000000-0000-0000-0000-000000000001'
 and overtime_hour_rate_yen=1500 and allowance_1_name='手当' and allowance_1_amount_yen=500 and allowance_1_unit='回') then
 raise exception 'second-step failure left partial money save'; end if;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',false);
do $$declare denied boolean:=false; begin
 begin perform public.save_company_rate_settings_with_units(20,9,9999,0,0,0); exception when others then
 if sqlerrm='owner or admin permission required' then denied:=true; else raise; end if; end;
 if not denied then raise exception 'member money save allowed'; end if;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000004',false);
select public.save_company_rate_settings_with_units(7,2,1234,0,0,0);
do $$begin
 if (select tax_rate from public.companies where id='10000000-0000-0000-0000-000000000001')<>10 then
 raise exception 'other company owner changed original company'; end if;
 if not exists(select 1 from public.company_rate_settings where company_id='10000000-0000-0000-0000-000000000002' and overtime_hour_rate_yen=1234) then
 raise exception 'other company scoped save failed'; end if;
 if has_function_privilege('anon','public.save_company_rate_settings_with_units(numeric,numeric,integer,integer,integer,integer,text,integer,text,integer,text,integer,text,text,text)','execute') then
 raise exception 'anonymous atomic money save exposed'; end if;
end $$;
