alter table public.companies add column name text;
create table public.workers(id uuid primary key,company_id uuid,user_id uuid,name text);
create table public.payroll_statements(id uuid primary key,worker_id uuid,company_id uuid,period_start date,period_end date,gross_pay int,deductions int,net_pay int,detail jsonb,issued_at timestamptz);
create table public.payroll_adjustments(company_id uuid,worker_id uuid,effective_date date,cancelled_at timestamptz,label_snapshot text,direction text,amount_yen int);
create table public.worker_private_bank_accounts(worker_id uuid,company_id uuid,bank_name text,branch_name text,account_type text,account_number text,account_holder text,updated_at timestamptz);
insert into public.workers values('40000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000001','Employee One'),('40000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002','Employee Two');
insert into public.payroll_statements values('50000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','2026-09-01','2026-09-30',10000,1000,9000,'{}',now()),('50000000-0000-0000-0000-000000000002','40000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001','2026-09-01','2026-09-30',20000,1000,19000,'{}',now());
insert into public.payroll_adjustments values('10000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000001','2026-09-20',null,'Adjustment','addition',500);
insert into public.worker_private_bank_accounts values('40000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','SELF BANK','BRANCH','ordinary','0012345','SELF',now()),('40000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001','OTHER BANK','BRANCH','ordinary','SECRET','OTHER',now());
-- Assertions follow after applying the private-bank migration (runner splits here).
-- ASSERTIONS
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',false);
do $$declare r record; begin
 if (select count(*) from public.my_payroll_statement_rows_with_adjustments())<>1 then raise exception 'payroll scope'; end if;
 select * into r from public.my_payroll_statement_rows_with_adjustments();
 if r.detail->'bank_account'->>'account_number'<>'0012345' then raise exception 'bank join'; end if;
 if r.gross_pay<>10500 or r.net_pay<>9500 then raise exception 'adjustment calculation'; end if;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000003',false);
do $$begin
 if exists(select 1 from public.my_payroll_statement_rows_with_adjustments()) then raise exception 'other user leakage'; end if;
end $$;
