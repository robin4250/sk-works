-- Disposable schema and permission prerequisites; never apply to a linked DB.
create table public.daily_reports(id uuid primary key default gen_random_uuid(),company_id uuid references public.companies(id),site_id uuid,route_assignment_id uuid,report_date date,status text default 'draft',representative_signature_json jsonb,supervisor_signature_json jsonb,representative_signer_name text,supervisor_signer_name text,signer_name text,signature_json jsonb,signed_at timestamptz,updated_by uuid,updated_at timestamptz);
create table public.daily_report_workers(report_id uuid references public.daily_reports(id) on delete cascade,worker_id uuid references public.workers(id),overtime_hours numeric default 0,early_hours numeric default 0,night_hours numeric default 0,allowance_amount integer default 0,allowance_label text,work_category text default 'day',primary key(report_id,worker_id));
alter table public.attendance_entries add column source_report_id uuid references public.daily_reports(id),add column route_assignment_id uuid,add column allowance_amount numeric default 0,add column notes text,add column created_by uuid,add column updated_by uuid,add column created_at timestamptz default now(),add column updated_at timestamptz;
alter table public.attendance_entries add constraint fixture_attendance_company_fk foreign key(company_id) references public.companies(id) on delete cascade,add constraint fixture_attendance_worker_fk foreign key(worker_id) references public.workers(id) on delete cascade;
create table public.sites(id uuid primary key,company_id uuid,customer_id uuid,name text);
create table public.customers(id uuid primary key,company_id uuid);
create table public.partner_companies(id uuid primary key,company_id uuid);
create table public.partner_payment_settings(company_id uuid,partner_company_id uuid,daily_rate_yen numeric,updated_at timestamptz,primary key(company_id,partner_company_id));
alter table public.trade_companies add primary key(id),add column trade_role text,add column customer_id uuid,add column partner_company_id uuid;
alter table public.trade_company_contracts add column updated_by uuid,add column updated_at timestamptz,add unique(company_id,trade_company_id);
alter table public.site_calculation_source_preferences add column selected_by uuid,add column selected_at timestamptz,add unique(company_id,site_id,output_type);
create function private.current_company_admin_id() returns uuid language sql stable security definer set search_path='' as $$select company_id from public.company_members where user_id=auth.uid() and role::text in ('owner','admin') limit 1$$;
-- Non-payroll branch stubs are explicit fixture boundaries, not tested production behavior.
create function private.refresh_automatic_invoice(uuid,uuid,date) returns void language sql as $$select$$;
create function private.refresh_automatic_payment_certificate(uuid,uuid,date) returns void language sql as $$select$$;

create table public.payroll_confirmation_history(company_id uuid,statement_id uuid,reviewer_id uuid,revision integer,action text,created_at timestamptz);
create function private.payroll_confirmation_company() returns uuid language sql stable security definer set search_path='' as $$select company_id from public.company_members where user_id=auth.uid() limit 1$$;

-- Existing public signature wrapper is SECINV and delegates to an authenticated private API.
grant usage on schema private to authenticated;

alter table public.daily_reports add column work_description text;
create table public.attendance_verifications(id uuid primary key,daily_report_id uuid,work_date date,source_clock_in_id uuid);

alter table public.daily_report_workers add column if not exists vehicle_id uuid, add column if not exists route_assignment_id uuid, add column if not exists odometer_km numeric;
create table if not exists public.vehicles(id uuid primary key,company_id uuid,is_active boolean,odometer_km numeric,updated_by uuid,updated_at timestamptz);
create table if not exists public.route_assignments(id uuid primary key,company_id uuid,is_active boolean);
