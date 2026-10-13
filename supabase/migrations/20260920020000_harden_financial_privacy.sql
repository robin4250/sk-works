create or replace function private.has_company_feature(
  p_company_id uuid,
  p_feature text
)
returns boolean
language plpgsql
stable
security definer
set search_path = public, private, pg_temp
as $$
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
    return false;
  end if;

  return case p_feature
    when 'can_view_invoices' then
      v_perm.can_view_invoices or v_perm.can_manage_invoices
    when 'can_manage_invoices' then
      v_perm.can_manage_invoices
    when 'can_view_admin_site_data' then
      v_perm.can_view_admin_site_data or v_perm.can_manage_admin_site_data
    when 'can_manage_admin_site_data' then
      v_perm.can_manage_admin_site_data
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
$$;

-- Ordinary company rows are readable by members, but direct mutation is admin-only.
drop policy if exists "companies_member_access" on public.companies;
drop policy if exists "company members can read company" on public.companies;
drop policy if exists "owners and admins can update company" on public.companies;
drop policy if exists "owners and admins can delete company" on public.companies;

create policy "company members can read company"
on public.companies
for select
to authenticated
using (
  exists (
    select 1 from public.company_members cm
    where cm.company_id = companies.id
      and cm.user_id = auth.uid()
  )
);

create policy "owners and admins can update company"
on public.companies
for update
to authenticated
using (
  exists (
    select 1 from public.company_members cm
    where cm.company_id = companies.id
      and cm.user_id = auth.uid()
      and cm.role::text in ('owner','admin')
  )
)
with check (
  exists (
    select 1 from public.company_members cm
    where cm.company_id = companies.id
      and cm.user_id = auth.uid()
      and cm.role::text in ('owner','admin')
  )
);

create policy "owners and admins can delete company"
on public.companies
for delete
to authenticated
using (
  exists (
    select 1 from public.company_members cm
    where cm.company_id = companies.id
      and cm.user_id = auth.uid()
      and cm.role::text in ('owner','admin')
  )
);

