-- Disposable existing-schema additions; no production row mutations.
alter table public.workers add column affiliation text default 'employee',add column status text default 'active',add column role text,
 add column employee_number text,add column department text,add column hire_date date;
alter table public.worker_payroll_settings add column payment_day integer default 25;
update public.company_members set role='viewer' where user_id='00000000-0000-0000-0000-000000000002';
update public.company_members set role='manager' where user_id='00000000-0000-0000-0000-000000000003';
-- ASSERTIONS
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',false);
select set_config('test.account_access_denied','',false);
do $$declare a jsonb; before_time timestamptz; s record; begin
 if (select count(*) from public.payroll_confirmers where company_id='10000000-0000-0000-0000-000000000001')<>1 then raise exception 'default single owner'; end if;
 if private.payroll_payment_date('2026-10-31','10000000-0000-0000-0000-000000000001')<>'2026-11-25'::date then raise exception 'next month payday'; end if;
 perform public.set_payroll_confirmation_settings(array['00000000-0000-0000-0000-000000000001'::uuid,'00000000-0000-0000-0000-000000000002'::uuid],25,1,31);
 for s in select id,revision from public.payroll_statements where period_start='2026-08-01' loop perform public.set_payroll_review_check(s.id,s.revision,true); end loop;
 perform public.confirm_payroll_review_month('2026-08-01');
 select max(confirmed_at) into before_time from public.payroll_statement_reviews;
 if public.confirm_payroll_review_month('2026-08-01')<>0 then raise exception 'double confirm'; end if;
 if (select max(confirmed_at) from public.payroll_statement_reviews)<>before_time then raise exception 'actual timestamp changed'; end if;
 a:=public.payroll_confirmation_status('2026-08-01');
 if (a->>'confirmed')::boolean then raise exception 'ANY instead of ALL'; end if;
 if not (a->>'can_cancel')::boolean then raise exception 'self cancel status'; end if;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',false);
do $$declare s record; begin
 for s in select id,revision from public.payroll_statements where period_start='2026-08-01' loop perform public.set_payroll_review_check(s.id,s.revision,true); end loop;
 perform public.confirm_payroll_review_month('2026-08-01');
 if not (public.payroll_confirmation_status('2026-08-01')->>'confirmed')::boolean then raise exception 'two confirmers finalize'; end if;
 perform public.cancel_payroll_review_month('2026-08-01');
 if (public.payroll_confirmation_status('2026-08-01')->>'confirmed')::boolean then raise exception 'cancellation invalidation'; end if;
 if (select count(*) from public.payroll_statement_reviews where reviewer_id='00000000-0000-0000-0000-000000000001' and confirmed_at is not null)<>2 then raise exception 'cancel affected other reviewer'; end if;
end $$;
-- Reminder dedupe and eight-day inclusive window: Sep18 through25 for Aug work.
do $$declare n int; begin
 n:=private.enqueue_payroll_confirmation_notifications('2026-08-30'); if n<>0 then raise exception 'before month end notices'; end if;
 n:=private.enqueue_payroll_confirmation_notifications('2026-08-31'); if n<>1 then raise exception 'open notice'; end if;
 if private.enqueue_payroll_confirmation_notifications('2026-08-31')<>0 then raise exception 'duplicate open'; end if;
 if private.enqueue_payroll_confirmation_notifications('2026-09-17')<>0 then raise exception 'early reminder'; end if;
 if private.enqueue_payroll_confirmation_notifications('2026-09-18')<>1 then raise exception 'day seven reminder'; end if;
 if private.enqueue_payroll_confirmation_notifications('2026-09-18')<>0 then raise exception 'duplicate reminder'; end if;
 if private.enqueue_payroll_confirmation_notifications('2026-09-25')<>1 then raise exception 'payday reminder'; end if;
 if private.enqueue_payroll_confirmation_notifications('2026-09-26')<>0 then raise exception 'late reminder'; end if;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000003',false);
do $$begin
 begin perform public.confirm_payroll_review_month('2026-08-01'); raise exception 'unassigned allowed'; exception when others then if sqlerrm<>'assigned payroll confirmer required' then raise; end if; end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',false);
