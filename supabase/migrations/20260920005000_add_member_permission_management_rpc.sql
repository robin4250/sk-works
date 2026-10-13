create or replace function public.company_member_permission_rows()
returns table(
  user_id uuid,
  display_name text,
  role text,
  can_approve_daily_report_edits boolean,
  can_manage_attendance boolean,
  can_manage_people boolean,
  can_view_invoices boolean,
  can_manage_invoices boolean,
  can_view_admin_site_data boolean,
  can_manage_admin_site_data boolean,
  can_manage_payroll boolean,
  can_manage_partner_chat boolean
)
language sql
security definer
set search_path = public, pg_temp
as $$
  with my_company as (
    select cm.company_id
    from public.company_members cm
    where cm.user_id = auth.uid()
      and cm.role::text in ('owner','admin')
    limit 1
  )
  select
    cm.user_id,
    coalesce(up.display_name, 'SKOユーザー') as display_name,
    cm.role::text,
    case when cm.role::text in ('owner','admin') then true
         else coalesce(p.can_approve_daily_report_edits, cm.role::text = 'manager') end,
    case when cm.role::text in ('owner','admin') then true
         else coalesce(p.can_manage_attendance, cm.role::text = 'manager') end,
    case when cm.role::text in ('owner','admin') then true
         else coalesce(p.can_manage_people, false) end,
    case when cm.role::text in ('owner','admin') then true
         else coalesce(p.can_view_invoices, false) end,
    case when cm.role::text in ('owner','admin') then true
         else coalesce(p.can_manage_invoices, false) end,
    case when cm.role::text in ('owner','admin') then true
         else coalesce(p.can_view_admin_site_data, false) end,
    case when cm.role::text in ('owner','admin') then true
         else coalesce(p.can_manage_admin_site_data, false) end,
    case when cm.role::text in ('owner','admin') then true
         else coalesce(p.can_manage_payroll, false) end,
    case when cm.role::text in ('owner','admin') then true
         else coalesce(p.can_manage_partner_chat, false) end
  from public.company_members cm
  join my_company mc on mc.company_id = cm.company_id
  left join public.user_profiles up on up.user_id = cm.user_id
  left join public.member_feature_permissions p
    on p.company_id = cm.company_id
   and p.user_id = cm.user_id
  order by display_name;
$$;

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

  if not exists (
    select 1 from public.company_members cm
    where cm.company_id = v_company_id
      and cm.user_id = p_user_id
  ) then
    raise exception 'target user is not in company';
  end if;

  if p_role not in ('admin','manager','viewer') then
    raise exception 'invalid role';
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
    coalesce((p_permissions ->> 'can_approve_daily_report_edits')::boolean, false),
    coalesce((p_permissions ->> 'can_manage_attendance')::boolean, false),
    coalesce((p_permissions ->> 'can_manage_people')::boolean, false),
    coalesce((p_permissions ->> 'can_view_invoices')::boolean, false),
    coalesce((p_permissions ->> 'can_manage_invoices')::boolean, false),
    coalesce((p_permissions ->> 'can_view_admin_site_data')::boolean, false),
    coalesce((p_permissions ->> 'can_manage_admin_site_data')::boolean, false),
    coalesce((p_permissions ->> 'can_manage_payroll')::boolean, false),
    coalesce((p_permissions ->> 'can_manage_partner_chat')::boolean, false),
    v_actor,
    now()
  )
  on conflict(company_id, user_id) do update
  set can_approve_daily_report_edits = excluded.can_approve_daily_report_edits,
      can_manage_attendance = excluded.can_manage_attendance,
      can_manage_people = excluded.can_manage_people,
      can_view_invoices = excluded.can_view_invoices,
      can_manage_invoices = excluded.can_manage_invoices,
      can_view_admin_site_data = excluded.can_view_admin_site_data,
      can_manage_admin_site_data = excluded.can_manage_admin_site_data,
      can_manage_payroll = excluded.can_manage_payroll,
      can_manage_partner_chat = excluded.can_manage_partner_chat,
      updated_by = v_actor,
      updated_at = now();
end;
$$;

revoke execute on function public.company_member_permission_rows() from public, anon;
revoke execute on function public.set_member_feature_permissions(uuid, text, jsonb)
  from public, anon;

grant execute on function public.company_member_permission_rows() to authenticated;
grant execute on function public.set_member_feature_permissions(uuid, text, jsonb)
  to authenticated;
