do $$declare
  cid uuid:='10000000-0000-0000-0000-000000000001';
  before_all jsonb;after_all jsonb;before_legacy jsonb;after_legacy jsonb;before_stamp timestamptz;
  original jsonb;wanted jsonb;saved jsonb;
begin
  perform set_config('fixture.actor','20000000-0000-0000-0000-000000000001',false);
  original:=public.read_company_rate_defaults(cid)-'contract_version'-'company_id';
  select to_jsonb(r)-'overtime_hour_rate_yen'-'early_hour_rate_yen'-'night_hour_rate_yen'
    -'holiday_day_rate_yen'-'updated_by'-'updated_at' into before_legacy from public.company_rate_settings r where company_id=cid;
  wanted:=original||jsonb_build_object('tax_rate',8,'overtime_hour_rate_yen',1400);
  saved:=public.save_company_rate_defaults(cid,original,wanted);
  assert saved-'contract_version'-'company_id'=wanted,'rate save response differs';
  select to_jsonb(r)-'overtime_hour_rate_yen'-'early_hour_rate_yen'-'night_hour_rate_yen'
    -'holiday_day_rate_yen'-'updated_by'-'updated_at',r.updated_at into after_legacy,before_stamp from public.company_rate_settings r where company_id=cid;
  assert before_legacy=after_legacy,'legacy allowances changed';
  saved:=public.save_company_rate_defaults(cid,original,wanted);
  assert (select updated_at=before_stamp from public.company_rate_settings where company_id=cid),'exact retry wrote again';
  select jsonb_build_object('companies',(select jsonb_agg(to_jsonb(c) order by id) from public.companies c),
    'rates',(select jsonb_agg(to_jsonb(r) order by company_id) from public.company_rate_settings r)) into before_all;
  begin
    perform public.save_company_rate_defaults(cid,original,wanted||'{"tax_rate":9}');
    raise exception 'stale accepted';
  exception when serialization_failure then null;end;
  begin
    perform public.save_company_rate_defaults(cid,wanted,wanted||'{"allowance_1_amount_yen":0}');
    raise exception 'hidden allowance accepted';
  exception when invalid_parameter_value then null;end;
  begin
    perform public.save_company_rate_defaults(cid,wanted,wanted||'{"tax_rate":8.001}');
    raise exception 'silent database rounding accepted';
  exception when invalid_parameter_value then null;end;
  begin
    perform public.save_company_rate_defaults(cid,wanted,wanted||'{"tax_rate":101}');
    raise exception 'invalid rate accepted';
  exception when invalid_parameter_value then null;end;
  begin
    perform public.save_company_rate_defaults('10000000-0000-0000-0000-000000000002',wanted,wanted);
    raise exception 'foreign company accepted';
  exception when insufficient_privilege then null;end;
  perform set_config('fixture.actor','20000000-0000-0000-0000-000000000002',false);
  begin
    perform public.save_company_rate_defaults(cid,wanted,wanted);
    raise exception 'employee accepted';
  exception when insufficient_privilege then null;end;
  select jsonb_build_object('companies',(select jsonb_agg(to_jsonb(c) order by id) from public.companies c),
    'rates',(select jsonb_agg(to_jsonb(r) order by company_id) from public.company_rate_settings r)) into after_all;
  assert before_all=after_all,'rejected requests changed originals';
  assert not has_function_privilege('anon','public.save_company_rate_defaults(uuid,jsonb,jsonb)','execute');
  assert not has_function_privilege('service_role','public.save_company_rate_defaults(uuid,jsonb,jsonb)','execute');
  assert has_function_privilege('authenticated','public.save_company_rate_defaults(uuid,jsonb,jsonb)','execute');
end $$;

-- Exercise the public invoker wrappers as the actual caller role. A concurrent
-- change to a legacy slot must survive an unrelated defaults save.
select set_config('fixture.actor','20000000-0000-0000-0000-000000000001',false);
update public.company_rate_settings set allowance_1_amount_yen=3210
where company_id='10000000-0000-0000-0000-000000000001';
set role authenticated;
do $$declare cid uuid:='10000000-0000-0000-0000-000000000001'; old jsonb;new_values jsonb;begin
  old:=public.read_company_rate_defaults(cid)-'contract_version'-'company_id';
  new_values:=old||'{"welfare_rate":16}';
  perform public.save_company_rate_defaults(cid,old,new_values);
end $$;
reset role;
do $$begin
  assert (select allowance_1_amount_yen=3210 and allowance_2_amount_yen=2000
    and allowance_3_amount_yen=1000 from public.company_rate_settings
    where company_id='10000000-0000-0000-0000-000000000001'),'concurrent legacy allowances lost';
end $$;
select set_config('fixture.actor','',false);
set role authenticated;
do $$begin
  begin
    perform public.read_company_rate_defaults('10000000-0000-0000-0000-000000000001');
    raise exception 'missing actor accepted';
  exception when insufficient_privilege then null;end;
end $$;
reset role;
