-- Read-only production connection check. Does not inspect employee/payroll values.
-- Run as the database migration operator without an end-user JWT.
begin read only;
do $$
declare signature text; relation record; actual_count integer;
begin
 if auth.uid() is not null then raise exception 'Run without an end-user JWT'; end if;
 foreach signature in array array[
  'public.read_company_payroll_rates(uuid)',
  'public.save_company_payroll_rate_scope(uuid,bigint,jsonb,boolean)',
  'public.save_manual_company_payroll_rate(uuid,text,bigint,jsonb,boolean)',
  'public.apply_company_payroll_rate_candidate(uuid,text,uuid,bigint,boolean)',
  'public.read_company_income_tax_tables(uuid,text,text)',
  'public.register_company_income_tax_table(uuid,uuid,bigint,jsonb,boolean)'
 ] loop
  if to_regprocedure(signature) is null then raise exception 'Missing RPC: %',signature; end if;
  if has_function_privilege('anon',signature,'EXECUTE') or
     not has_function_privilege('authenticated',signature,'EXECUTE') or
     (select prosecdef from pg_proc where oid=to_regprocedure(signature)) then
   raise exception 'Unexpected public RPC privileges: %',signature;
  end if;
 end loop;
 actual_count:=0;
 for relation in select c.oid,c.relname,c.relrowsecurity from pg_class c
  join pg_namespace n on n.oid=c.relnamespace
  where n.nspname in ('payroll_rate_private','income_tax_private') and c.relkind='r'
 loop
  actual_count:=actual_count+1;
  if not relation.relrowsecurity or
     has_table_privilege('authenticated',relation.oid,'SELECT,INSERT,UPDATE,DELETE') or
     has_table_privilege('anon',relation.oid,'SELECT,INSERT,UPDATE,DELETE') then
   raise exception 'Unexpected direct table access: %',relation.relname;
  end if;
 end loop;
 if actual_count<>8 then raise exception 'Expected 8 private tax tables, found %',actual_count; end if;
 if not exists(select 1 from storage.buckets where id='company-income-tax-tables'
  and public=false and file_size_limit=10485760 and allowed_mime_types=array['application/pdf']) then
  raise exception 'Private PDF bucket configuration differs';
 end if;
 if (select count(*) from pg_policy where polrelid='storage.objects'::regclass
  and polname in ('income_tax_pdf_insert_guard','income_tax_pdf_insert',
   'income_tax_pdf_read_guard','income_tax_pdf_read','income_tax_pdf_no_update',
   'income_tax_pdf_no_delete','income_tax_pdf_no_anon'))<>7 then
  raise exception 'Income PDF policies incomplete';
 end if;
 begin
  perform public.read_company_payroll_rates('00000000-0000-0000-0000-000000000000');
  raise exception 'Unauthenticated rate read unexpectedly allowed';
 exception when insufficient_privilege then null;
 end;
 begin
  perform public.read_company_income_tax_tables('00000000-0000-0000-0000-000000000000','2026-10-10','monthly');
  raise exception 'Unauthenticated income read unexpectedly allowed';
 exception when insufficient_privilege then null;
 end;
end $$;
select 'PASS tax connection: RPC ACL, private tables, PDF bucket/policies, unauthenticated denial' as result;
rollback;
