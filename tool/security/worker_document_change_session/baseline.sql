-- Synthetic fixture definitions copied from saved read-only catalog; auth schema stays genuine.
CREATE OR REPLACE FUNCTION private.require_reauthentication_session()
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare actor uuid:=auth.uid();sid uuid;
begin
 if actor is null or auth.jwt()->>'role' is distinct from 'authenticated'
  or coalesce(auth.jwt()->>'is_anonymous','false')<>'false'
  or not private.account_access_allowed() then
  raise sqlstate '42501' using message='reauthentication_required';
 end if;
 begin sid:=(auth.jwt()->>'session_id')::uuid;
 exception when invalid_text_representation then raise sqlstate '42501' using message='reauthentication_required';end;
 if sid is null or not pg_try_advisory_xact_lock_shared(private.account_deletion_barrier_key(actor)) then
  raise sqlstate '42501' using message='reauthentication_required';end if;
 perform 1 from auth.users where id=actor and not coalesce(is_anonymous,false)
  and (banned_until is null or banned_until<=clock_timestamp()) for share;
 if not found then raise sqlstate '42501' using message='reauthentication_required';end if;
 perform 1 from auth.sessions where id=sid and user_id=actor
  and (not_after is null or not_after>clock_timestamp()) for share;
 if not found then raise sqlstate '42501' using message='reauthentication_required';end if;
 return sid;
end $function$
;
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
revoke all on function private.require_reauthentication_session() from public,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION private.account_access_allowed()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select auth.uid() is not null and not exists(
  select 1 from private.account_deletion_access_restrictions where user_id=auth.uid())
$function$
;
revoke all on function private.account_access_allowed() from public;
grant execute on function private.account_access_allowed() to anon,authenticated,service_role;
