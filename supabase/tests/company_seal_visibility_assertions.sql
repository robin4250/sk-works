-- Run only through the isolated fixture runner.
do $$begin
 if exists(select 1 from public.companies where company_seal_enabled is distinct from true) then
  raise exception 'existing companies must retain visible seals'; end if;
 if (public.invoice_document_settings()-'company_seal_enabled')<>(select metadata from test_before_invoice) then
  raise exception 'invoice metadata changed beyond the seal switch'; end if;
 if exists(select 1 from public.payroll_statements ps join test_before_payroll b on b.id=ps.id
  where (private.payroll_document_metadata(ps.id)-'company_seal_enabled')<>b.metadata) then
  raise exception 'payroll metadata, warnings or approval history changed'; end if;
 if not (select relrowsecurity from pg_class where oid='public.companies'::regclass)
 or exists((select oid from pg_policy where polrelid='public.companies'::regclass) except select oid from test_before_policy)
 or exists(select oid from test_before_policy except (select oid from pg_policy where polrelid='public.companies'::regclass)) then
  raise exception 'existing company RLS changed'; end if;
 if has_function_privilege('anon','public.company_seal_settings()','execute')
 or has_function_privilege('anon','public.save_company_seal_settings(boolean)','execute') then
  raise exception 'anonymous seal settings exposed'; end if;
 if not has_function_privilege('authenticated','public.company_seal_settings()','execute')
 or not has_function_privilege('authenticated','public.save_company_seal_settings(boolean)','execute') then
  raise exception 'authenticated RPC grant missing'; end if;
end $$;

set role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',false);
do $$begin
 if public.company_seal_settings()<>'{"company_seal_enabled":true}'::jsonb then raise exception 'owner load failed'; end if;
 if public.save_company_seal_settings(false)<>'{"company_seal_enabled":false}'::jsonb then raise exception 'owner disable failed'; end if;
 if (public.invoice_document_settings()->>'company_seal_enabled')::boolean then raise exception 'invoice stale seal state'; end if;
 begin perform public.save_company_seal_settings(null); raise exception 'null accepted'; exception when null_value_not_allowed then null; end;
 if public.company_seal_settings()<>'{"company_seal_enabled":false}'::jsonb then raise exception 'null save altered setting'; end if;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',false);
do $$begin
 if public.company_seal_settings()<>'{"company_seal_enabled":false}'::jsonb then raise exception 'admin load failed'; end if;
 if public.save_company_seal_settings(true)<>'{"company_seal_enabled":true}'::jsonb then raise exception 'admin enable failed'; end if;
 perform public.save_company_seal_settings(false);
end $$;
-- Manager, viewer, member and a user without membership cannot use admin settings.
do $$declare suffix text; changed integer; begin
 foreach suffix in array array['3','4','5','7'] loop
  perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-00000000000'||suffix,false);
  begin perform public.company_seal_settings(); raise exception 'nonadmin load allowed'; exception when insufficient_privilege then null; end;
  begin perform public.save_company_seal_settings(true); raise exception 'nonadmin save allowed'; exception when insufficient_privilege then null; end;
  update public.companies set company_seal_enabled=true;
  get diagnostics changed=row_count;
  if changed<>0 then raise exception 'nonadmin bypassed settings via direct UPDATE'; end if;
  if exists(select 1 from public.companies where id='10000000-0000-0000-0000-000000000002') then raise exception 'foreign flag exposed through SELECT'; end if;
 end loop;
end $$;
select set_config('request.jwt.claim.sub','',false);
do $$begin
 begin perform public.company_seal_settings(); raise exception 'logged out load allowed'; exception when insufficient_privilege then null; end;
 begin perform public.save_company_seal_settings(true); raise exception 'logged out save allowed'; exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',false);
select set_config('test.account_access_denied','1',false);
do $$begin
 begin perform public.company_seal_settings(); raise exception 'blocked account load allowed'; exception when insufficient_privilege then null; end;
 begin perform public.save_company_seal_settings(true); raise exception 'blocked account save allowed'; exception when insufficient_privilege then null; end;
end $$;
select set_config('test.account_access_denied','',false);
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000006',false);
do $$declare changed integer; begin
 if public.company_seal_settings()<>'{"company_seal_enabled":true}'::jsonb then raise exception 'foreign company initial state changed';
 update public.companies set company_seal_enabled=true where id='10000000-0000-0000-0000-000000000001';
 get diagnostics changed=row_count;
 if changed<>0 then raise exception 'foreign owner bypassed settings via direct UPDATE'; end if; end if;
 perform public.save_company_seal_settings(false);
 perform public.save_company_seal_settings(true);
end $$;
reset role;

do $$begin
 if (select company_seal_enabled from public.companies where id='10000000-0000-0000-0000-000000000001') then
  raise exception 'other company or unauthorized save changed original'; end if;
 if not (select company_seal_enabled from public.companies where id='10000000-0000-0000-0000-000000000002') then
  raise exception 'foreign owner save failed'; end if;
 if (private.payroll_document_metadata('50000000-0000-0000-0000-000000000001')->>'company_seal_enabled')::boolean
 or not (private.payroll_document_metadata('50000000-0000-0000-0000-000000000002')->>'company_seal_enabled')::boolean then
  raise exception 'payroll seal state not bound to statement company'; end if;
 if exists((select id,gross_pay,deductions,net_pay,detail from public.payroll_statements) except select * from test_before_money)
 or exists(select * from test_before_money except (select id,gross_pay,deductions,net_pay,detail from public.payroll_statements)) then
  raise exception 'seal switch mutated persisted payroll'; end if;
 if exists(select 1 from public.payroll_statements ps join test_before_payroll b on b.id=ps.id
  where (private.payroll_document_metadata(ps.id)-'company_seal_enabled')<>b.metadata) then
  raise exception 'seal toggling altered payroll history or calculations'; end if;
end $$;
set role anon;
do $$begin
 begin perform public.company_seal_settings(); raise exception 'anonymous actual load allowed'; exception when insufficient_privilege then null; end;
 begin perform public.save_company_seal_settings(true); raise exception 'anonymous actual save allowed'; exception when insufficient_privilege then null; end;
end $$;
reset role;
