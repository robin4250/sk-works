-- Disposable supporting schema/access only; never execute against a linked DB.
alter table public.workers add column employee_number text,add column department text,add column role text;
alter table public.companies add column company_seal_enabled boolean default false,add column company_seal_url text,add column company_seal_style text default 'legacy';
alter table public.payroll_statements add column finalized_by uuid,add column finalized_at timestamptz,add column retained_finalized_by jsonb;
alter table public.payroll_adjustments add column id uuid primary key default gen_random_uuid(),add column type_id uuid,add column note text,add column created_by uuid,add column cancelled_by uuid,add column cancellation_reason text,add column updated_at timestamptz;
create table public.payroll_adjustment_types(id uuid primary key,company_id uuid,label text,direction text,is_active boolean);
create table public.payroll_adjustment_audit_log(company_id uuid,action text,target_kind text,target_id uuid,actor_user_id uuid,details jsonb);
create table public.payroll_confirmers(company_id uuid,user_id uuid,position integer);
create table public.payroll_statement_reviews(statement_id uuid,reviewer_id uuid,checked_revision integer,confirmed_revision integer,confirmed_at timestamptz,updated_at timestamptz);
create table if not exists public.user_profiles(user_id uuid,display_name text);
create table public.payroll_manager_worker_visibility(company_id uuid,worker_id uuid,visible_to_manager boolean);
create function public.payroll_adjustment_access() returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('company_id',cm.company_id,'can_manage',cm.role::text in ('owner','admin')) from public.company_members cm where cm.user_id=auth.uid() limit 1
$$;
create function private.payroll_confirmer_eligible(cid uuid,uid uuid,day date) returns boolean language sql stable security definer set search_path='' as $$select exists(select 1 from public.payroll_confirmers where company_id=cid and user_id=uid)$$;
create function private.payroll_confirmed_all(statement uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.payroll_confirmers c where c.company_id=ps.company_id) and not exists(select 1 from public.payroll_confirmers c where c.company_id=ps.company_id and not exists(select 1 from public.payroll_statement_reviews r where r.statement_id=ps.id and r.reviewer_id=c.user_id and r.confirmed_revision=ps.revision and r.confirmed_at is not null)) from public.payroll_statements ps where ps.id=statement
$$;