-- Bank account information is isolated from the generally readable company row.
create table if not exists public.company_private_billing_settings (
  company_id uuid primary key references public.companies(id) on delete cascade,
  bank_name text,
  bank_branch text,
  bank_account_type text,
  bank_account_number text,
  bank_account_holder text,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

insert into public.company_private_billing_settings (
  company_id,
  bank_name,
  bank_branch,
  bank_account_type,
  bank_account_number,
  bank_account_holder
)
select
  id,
  bank_name,
  bank_branch,
  bank_account_type,
  bank_account_number,
  bank_account_holder
from public.companies
where bank_name is not null
   or bank_branch is not null
   or bank_account_type is not null
   or bank_account_number is not null
   or bank_account_holder is not null
on conflict (company_id) do update
set bank_name = excluded.bank_name,
    bank_branch = excluded.bank_branch,
    bank_account_type = excluded.bank_account_type,
    bank_account_number = excluded.bank_account_number,
    bank_account_holder = excluded.bank_account_holder,
    updated_at = now();

alter table public.company_private_billing_settings enable row level security;

drop policy if exists "authorized users can read private billing settings"
  on public.company_private_billing_settings;
drop policy if exists "authorized users can insert private billing settings"
  on public.company_private_billing_settings;
drop policy if exists "authorized users can update private billing settings"
  on public.company_private_billing_settings;
drop policy if exists "authorized users can delete private billing settings"
  on public.company_private_billing_settings;

create policy "authorized users can read private billing settings"
on public.company_private_billing_settings
for select
to authenticated
using (
  private.has_company_feature(company_id, 'can_view_invoices')
);

create policy "authorized users can insert private billing settings"
on public.company_private_billing_settings
for insert
to authenticated
with check (
  private.has_company_feature(company_id, 'can_manage_invoices')
);

create policy "authorized users can update private billing settings"
on public.company_private_billing_settings
for update
to authenticated
using (
  private.has_company_feature(company_id, 'can_manage_invoices')
)
with check (
  private.has_company_feature(company_id, 'can_manage_invoices')
);

create policy "authorized users can delete private billing settings"
on public.company_private_billing_settings
for delete
to authenticated
using (
  private.has_company_feature(company_id, 'can_manage_invoices')
);

-- Do not leave migrated bank information in the generally readable company row.
update public.companies
set bank_name = null,
    bank_branch = null,
    bank_account_type = null,
    bank_account_number = null,
    bank_account_holder = null
where bank_name is not null
   or bank_branch is not null
   or bank_account_type is not null
   or bank_account_number is not null
   or bank_account_holder is not null;

-- Initial onboarding writes bank information only to the protected table.
create or replace function public.complete_initial_company_profile(
  p_display_name text,
  p_company_name text,
  p_postal_code text default null,
  p_address text default null,
  p_phone text default null,
  p_fax text default null,
  p_email text default null,
  p_bank_name text default null,
  p_bank_branch text default null,
  p_bank_account_type text default null,
  p_bank_account_number text default null,
  p_bank_account_holder text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_company_id uuid;
  v_role text;
begin
  if v_user_id is null then
    raise exception 'authentication required';
  end if;

  if nullif(trim(p_display_name), '') is null then
    raise exception 'display name is required';
  end if;

  if nullif(trim(p_company_name), '') is null then
    raise exception 'company name is required';
  end if;

  select cm.company_id, cm.role::text
  into v_company_id, v_role
  from public.company_members cm
  where cm.user_id = v_user_id
  limit 1;

  if v_company_id is null then
    perform public.create_company(trim(p_company_name));

    select cm.company_id, cm.role::text
    into v_company_id, v_role
    from public.company_members cm
    where cm.user_id = v_user_id
    limit 1;
  elsif v_role not in ('owner', 'admin') then
    raise exception 'owner or admin role required';
  end if;

  if v_company_id is null then
    raise exception 'company membership was not created';
  end if;

  insert into public.user_profiles (
    user_id,
    display_name,
    phone,
    updated_at
  )
  values (
    v_user_id,
    trim(p_display_name),
    nullif(trim(coalesce(p_phone, '')), ''),
    now()
  )
  on conflict (user_id) do update
  set display_name = excluded.display_name,
      phone = excluded.phone,
      updated_at = now();

  update public.companies
  set name = trim(p_company_name),
      postal_code = nullif(trim(coalesce(p_postal_code, '')), ''),
      address = nullif(trim(coalesce(p_address, '')), ''),
      phone = nullif(trim(coalesce(p_phone, '')), ''),
      fax = nullif(trim(coalesce(p_fax, '')), ''),
      email = nullif(trim(coalesce(p_email, '')), '')
  where id = v_company_id;

  insert into public.company_private_billing_settings (
    company_id,
    bank_name,
    bank_branch,
    bank_account_type,
    bank_account_number,
    bank_account_holder,
    updated_by,
    updated_at
  )
  values (
    v_company_id,
    nullif(trim(coalesce(p_bank_name, '')), ''),
    nullif(trim(coalesce(p_bank_branch, '')), ''),
    nullif(trim(coalesce(p_bank_account_type, '')), ''),
    nullif(trim(coalesce(p_bank_account_number, '')), ''),
    nullif(trim(coalesce(p_bank_account_holder, '')), ''),
    v_user_id,
    now()
  )
  on conflict (company_id) do update
  set bank_name = excluded.bank_name,
      bank_branch = excluded.bank_branch,
      bank_account_type = excluded.bank_account_type,
      bank_account_number = excluded.bank_account_number,
      bank_account_holder = excluded.bank_account_holder,
      updated_by = v_user_id,
      updated_at = now();

  return v_company_id;
end;
$$;

-- Invoice data is never readable merely because someone belongs to the company.
drop policy if exists "company members can read invoices" on public.invoices;
drop policy if exists "managers can manage invoices" on public.invoices;

create policy "authorized users can read invoices"
on public.invoices for select to authenticated
using (
  private.has_company_feature(company_id, 'can_view_invoices')
);

create policy "authorized users can insert invoices"
on public.invoices for insert to authenticated
with check (
  private.has_company_feature(company_id, 'can_manage_invoices')
);

create policy "authorized users can update invoices"
on public.invoices for update to authenticated
using (
  private.has_company_feature(company_id, 'can_manage_invoices')
)
with check (
  private.has_company_feature(company_id, 'can_manage_invoices')
);

create policy "authorized users can delete invoices"
on public.invoices for delete to authenticated
using (
  private.has_company_feature(company_id, 'can_manage_invoices')
);

drop policy if exists "company members can read invoice site calculations"
  on public.invoice_site_calculations;
drop policy if exists "managers can manage invoice site calculations"
  on public.invoice_site_calculations;

create policy "authorized users can read invoice site calculations"
on public.invoice_site_calculations for select to authenticated
using (
  private.has_company_feature(company_id, 'can_view_invoices')
);

create policy "authorized users can insert invoice site calculations"
on public.invoice_site_calculations for insert to authenticated
with check (
  private.has_company_feature(company_id, 'can_manage_invoices')
);

create policy "authorized users can update invoice site calculations"
on public.invoice_site_calculations for update to authenticated
using (
  private.has_company_feature(company_id, 'can_manage_invoices')
)
with check (
  private.has_company_feature(company_id, 'can_manage_invoices')
);

create policy "authorized users can delete invoice site calculations"
on public.invoice_site_calculations for delete to authenticated
using (
  private.has_company_feature(company_id, 'can_manage_invoices')
);

drop policy if exists "company members can read invoice detail lines"
  on public.invoice_detail_lines;
drop policy if exists "managers can manage invoice detail lines"
  on public.invoice_detail_lines;

create policy "authorized users can read invoice detail lines"
on public.invoice_detail_lines for select to authenticated
using (
  private.has_company_feature(company_id, 'can_view_invoices')
);

create policy "authorized users can insert invoice detail lines"
on public.invoice_detail_lines for insert to authenticated
with check (
  private.has_company_feature(company_id, 'can_manage_invoices')
);

create policy "authorized users can update invoice detail lines"
on public.invoice_detail_lines for update to authenticated
using (
  private.has_company_feature(company_id, 'can_manage_invoices')
)
with check (
  private.has_company_feature(company_id, 'can_manage_invoices')
);

create policy "authorized users can delete invoice detail lines"
on public.invoice_detail_lines for delete to authenticated
using (
  private.has_company_feature(company_id, 'can_manage_invoices')
);

-- Admin-only site financial data honors explicit sub-admin permissions.
drop policy if exists "owners and admins can read site financial settings"
  on public.site_financial_settings;
drop policy if exists "owners and admins can manage site financial settings"
  on public.site_financial_settings;

create policy "authorized users can read site financial settings"
on public.site_financial_settings for select to authenticated
using (
  private.has_company_feature(company_id, 'can_view_admin_site_data')
);

create policy "authorized users can insert site financial settings"
on public.site_financial_settings for insert to authenticated
with check (
  private.has_company_feature(company_id, 'can_manage_admin_site_data')
);

create policy "authorized users can update site financial settings"
on public.site_financial_settings for update to authenticated
using (
  private.has_company_feature(company_id, 'can_manage_admin_site_data')
)
with check (
  private.has_company_feature(company_id, 'can_manage_admin_site_data')
);

create policy "authorized users can delete site financial settings"
on public.site_financial_settings for delete to authenticated
using (
  private.has_company_feature(company_id, 'can_manage_admin_site_data')
);

-- Payroll is readable by the worker themself, or by an explicitly authorized payroll manager.
drop policy if exists "workers and managers can read payroll statements"
  on public.payroll_statements;
drop policy if exists "owners and admins can manage payroll statements"
  on public.payroll_statements;

create policy "worker or authorized manager can read payroll statements"
on public.payroll_statements for select to authenticated
using (
  exists (
    select 1 from public.workers w
    where w.id = payroll_statements.worker_id
      and w.user_id = auth.uid()
  )
  or private.has_company_feature(company_id, 'can_manage_payroll')
);

create policy "authorized payroll managers can insert payroll statements"
on public.payroll_statements for insert to authenticated
with check (
  private.has_company_feature(company_id, 'can_manage_payroll')
);

create policy "authorized payroll managers can update payroll statements"
on public.payroll_statements for update to authenticated
using (
  private.has_company_feature(company_id, 'can_manage_payroll')
)
with check (
  private.has_company_feature(company_id, 'can_manage_payroll')
);

create policy "authorized payroll managers can delete payroll statements"
on public.payroll_statements for delete to authenticated
using (
  private.has_company_feature(company_id, 'can_manage_payroll')
);

-- Invoice settings are changed through a narrow RPC instead of granting
-- sub-admins update access to the entire company row.
create or replace function public.save_invoice_settings(
  p_tax_rate numeric,
  p_welfare_rate numeric,
  p_template_title text,
  p_footer_note text,
  p_bank_name text,
  p_bank_branch text,
  p_bank_account_type text,
  p_bank_account_number text,
  p_bank_account_holder text
)
returns void
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_company_id uuid;
begin
  if v_user_id is null then
    raise exception 'authentication required';
  end if;

  select cm.company_id
  into v_company_id
  from public.company_members cm
  where cm.user_id = v_user_id
  limit 1;

  if v_company_id is null
     or not private.has_company_feature(v_company_id, 'can_manage_invoices') then
    raise exception 'invoice management permission required';
  end if;

  if p_tax_rate is null or p_tax_rate < 0 or p_tax_rate > 100 then
    raise exception 'invalid tax rate';
  end if;

  if p_welfare_rate is null or p_welfare_rate < 0 or p_welfare_rate > 100 then
    raise exception 'invalid welfare rate';
  end if;

  update public.companies
  set tax_rate = p_tax_rate,
      default_welfare_rate = p_welfare_rate,
      invoice_template_title = coalesce(
        nullif(trim(coalesce(p_template_title, '')), ''),
        '請求書'
      ),
      invoice_footer_note = nullif(trim(coalesce(p_footer_note, '')), '')
  where id = v_company_id;

  insert into public.company_private_billing_settings (
    company_id,
    bank_name,
    bank_branch,
    bank_account_type,
    bank_account_number,
    bank_account_holder,
    updated_by,
    updated_at
  )
  values (
    v_company_id,
    nullif(trim(coalesce(p_bank_name, '')), ''),
    nullif(trim(coalesce(p_bank_branch, '')), ''),
    nullif(trim(coalesce(p_bank_account_type, '')), ''),
    nullif(trim(coalesce(p_bank_account_number, '')), ''),
    nullif(trim(coalesce(p_bank_account_holder, '')), ''),
    v_user_id,
    now()
  )
  on conflict (company_id) do update
  set bank_name = excluded.bank_name,
      bank_branch = excluded.bank_branch,
      bank_account_type = excluded.bank_account_type,
      bank_account_number = excluded.bank_account_number,
      bank_account_holder = excluded.bank_account_holder,
      updated_by = v_user_id,
      updated_at = now();
end;
$$;

revoke execute on function public.save_invoice_settings(
  numeric, numeric, text, text, text, text, text, text, text
) from public, anon;
grant execute on function public.save_invoice_settings(
  numeric, numeric, text, text, text, text, text, text, text
) to authenticated;
