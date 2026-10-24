-- Disposable PostgreSQL17 only. Explicit synthetic authorization/neutral tax
-- surroundings; the report writers, signatures and financial producer bodies
-- are loaded separately from the source-MD5-checked observed fixture.
create role anon;
create role authenticated;
create role service_role bypassrls;
create schema auth;
create schema private;
create schema payroll_scope_private;
create schema payroll_unit_private;
create schema payroll_tax_private;
create schema resident_tax_private;
create schema company_allowance_identity_private;
create schema company_common_allowance_private;
create schema company_common_canonical_review_private;
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('fixture.actor',true),'')::uuid$$;
create function private.account_access_allowed() returns boolean language sql stable as $$select coalesce(nullif(current_setting('fixture.account',true),'')::boolean,true)$$;
create table public.companies(id uuid primary key,payroll_payment_day integer default 25,payroll_payment_month_offset integer default 0,payroll_closing_day integer default 31);
create table public.company_members(company_id uuid,user_id uuid,role text default 'owner');
create table public.workers(id uuid primary key,company_id uuid,name text);
create table public.sites(id uuid primary key,company_id uuid);
create table public.route_assignments(id uuid primary key,company_id uuid,is_active boolean default true);
create table public.daily_reports(id uuid primary key default gen_random_uuid(),company_id uuid,site_id uuid,route_assignment_id uuid,report_date date,
 work_description text,status text default 'draft',signer_name text,signature_json jsonb,signed_at timestamptz,
 representative_signer_name text,representative_signature_json jsonb,supervisor_signer_name text,supervisor_signature_json jsonb,
 created_by uuid,updated_by uuid,created_at timestamptz default now(),updated_at timestamptz default now(),unique(company_id,site_id,report_date));
create table public.daily_report_workers(report_id uuid,worker_id uuid,overtime_hours numeric default 0,early_hours numeric default 0,night_hours numeric default 0,
 allowance_amount integer default 0,allowance_label text,work_category text,primary key(report_id,worker_id));
create table public.daily_report_edit_requests(id uuid primary key default gen_random_uuid(),report_id uuid,requested_by uuid,status text,created_at timestamptz default now(),resolved_at timestamptz);
create table public.attendance_entries(id uuid primary key default gen_random_uuid(),company_id uuid,worker_id uuid,site_id uuid,route_assignment_id uuid,work_date date,
 base_man_days numeric default 0,regular_hours numeric not null default 0,overtime_hours numeric default 0,early_hours numeric default 0,night_hours numeric default 0,
 allowance_amount integer default 0,notes text,work_category text,allowance_names text[] default '{}',source_report_id uuid,created_by uuid,updated_by uuid,
 created_at timestamptz default now(),updated_at timestamptz default now());
create table public.worker_payroll_settings(company_id uuid,worker_id uuid,pay_type text default 'daily',day_daily integer default 10000,
 day_overtime integer default 0,day_early integer default 0,night_daily integer default 0,night_overtime integer default 0,night_early integer default 0,
 holiday_daily integer default 0,holiday_overtime integer default 0,holiday_early integer default 0,holiday_night_daily integer default 0,holiday_night_overtime integer default 0,holiday_night_early integer default 0,
 allowance_name_1 text,allowance_name_2 text,allowance_name_3 text,allowance_1 integer default 0,allowance_2 integer default 0,allowance_3 integer default 0,
 family_monthly integer default 0,transport_monthly integer default 0,income_tax_monthly integer default 0,social_insurance_monthly integer default 0,other_deduction_monthly integer default 0,
 monthly_salary_yen integer default 0,hourly_rate_yen integer default 0,custom_earnings jsonb default '[]',custom_deductions jsonb default '[]',rate_formula jsonb default '{}',updated_at timestamptz default now(),primary key(company_id,worker_id));
