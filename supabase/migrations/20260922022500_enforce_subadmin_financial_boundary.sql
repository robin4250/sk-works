create or replace function public.set_member_feature_permissions(
  p_user_id uuid,
  p_role text,
  p_permissions jsonb
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor uuid := auth.uid();
  v_company_id uuid;
  v_target_role text;
  v_assignee_count integer;
  v_can_manage_attendance boolean;
  v_can_manage_people boolean;
  v_can_manage_partner_chat boolean;
begin
  select cm.company_id
  into v_company_id
  from public.company_members cm
  where cm.user_id = v_actor
    and cm.role::text in ('owner','admin')
  limit 1;

  if v_company_id is null then
    raise exception 'owner or admin permission required';
  end if;

  select cm.role::text
  into v_target_role
  from public.company_members cm
  where cm.company_id = v_company_id
    and cm.user_id = p_user_id
  limit 1;

  if v_target_role is null then
    raise exception 'target user is not in company';
  end if;

  if v_target_role = 'owner' then
    raise exception 'owner role cannot be changed';
  end if;

  if p_role not in ('admin','manager','viewer') then
    raise exception 'invalid role';
  end if;

  if p_role = 'viewer' and exists (
    select 1 from public.company_approval_assignees
    where company_id = v_company_id
      and user_id = p_user_id
  ) then
    select count(*) into v_assignee_count
    from public.company_approval_assignees
    where company_id = v_company_id;

    if v_assignee_count <= 1 then
      raise exception 'remove approval duty after assigning another approver';
    end if;

    delete from public.company_approval_assignees
    where company_id = v_company_id
      and user_id = p_user_id;
  end if;

  update public.company_members
  set role = p_role
  where company_id = v_company_id
    and user_id = p_user_id;

  if p_role = 'admin' then
    delete from public.member_feature_permissions
    where company_id = v_company_id
      and user_id = p_user_id;
    return;
  end if;

  v_can_manage_attendance :=
    coalesce((p_permissions ->> 'can_manage_attendance')::boolean, false);
  v_can_manage_people :=
    coalesce((p_permissions ->> 'can_manage_people')::boolean, false);
  v_can_manage_partner_chat :=
    coalesce((p_permissions ->> 'can_manage_partner_chat')::boolean, false);

  insert into public.member_feature_permissions(
    company_id,
    user_id,
    can_approve_daily_report_edits,
    can_manage_attendance,
    can_manage_people,
    can_view_invoices,
    can_manage_invoices,
    can_view_admin_site_data,
    can_manage_admin_site_data,
    can_manage_payroll,
    can_manage_partner_chat,
    updated_by,
    updated_at
  )
  values(
    v_company_id,
    p_user_id,
    false,
    v_can_manage_attendance,
    v_can_manage_people,
    false,
    false,
    false,
    false,
    false,
    v_can_manage_partner_chat,
    v_actor,
    now()
  )
  on conflict(company_id, user_id) do update
  set can_approve_daily_report_edits = false,
      can_manage_attendance = excluded.can_manage_attendance,
      can_manage_people = excluded.can_manage_people,
      can_view_invoices = false,
      can_manage_invoices = false,
      can_view_admin_site_data = false,
      can_manage_admin_site_data = false,
      can_manage_payroll = false,
      can_manage_partner_chat = excluded.can_manage_partner_chat,
      updated_by = v_actor,
      updated_at = now();
end;
$$;

revoke execute on function public.set_member_feature_permissions(uuid,text,jsonb)
  from public, anon;
grant execute on function public.set_member_feature_permissions(uuid,text,jsonb)
  to authenticated;
