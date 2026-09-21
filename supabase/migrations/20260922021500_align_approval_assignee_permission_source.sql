update public.member_feature_permissions mfp
set can_approve_daily_report_edits = false,
    can_view_invoices = false,
    can_manage_invoices = false,
    can_view_admin_site_data = false,
    can_manage_admin_site_data = false,
    can_manage_payroll = false,
    updated_at = now()
where exists (
  select 1
  from public.company_members cm
  where cm.company_id = mfp.company_id
    and cm.user_id = mfp.user_id
    and cm.role::text in ('manager','viewer')
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
  v_is_approval_assignee boolean := false;
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

  select exists (
    select 1
    from public.company_approval_assignees caa
    where caa.company_id = v_company_id
      and caa.user_id = v_user_id
  )
  into v_is_approval_assignee;

  if v_role in ('owner','admin') then
    return jsonb_build_object(
      'can_approve_daily_report_edits', v_is_approval_assignee,
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
    return jsonb_build_object(
      'can_approve_daily_report_edits', v_is_approval_assignee,
      'can_manage_attendance', coalesce(v_perm.can_manage_attendance, false),
      'can_manage_people', coalesce(v_perm.can_manage_people, false),
      'can_view_invoices', coalesce(v_perm.can_view_invoices, false),
      'can_manage_invoices', coalesce(v_perm.can_manage_invoices, false),
      'can_view_admin_site_data', coalesce(v_perm.can_view_admin_site_data, false),
      'can_manage_admin_site_data', coalesce(v_perm.can_manage_admin_site_data, false),
      'can_manage_payroll', coalesce(v_perm.can_manage_payroll, false),
      'can_manage_partner_chat', coalesce(v_perm.can_manage_partner_chat, false)
    );
  end if;

  return jsonb_build_object(
    'can_approve_daily_report_edits', v_is_approval_assignee,
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
