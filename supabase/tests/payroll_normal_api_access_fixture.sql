-- Synthetic API dependencies; exact original business functions are installed separately.
alter table public.paid_leave_requests add column id uuid default gen_random_uuid() primary key,add column batch_id uuid,add column requested_by uuid,add column reason text,add column reviewed_by uuid,add column reviewed_at timestamptz,add column review_note text,add column updated_at timestamptz default now();
alter table public.paid_leave_requests alter column status set default 'pending';
alter table public.worker_payroll_settings add column paid_leave_granted_days numeric default 31;
alter table public.daily_reports alter column id set default gen_random_uuid();
alter table public.daily_reports add column created_by uuid;
alter table public.daily_report_workers add constraint normal_worker_report_unique unique(report_id,worker_id);
create table public.attendance_correction_requests(id uuid primary key default gen_random_uuid(),company_id uuid,status text,requested_by uuid,request_kind text,reviewed_by uuid,reviewed_at timestamptz,review_note text,updated_at timestamptz);
create table public.attendance_correction_items(id uuid primary key default gen_random_uuid(),request_id uuid,company_id uuid,attendance_entry_id uuid,proposed_snapshot jsonb,created_at timestamptz default now());
create table public.company_approval_assignees(company_id uuid,user_id uuid);
create table public.daily_report_edit_requests(id uuid primary key default gen_random_uuid(),report_id uuid,requested_by uuid,status text,created_at timestamptz default now(),resolved_at timestamptz);
create table private.daily_report_cancellations(id uuid primary key default gen_random_uuid(),company_id uuid,actor_id uuid,report_id uuid,site_id uuid,work_date date,reason text,snapshot jsonb);
alter table public.invoices add column if not exists customer_id uuid,add column if not exists billing_period_start date,add column if not exists billing_period_end date,add column if not exists status text,add column if not exists finalized_at timestamptz,add column if not exists automatic_calculation boolean;
alter table public.attendance_verifications add column company_id uuid,add column worker_id uuid,add column site_id uuid,add column event_type text,add column confirmed_at timestamptz,add column if not exists daily_report_id uuid,add column if not exists work_date date,add column verification_mode text,add column proximity_status text,add column note text,add column created_by uuid;
create table private.normal_fixture_notifications(company_id uuid,user_id uuid,kind text,title text,body text,entity_type text,entity_id uuid);
create or replace function private.enqueue_notification(uuid,uuid,text,text,text,text,uuid) returns void language sql as $$insert into private.normal_fixture_notifications values($1,$2,$3,$4,$5,$6,$7)$$;
create function private.report_clock_ids(uuid,uuid[],uuid,date) returns uuid[] language sql as $$select coalesce(array_agg(id),'{}') from public.attendance_verifications where company_id=$1 and worker_id=any($2) and site_id=$3 and work_date=$4$$;
create or replace function public.current_feature_permissions() returns jsonb language sql as $$select '{"can_manage_attendance":true}'::jsonb$$;
-- Exact captured WPS predicates; synthetic company/account helper fixtures remain documented.
alter table public.worker_payroll_settings enable row level security;
grant select,insert,update on public.worker_payroll_settings to authenticated;
create policy normal_fixture_wps_account on public.worker_payroll_settings as restrictive for all to authenticated using((select private.account_access_allowed())) with check((select private.account_access_allowed()));
create policy normal_fixture_wps_insert on public.worker_payroll_settings for insert to authenticated with check(private.payroll_settings_allowed(company_id,worker_id,'edit'));
create policy normal_fixture_wps_update on public.worker_payroll_settings for update to authenticated using(private.payroll_allowed(company_id,'edit')) with check(private.payroll_settings_allowed(company_id,worker_id,'edit'));
create policy normal_fixture_wps_read on public.worker_payroll_settings for select to authenticated using(private.payroll_allowed(company_id,'view'));
grant usage on schema auth to authenticated;

create table private.professional_invites(id uuid primary key,company_id uuid,claimed_by uuid,status text,payroll_access text,invoice_access text,attendance_view boolean,name text,phone text,profession text,token_hash bytea,created_by uuid,expires_at timestamptz,reviewed_by uuid,reviewed_at timestamptz,review_note text);
create table private.professional_access_audit(invite_id uuid,actor_id uuid,action text);
alter table public.worker_payroll_settings add column if not exists allowance_2 numeric,add column if not exists allowance_3 numeric,add column if not exists allowance_name_2 text,add column if not exists allowance_name_3 text;
alter table public.worker_payroll_settings add column updated_at timestamptz;
alter table public.worker_payroll_settings add constraint normal_fixture_wps_worker_unique unique(worker_id);
