-- Synthetic authorization surroundings. Not a real GoTrue/session proof.
create role anon nologin;
create role authenticated nologin;
create role service_role nologin;
create schema auth;create schema private;create schema payroll_tax_private;create schema payroll_final_private;
grant usage on schema auth,private,payroll_tax_private to authenticated;
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('test.actor',true),'')::uuid$$;
create function private.account_access_allowed() returns boolean language sql stable as $$select coalesce(current_setting('test.blocked',true),'')<> 'yes'$$;
create table public.companies(id uuid primary key);
create table public.workers(id uuid primary key,company_id uuid not null);
create table public.payroll_statements(id uuid primary key,company_id uuid not null,worker_id uuid not null,
 period_start date not null,period_end date not null,gross_pay integer not null,revision integer not null,
 workflow_state text not null,automatic_calculation boolean not null default false,calculation_blocked boolean not null default false,detail jsonb not null default '{}');
create table public.payroll_adjustments(id uuid primary key,company_id uuid,worker_id uuid,effective_date date,
 direction text,amount_yen integer,cancelled_at timestamptz);
create table payroll_final_private.documents(statement_id uuid primary key,company_id uuid,worker_id uuid,value jsonb);
create table payroll_tax_private.worker_conditions(company_id uuid,worker_id uuid,starts_on date,version bigint,value jsonb,updated_by uuid,updated_at timestamptz,primary key(company_id,worker_id,starts_on));
create table payroll_tax_private.condition_history(company_id uuid,worker_id uuid,starts_on date,version bigint,before_value jsonb,after_value jsonb,actor_id uuid,changed_at timestamptz,primary key(company_id,worker_id,starts_on,version));
alter table payroll_tax_private.worker_conditions enable row level security;
alter table payroll_tax_private.condition_history enable row level security;
revoke all on all tables in schema payroll_tax_private,payroll_final_private from public,anon,authenticated;
create function private.payroll_settings_allowed(cid uuid,wid uuid,op text) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid()='00000000-0000-0000-0000-000000000001'::uuid and
 cid='10000000-0000-0000-0000-000000000001'::uuid and exists(select 1 from public.workers w where w.id=wid and w.company_id=cid)
 and (op='view' or coalesce(current_setting('test.viewer',true),'')<>'yes')
$$;
create function private.payroll_document_metadata(sid uuid) returns jsonb language sql stable as $$select detail->'document_metadata' from public.payroll_statements where id=sid$$;
create function private.refresh_automatic_payroll(cid uuid,wid uuid,d date) returns void language plpgsql as $$begin return;end$$;
create function private.sync_payroll_attendance_detail(cid uuid,wid uuid,d date) returns void language plpgsql as $$begin return;end$$;
