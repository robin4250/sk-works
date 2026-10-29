-- Disposable business-only fixture. Real GoTrue keeps its own auth schema.
create schema if not exists private;
create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;
create table public.companies(id uuid primary key,name text not null);
create table public.company_members(company_id uuid not null references public.companies(id),user_id uuid not null,role text not null,primary key(company_id,user_id));
create table public.member_feature_permissions(company_id uuid,user_id uuid,
 can_approve_daily_report_edits boolean default false,can_manage_attendance boolean default false,
 can_manage_people boolean default false,can_view_invoices boolean default false,can_manage_invoices boolean default false,
 can_view_admin_site_data boolean default false,can_manage_admin_site_data boolean default false,
 can_manage_payroll boolean default false,can_manage_partner_chat boolean default false,
 primary key(company_id,user_id));
create table public.workers(id uuid primary key,company_id uuid not null references public.companies(id),user_id uuid,status text not null default 'active');
create table public.document_requirements(id uuid primary key,company_id uuid not null,name text not null,is_active boolean not null default true);
create table public.worker_document_statuses(company_id uuid,worker_id uuid,requirement_id uuid,status text,original_verified boolean,updated_by uuid,updated_at timestamptz,attachment_path text,notes text,unique(worker_id,requirement_id));
create table private.account_deletion_access_restrictions(user_id uuid primary key);
create function private.account_deletion_barrier_key(p_actor uuid) returns bigint language sql immutable as $$select hashtextextended('deletion:'||p_actor::text,0)$$;
create function private.account_access_allowed() returns boolean language sql stable security definer set search_path='' as $$select auth.uid() is not null and not exists(select 1 from private.account_deletion_access_restrictions where user_id=auth.uid())$$;
create table private.master_admins(user_id uuid primary key,enabled boolean not null);
create function public.is_current_user_master_admin() returns boolean language sql stable security definer set search_path='' as $$select exists(select 1 from private.master_admins where user_id=auth.uid() and enabled)$$;
create table public.user_secondary_credentials(user_id uuid primary key,password_hash text not null);
create table private.reauthentication_rollout(scope text primary key check(scope in('secondary_password','master_feature','master_security','attendance_management')),enabled boolean not null default false);
insert into private.reauthentication_rollout(scope) values('secondary_password'),('master_feature'),('master_security'),('attendance_management');
create table private.reauthentication_proofs(proof_hash text primary key check(proof_hash ~ '^[0-9a-f]{64}$'),actor_id uuid not null,session_id uuid not null,operation text not null,target jsonb not null,issued_at timestamptz not null default clock_timestamp(),expires_at timestamptz not null,consumed_at timestamptz,secondary_credential_fingerprint text,check(expires_at>issued_at and expires_at<=issued_at+interval '120 seconds'));
alter table private.reauthentication_proofs enable row level security;
revoke all on private.reauthentication_proofs,private.reauthentication_rollout from public,anon,authenticated,service_role;
create table public.worker_private_bank_accounts(worker_id uuid primary key references public.workers(id),company_id uuid not null references public.companies(id),
 bank_name text not null check(length(trim(bank_name)) between 1 and 100),branch_name text not null check(length(trim(branch_name)) between 1 and 100),
 account_type text not null check(account_type in('普通','当座','貯蓄')),account_number text not null check(account_number ~ '^[0-9]{7}$'),
 account_holder text not null check(length(trim(account_holder)) between 1 and 100),updated_at timestamptz not null default now());
CREATE OR REPLACE FUNCTION private.has_company_feature(p_company_id uuid, p_feature text)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
declare
  v_user_id uuid := auth.uid();
  v_role text;
  v_perm public.member_feature_permissions%rowtype;
begin
  if v_user_id is null or p_company_id is null then
    return false;
  end if;

  select cm.role::text
  into v_role
  from public.company_members cm
  where cm.company_id = p_company_id
    and cm.user_id = v_user_id
  limit 1;

  if v_role is null then
    return false;
  end if;

  if v_role in ('owner', 'admin') then
    return true;
  end if;

  select *
  into v_perm
  from public.member_feature_permissions
  where company_id = p_company_id
    and user_id = v_user_id;

  if not found then
    return case
      when v_role = 'manager'
       and p_feature in (
         'can_manage_attendance',
         'can_approve_daily_report_edits'
       )
      then true
      else false
    end;
  end if;

  return case p_feature
    when 'can_view_invoices' then
      v_perm.can_view_invoices or v_perm.can_manage_invoices
    when 'can_manage_invoices' then
      v_perm.can_manage_invoices
    when 'can_view_admin_site_data' then
      false
    when 'can_manage_admin_site_data' then
      false
    when 'can_manage_payroll' then
      v_perm.can_manage_payroll
    when 'can_manage_people' then
      v_perm.can_manage_people
    when 'can_manage_attendance' then
      v_perm.can_manage_attendance
    when 'can_approve_daily_report_edits' then
      v_perm.can_approve_daily_report_edits
    when 'can_manage_partner_chat' then
      v_perm.can_manage_partner_chat
    else false
  end;
end;
$function$
;
alter table public.worker_private_bank_accounts enable row level security;
create policy account_deletion_access_guard on public.worker_private_bank_accounts as restrictive for all to authenticated using((select private.account_access_allowed())) with check((select private.account_access_allowed()));
create policy bank_read on public.worker_private_bank_accounts for select to authenticated using(
 exists(select 1 from public.workers w where w.id=worker_id and w.company_id=worker_private_bank_accounts.company_id and w.user_id=(select auth.uid())) or private.has_company_feature(company_id,'can_manage_payroll'));
create policy bank_self_insert on public.worker_private_bank_accounts for insert to authenticated with check(
 exists(select 1 from public.workers w where w.id=worker_id and w.company_id=worker_private_bank_accounts.company_id and w.user_id=(select auth.uid())));
create policy bank_self_update on public.worker_private_bank_accounts for update to authenticated using(
 exists(select 1 from public.workers w where w.id=worker_id and w.company_id=worker_private_bank_accounts.company_id and w.user_id=(select auth.uid()))) with check(
 exists(select 1 from public.workers w where w.id=worker_id and w.company_id=worker_private_bank_accounts.company_id and w.user_id=(select auth.uid())));
grant usage on schema public,auth,private to authenticated,service_role;
grant execute on function private.account_access_allowed() to authenticated;
grant select on public.workers,public.company_members to authenticated;
grant insert,select,update on public.worker_private_bank_accounts to authenticated;
revoke all on public.worker_document_statuses,public.member_feature_permissions,private.account_deletion_access_restrictions from public,anon,authenticated,service_role;
-- Fixture-only immutable payroll/original evidence sentinels, never feature writes.
create schema payroll_final_private;
create table public.payroll_statements(id uuid primary key,company_id uuid,worker_id uuid,value jsonb);
create table payroll_final_private.documents(statement_id uuid primary key,value jsonb);
create table payroll_final_private.history(id uuid primary key,value jsonb);
