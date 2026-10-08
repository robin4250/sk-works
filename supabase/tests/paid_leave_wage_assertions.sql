do $$
declare c uuid:='10000000-0000-0000-0000-000000000001'; w uuid:='40000000-0000-0000-0000-000000000001'; d date:=(now() at time zone 'Asia/Tokyo')::date; amount integer; revision_before integer;
begin
 delete from public.attendance_entries; delete from public.payroll_statements;
 update public.worker_payroll_settings set family_monthly=0,transport_monthly=0,income_tax_monthly=0,resident_tax_monthly=0,social_insurance_monthly=0,other_deduction_monthly=0,pay_type='daily',day_daily=12000,custom_earnings='[]',custom_deductions='[]';
 insert into public.paid_leave_requests values(c,w,d,'approved');
 select gross_pay into amount from public.payroll_statements where worker_id=w;
 if amount<>12000 then raise exception 'daily leave-only gross %',amount; end if;
 if (select (detail->>'有給支給額')::integer from public.payroll_statements where worker_id=w)<>12000 then raise exception 'missing named leave amount'; end if;
 select revision into revision_before from public.payroll_statements where worker_id=w;
 perform private.refresh_automatic_payroll_internal(c,w,d);
 if (select revision from public.payroll_statements where worker_id=w)<>revision_before then raise exception 'unstable revision'; end if;
 update public.worker_payroll_settings set pay_type='hourly',hourly_rate_yen=1500;
 perform private.refresh_automatic_payroll_internal(c,w,d);
 if (select gross_pay from public.payroll_statements where worker_id=w)<>12000 then raise exception 'hourly default'; end if;
 update public.worker_payroll_settings set rate_formula='{"paid_leave_daily_yen":9000}';
 perform private.refresh_automatic_payroll_internal(c,w,d);
 if (select gross_pay from public.payroll_statements where worker_id=w)<>9000 then raise exception 'hourly override'; end if;
 update public.worker_payroll_settings set pay_type='monthly',monthly_salary_yen=300000,calculation_daily_base_yen=14000;
 perform private.refresh_automatic_payroll_internal(c,w,d);
 if (select gross_pay from public.payroll_statements where worker_id=w)<>300000 then raise exception 'monthly double addition'; end if;
 -- Only the automatic draft is changed; deleting approval reverts leave wages.
 update public.worker_payroll_settings set pay_type='daily',day_daily=12000,monthly_salary_yen=0;
 delete from public.paid_leave_requests;
 if exists(select 1 from public.payroll_statements where worker_id=w) then raise exception 'revoked leave-only draft retained'; end if;
 insert into public.paid_leave_requests values(c,w,d+1,'approved');
 if exists(select 1 from public.payroll_statements where worker_id=w) then raise exception 'future leave paid early'; end if;
 delete from public.paid_leave_requests;
 insert into public.paid_leave_requests values(c,w,d,'pending');
 if exists(select 1 from public.payroll_statements where worker_id=w) then raise exception 'pending leave paid'; end if;
 update public.paid_leave_requests set status='approved';
 if (select gross_pay from public.payroll_statements where worker_id=w)<>12000 then raise exception 'approval update failed'; end if;
 update public.worker_payroll_settings set pay_type='monthly',monthly_salary_yen=300000;
 perform private.refresh_automatic_payroll_internal(c,w,d);
 update public.payroll_statements set workflow_state='approved';
 update public.worker_payroll_settings set monthly_salary_yen=400000;
 perform private.refresh_automatic_payroll_internal(c,w,d);
 if (select gross_pay from public.payroll_statements where worker_id=w)<>300000 then raise exception 'history overwritten'; end if;
end $$;