do $$declare s record; begin
 update public.payroll_statements set revision=revision+1 where period_start='2026-08-01';
 if (public.payroll_confirmation_status('2026-08-01')->'reviewers'->0->>'confirmed')::boolean then raise exception 'stale revision stamp'; end if;
 if exists(select 1 from public.my_payroll_statement_rows_with_adjustments(),jsonb_array_elements(detail->'payroll_confirmations')x where period_start='2026-08-01' and x->>'confirmed_at' is not null) then raise exception 'stale PDF stamp'; end if;
 if (select count(*) from public.payroll_confirmation_history where action='confirmed')<>4 then raise exception 'history lost'; end if;
 perform public.set_payroll_confirmation_settings(array['00000000-0000-0000-0000-000000000001'::uuid],31,1,31);
 if private.payroll_payment_date('2026-01-31','10000000-0000-0000-0000-000000000001')<>'2026-02-28'::date then raise exception 'short month clamp'; end if;
 if private.payroll_payment_date('2026-01-31','10000000-0000-0000-0000-000000000001','{"payment_date":"2026-02-20"}')<>'2026-02-20'::date then raise exception 'historical payment priority'; end if;
 begin perform public.set_payroll_confirmation_settings(array['00000000-0000-0000-0000-000000000004'::uuid],22,1,31); raise exception 'cross company settings allowed'; exception when others then if sqlerrm<>'invalid company confirmer' then raise; end if; end;
 if (public.payroll_company_policy()->>'payment_day')::int<>31 then raise exception 'non atomic company settings'; end if;
 if has_function_privilege('anon','public.confirm_payroll_review_month(date)','EXECUTE') then raise exception 'anonymous confirm'; end if;
end $$;

select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',false);
do $$begin
 begin perform public.set_payroll_company_policy(25,0,31); raise exception 'payday before confirmation accepted'; exception when others then if sqlerrm not like 'invalid payroll policy%' then raise; end if; end;
 perform public.set_payroll_company_policy(31,0,31);
 if private.payroll_payment_date('2026-02-28','10000000-0000-0000-0000-000000000001')<>'2026-02-28'::date then raise exception 'current month end'; end if;
 if private.enqueue_payroll_confirmation_notifications('2026-10-08')<>0 then raise exception 'late historical notice'; end if;
end $$;
-- Management previews use the same registered employee/date metadata, retaining visibility.
update public.workers set employee_number='EMP001',department='工事部',role='作業員',hire_date='2020-04-01' where id='40000000-0000-0000-0000-000000000001';
do $$declare item jsonb; begin
 select x into item from jsonb_array_elements(public.payroll_review_workspace('2026-08-01')->'statements')x where x->>'worker_id'='40000000-0000-0000-0000-000000000001';
 if item->'detail'->>'社員番号'<>'EMP001' or item->'detail'->>'所属'<>'工事部' or item->'detail'->>'payment_date'<>'2026-08-31' then raise exception 'management document metadata'; end if;
 perform public.set_payroll_confirmers(array['00000000-0000-0000-0000-000000000001'::uuid,'00000000-0000-0000-0000-000000000002'::uuid,'00000000-0000-0000-0000-000000000003'::uuid]);
 if (select count(*) from public.payroll_confirmers where company_id='10000000-0000-0000-0000-000000000001')<>3 then raise exception 'three assignment'; end if;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000003',false);
do $$declare s record; begin
 if jsonb_array_length(public.payroll_review_workspace('2026-08-01')->'statements')<>0 then raise exception 'manager visibility widened'; end if;
 select id,revision into s from public.payroll_statements where period_start='2026-08-01' limit 1;
 begin perform public.set_payroll_review_check(s.id,s.revision,true); raise exception 'hidden payroll check permitted'; exception when others then if sqlerrm<>'payroll visibility required' then raise; end if; end;
end $$;
-- Future work periods cannot be confirmed before month end.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',false);
insert into public.payroll_statements(worker_id,company_id,period_start,period_end,gross_pay,deductions,net_pay,detail,automatic_calculation)
values('40000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','2099-01-01','2099-01-31',100,0,100,'{}',false);
do $$declare s record; begin
 select id,revision into s from public.payroll_statements where period_start='2099-01-01';
 begin perform public.set_payroll_review_check(s.id,s.revision,true); raise exception 'early check permitted'; exception when others then if sqlerrm<>'confirmation opens at period end' then raise; end if; end;
end $$;
-- Unauthenticated sessions cannot inspect status or change configuration.
select set_config('request.jwt.claim.sub','',false);
do $$begin
 begin perform public.payroll_confirmation_status('2026-08-01'); raise exception 'unauthenticated status allowed'; exception when others then if sqlerrm<>'authentication required' then raise; end if; end;
 if exists(select 1 from pg_class where relname in ('payroll_confirmers','payroll_confirmation_history','payroll_confirmation_notices') and not relrowsecurity) then raise exception 'RLS disabled'; end if;
 if has_table_privilege('authenticated','public.payroll_confirmation_history','UPDATE') then raise exception 'history client mutable'; end if;
end $$;
