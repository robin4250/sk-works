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

CREATE OR REPLACE FUNCTION private.payroll_allowed(cid uuid, capability text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select auth.uid() is not null and exists(select 1 from public.company_members m where m.company_id=cid and m.user_id=auth.uid()) and (
 case capability
 when 'admin' then exists(select 1 from public.company_members m where m.company_id=cid and m.user_id=auth.uid() and m.role::text in ('owner','admin'))
 when 'view' then private.has_company_feature(cid,'can_manage_payroll') or auth.uid()=any(private.payroll_approver_ids(cid)) or exists(select 1 from public.payroll_access a where a.company_id=cid and a.user_id=auth.uid() and (a.can_view or a.can_edit))
 when 'edit' then private.has_company_feature(cid,'can_manage_payroll') or exists(select 1 from public.payroll_access a where a.company_id=cid and a.user_id=auth.uid() and a.can_edit)
 else false end) or (capability='view' and auth.uid() is not null and exists(select 1 from private.professional_invites i where i.company_id=cid and i.claimed_by=auth.uid() and i.status='approved' and i.payroll_access<>'none'));

$function$
;

CREATE OR REPLACE FUNCTION private.payroll_approver_ids(cid uuid)
 RETURNS uuid[]
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select coalesce((select array_agg(user_id order by position) from public.payroll_approvers where company_id=cid),
 (select array[m.user_id] from public.company_members m where m.company_id=cid and m.role::text in ('owner','admin') order by case when m.role::text='owner' then 0 else 1 end,m.user_id limit 1),'{}'::uuid[])
$function$
;
