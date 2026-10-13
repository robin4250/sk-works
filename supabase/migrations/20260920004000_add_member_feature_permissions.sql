create table if not exists public.member_feature_permissions (
  company_id uuid not null references public.companies(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  can_approve_daily_report_edits boolean not null default false,
  can_manage_attendance boolean not null default false,
  can_manage_people boolean not null default false,
  can_view_invoices boolean not null default false,
  can_manage_invoices boolean not null default false,
  can_view_admin_site_data boolean not null default false,
  can_manage_admin_site_data boolean not null default false,
  can_manage_payroll boolean not null default false,
  can_manage_partner_chat boolean not null default false,
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now(),
  primary key(company_id, user_id)
);

alter table public.member_feature_permissions enable row level security;

drop policy if exists "company managers can read feature permissions"
  on public.member_feature_permissions;
create policy "company managers can read feature permissions"
on public.member_feature_permissions
for select
to authenticated
using (
  user_id = auth.uid()
  or exists (
    select 1 from public.company_members cm
    where cm.company_id = member_feature_permissions.company_id
      and cm.user_id = auth.uid()
      and cm.role::text in ('owner','admin')
  )
);

drop policy if exists "owners and admins can manage feature permissions"
  on public.member_feature_permissions;
create policy "owners and admins can manage feature permissions"
on public.member_feature_permissions
for all
to authenticated
using (
  exists (
    select 1 from public.company_members cm
    where cm.company_id = member_feature_permissions.company_id
      and cm.user_id = auth.uid()
      and cm.role::text in ('owner','admin')
  )
)
with check (
  exists (
    select 1 from public.company_members cm
    where cm.company_id = member_feature_permissions.company_id
      and cm.user_id = auth.uid()
      and cm.role::text in ('owner','admin')
  )
);

create or replace function public.current_feature_permissions()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_company_id uuid;
  v_role text;
  v_perm public.member_feature_permissions%rowtype;
begin
  if v_user_id is null then
    return '{}'::jsonb;
  end if;

  select cm.company_id, cm.role::text
  into v_company_id, v_role
  from public.company_members cm
  where cm.user_id = v_user_id
  limit 1;

  if v_company_id is null then
    return '{}'::jsonb;
  end if;

  if v_role in ('owner','admin') then
    return jsonb_build_object(
      'can_approve_daily_report_edits', true,
      'can_manage_attendance', true,
      'can_manage_people', true,
      'can_view_invoices', true,
      'can_manage_invoices', true,
      'can_view_admin_site_data', true,
      'can_manage_admin_site_data', true,
      'can_manage_payroll', true,
      'can_manage_partner_chat', true
    );
  end if;

  select *
  into v_perm
  from public.member_feature_permissions
  where company_id = v_company_id
    and user_id = v_user_id;

  if found then
    return to_jsonb(v_perm)
      - 'company_id'
      - 'user_id'
      - 'updated_by'
      - 'updated_at';
  end if;

  return jsonb_build_object(
    'can_approve_daily_report_edits', v_role = 'manager',
    'can_manage_attendance', v_role = 'manager',
    'can_manage_people', false,
    'can_view_invoices', false,
    'can_manage_invoices', false,
    'can_view_admin_site_data', false,
    'can_manage_admin_site_data', false,
    'can_manage_payroll', false,
    'can_manage_partner_chat', false
  );
end;
$$;

revoke execute on function public.current_feature_permissions() from public, anon;
grant execute on function public.current_feature_permissions() to authenticated;