create table public.payroll_statements(id uuid primary key default gen_random_uuid(),company_id uuid,worker_id uuid,period_start date,period_end date,
 gross_pay integer,deductions integer,net_pay integer,detail jsonb default '{}',workflow_state text default 'draft',approver_ids uuid[] default '{}',approved_ids uuid[] default '{}',
 automatic_calculation boolean default true,calculation_blocked boolean default false,calculation_fingerprint text,revision integer default 1,
 created_at timestamptz default now(),updated_at timestamptz default now(),unique(company_id,worker_id,period_start,period_end));
create table public.payroll_audit(id uuid primary key default gen_random_uuid(),company_id uuid,statement_id uuid,revision integer,action text,actor_id uuid);
create table public.paid_leave_requests(company_id uuid,worker_id uuid,leave_date date,status text);
create table public.site_calculation_source_preferences(company_id uuid,site_id uuid,output_type text,source text,trade_company_id uuid);
create table public.trade_companies(id uuid,company_id uuid);
create table public.trade_company_contracts(company_id uuid,trade_company_id uuid,contract_method text,daily_rate_yen numeric,monthly_rate_yen numeric,square_meter_unit_price_yen numeric,square_meter_quantity numeric,contract_amount_yen numeric);
create table public.company_rate_settings(company_id uuid primary key,allowance_1_name text,allowance_1_amount_yen integer,allowance_1_unit text,
 allowance_2_name text,allowance_2_amount_yen integer,allowance_2_unit text,allowance_3_name text,allowance_3_amount_yen integer,allowance_3_unit text);
create table company_allowance_identity_private.state(company_id uuid primary key,version bigint);
create table company_allowance_identity_private.identities(id uuid primary key,company_id uuid,slot integer,generation bigint,retired_at timestamptz);
create table company_common_allowance_private.state(company_id uuid primary key,version bigint);
create table company_common_allowance_private.items(id uuid primary key,company_id uuid,payroll_type text,section text,unit text,name text,amount_yen integer,retired_at timestamptz);
create table company_common_allowance_private.payroll_activation(company_id uuid,starts_on date);
create table company_common_allowance_private.payroll_activation_modes(company_id uuid,mode text);
create table company_common_allowance_private.payroll_type_activation(company_id uuid,payroll_type text,starts_on date);
create table company_common_allowance_private.payroll_publications(company_id uuid,version bigint,payroll_type text,starts_on date,items jsonb);
create table payroll_unit_private.conditions(company_id uuid,worker_id uuid,starts_on date,version bigint,items jsonb);
create table payroll_unit_private.quantities(company_id uuid,worker_id uuid,item_id uuid,month date,hours numeric);
create function resident_tax_private.resolve(uuid,uuid,date) returns jsonb language sql stable as $$select '{"mode":"legacy","amount_yen":0}'::jsonb$$;
create function payroll_tax_private.calculate(uuid,uuid,date,date,bigint,bigint) returns jsonb language sql stable as $$select null::jsonb$$;
create function private.paid_leave_daily_amount(jsonb) returns numeric language sql immutable as $$select 0::numeric$$;
create function private.payroll_approver_ids(uuid) returns uuid[] language sql stable as $$select '{}'::uuid[]$$;
create function payroll_scope_private.report_sources(rid uuid) returns jsonb language sql stable as $$
 select jsonb_build_object('scopes',coalesce(jsonb_agg(jsonb_build_object('cid',r.company_id,'wid',w.worker_id,'day',r.report_date) order by w.worker_id),'[]'))
 from public.daily_reports r join public.daily_report_workers w on w.report_id=r.id where r.id=rid
$$;
create function payroll_scope_private.lock_scopes(p jsonb,p_strict boolean default false) returns void language plpgsql as $$
declare s jsonb;begin for s in select value from jsonb_array_elements(p) order by value::text loop
 perform pg_advisory_xact_lock(hashtextextended((s->>'cid')||(s->>'wid')||date_trunc('month',(s->>'day')::date)::date::text,0));end loop;end$$;
