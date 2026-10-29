-- Disposable fixture only. Exact existing definitions from read-only catalog; no live rows.
CREATE OR REPLACE FUNCTION private.reauthentication_scope(p_operation text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
 select case p_operation when 'secondary_password.replace' then 'secondary_password'
  when 'secondary_password.change' then 'secondary_password'
  when 'master.feature.set' then 'master_feature'
  when 'master.security_incidents.read' then 'master_security'
  when 'attendance.manage' then 'attendance_management'
  when 'master.security_collector.read' then 'master_security' end
$function$
;
revoke all on function private.reauthentication_scope(text) from public,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION private.reauthentication_required(p_scope text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare required boolean;
begin
 select enabled into required from private.reauthentication_rollout where scope=p_scope for share;
 if not found then raise sqlstate '42501' using message='reauthentication_unavailable'; end if;
 return required;
end $function$
;
revoke all on function private.reauthentication_required(text) from public,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.issue_reauthentication_proof(p_actor uuid, p_session uuid, p_operation text, p_target jsonb, p_proof_hash text)
 RETURNS timestamp with time zone
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$begin
 if coalesce(auth.role(),'')<>'service_role' or p_operation in('secondary_password.change','attendance.manage') then
  raise sqlstate '42501' using message='reauthentication_unavailable';end if;
 return private.issue_reauthentication_proof(p_actor,p_session,p_operation,p_target,p_proof_hash);
end $function$
;
revoke all on function public.issue_reauthentication_proof(uuid,uuid,text,jsonb,text) from public,anon,authenticated,service_role;
grant execute on function public.issue_reauthentication_proof(uuid,uuid,text,jsonb,text) to service_role;
CREATE OR REPLACE FUNCTION private.issue_reauthentication_proof(p_actor uuid, p_session uuid, p_operation text, p_target jsonb, p_proof_hash text)
 RETURNS timestamp with time zone
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare expiry timestamptz; issued timestamptz;fingerprint text;
begin
 if p_actor is null or p_session is null
  or p_proof_hash is null or p_proof_hash !~ '^[0-9a-f]{64}$'
  or private.reauthentication_scope(p_operation) is null
  or not private.reauthentication_required(private.reauthentication_scope(p_operation)) then
  raise sqlstate '42501' using message='reauthentication_unavailable';
 end if;
 if p_operation in('secondary_password.replace','secondary_password.change') and p_target<>jsonb_build_object('user_id',p_actor) then
  raise sqlstate '42501' using message='reauthentication_unavailable';
 elsif p_operation='master.feature.set' and (
  jsonb_typeof(p_target)<>'object' or p_target<>jsonb_build_object('feature_key',p_target->'feature_key','enabled',p_target->'enabled')
  or coalesce(p_target->>'feature_key','') not in ('vehicle_management','route_assignment','traffic_nearest_station','traffic_train_transfer','traffic_bus_stop')
  or coalesce(jsonb_typeof(p_target->'enabled'),'')<>'boolean') then
  raise sqlstate '42501' using message='reauthentication_unavailable';
 elsif p_operation='attendance.manage' and (
  not private.reauthentication_required('secondary_password') or
  p_target is null or jsonb_typeof(p_target)<>'object'
  or p_target<>jsonb_build_object('company_id',p_target->'company_id','action',p_target->'action','items_sha256',p_target->'items_sha256')
  or coalesce(p_target->>'action','') not in ('upsert','delete')
  or coalesce(p_target->>'items_sha256','') !~ '^[0-9a-f]{64}$'
  or (select count(*) from public.company_members where user_id=p_actor)<>1
  or not exists(select 1 from public.company_members where user_id=p_actor
   and company_id::text=p_target->>'company_id' and role::text in ('owner','admin','manager'))) then
  raise sqlstate '42501' using message='reauthentication_unavailable';
 elsif p_operation='master.security_collector.read' and p_target is distinct from '{"scope":"decoy_collector"}'::jsonb then
  raise sqlstate '42501' using message='reauthentication_unavailable';
 elsif p_operation='master.security_incidents.read' and p_target<>'{"scope":"platform"}'::jsonb then
  raise sqlstate '42501' using message='reauthentication_unavailable';
 end if;
 if p_target is null or (p_operation like 'master.%' and not exists(
  select 1 from private.master_admins where user_id=p_actor and enabled)) then
  raise sqlstate '42501' using message='reauthentication_unavailable';
 end if;
 -- Same deletion barrier as the existing Data API account hook; fail closed.
 if not pg_try_advisory_xact_lock_shared(private.account_deletion_barrier_key(p_actor)) then
  raise sqlstate '42501' using message='reauthentication_unavailable';
 end if;
 if exists(select 1 from private.account_deletion_access_restrictions where user_id=p_actor) then
  raise sqlstate '42501' using message='reauthentication_unavailable';
 end if;
 perform 1 from auth.users where id=p_actor and not coalesce(is_anonymous,false)
  and (banned_until is null or banned_until<=clock_timestamp()) for share;
 if not found then raise sqlstate '42501' using message='reauthentication_unavailable';end if;
 perform 1 from auth.sessions where id=p_session and user_id=p_actor
  and (not_after is null or not_after>clock_timestamp()) for share;
 if not found then raise sqlstate '42501' using message='reauthentication_unavailable'; end if;
 if p_operation in('secondary_password.change','attendance.manage') then
  select encode(extensions.digest(password_hash,'sha256'),'hex') into fingerprint
  from public.user_secondary_credentials where user_id=p_actor for share;
  if not found then raise sqlstate '42501' using message='reauthentication_unavailable';end if;
 end if;
 issued:=clock_timestamp(); expiry:=issued+interval '120 seconds';
 insert into private.reauthentication_proofs(proof_hash,actor_id,session_id,operation,target,issued_at,expires_at,secondary_credential_fingerprint)
 values(p_proof_hash,p_actor,p_session,p_operation,p_target,issued,expiry,fingerprint);
 return expiry;
end $function$
;
revoke all on function private.issue_reauthentication_proof(uuid,uuid,text,jsonb,text) from public,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION private.consume_reauthentication_proof(p_operation text, p_target jsonb, p_proof text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare actor uuid:=auth.uid(); v_session uuid; consumed text;fingerprint text;
begin
 if actor is null or not private.account_access_allowed() or p_proof is null or p_proof !~ '^[0-9a-f]{64}$'
  or private.reauthentication_scope(p_operation) is null
  or not private.reauthentication_required(private.reauthentication_scope(p_operation)) then
  raise sqlstate '42501' using message='reauthentication_required';
 end if;
 v_session:=private.require_reauthentication_session();
 begin v_session:=(auth.jwt()->>'session_id')::uuid;
 exception when invalid_text_representation then raise sqlstate '42501' using message='reauthentication_required'; end;
 if v_session is null then raise sqlstate '42501' using message='reauthentication_required'; end if;
 if p_operation like 'master.%' and not public.is_current_user_master_admin() then
  raise sqlstate '42501' using message='reauthentication_required';
 end if;
 if not pg_try_advisory_xact_lock_shared(private.account_deletion_barrier_key(actor)) then
  raise sqlstate '42501' using message='reauthentication_required';
 end if;
 if not private.account_access_allowed() then raise sqlstate '42501' using message='reauthentication_required'; end if;
 perform 1 from auth.sessions s where s.id=v_session and s.user_id=actor
  and (s.not_after is null or s.not_after>clock_timestamp()) for share;
 if not found then raise sqlstate '42501' using message='reauthentication_required'; end if;
 -- Credential changes use one lock order, including primary recovery.
 if p_operation in('secondary_password.replace','secondary_password.change') then
  perform pg_advisory_xact_lock(hashtextextended('sko-secondary-password:'||actor::text,0));
  perform 1 from public.user_secondary_credentials where user_id=actor for update;
 end if;
 if p_operation in('secondary_password.change','attendance.manage') then
  select encode(extensions.digest(password_hash,'sha256'),'hex') into fingerprint
  from public.user_secondary_credentials where user_id=actor for share;
  if not found then raise sqlstate '42501' using message='reauthentication_required';end if;
 end if;
 update private.reauthentication_proofs p set consumed_at=clock_timestamp()
 where p.proof_hash=encode(extensions.digest(p_proof,'sha256'),'hex')
  and p.actor_id=actor and p.session_id=v_session and p.operation=p_operation
  and p.target=p_target and p.secondary_credential_fingerprint is not distinct from fingerprint
  and p.consumed_at is null and p.expires_at>clock_timestamp()
 returning proof_hash into consumed;
 if consumed is null then raise sqlstate '42501' using message='reauthentication_required'; end if;
end $function$
;
revoke all on function private.consume_reauthentication_proof(text,jsonb,text) from public,anon,authenticated,service_role;
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
revoke all on function private.require_reauthentication_session() from public,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION private.sync_bank_document_status()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if auth.uid() is null or not exists (
    select 1 from public.workers w where w.id = new.worker_id and w.company_id = new.company_id and w.user_id = auth.uid()
  ) then raise exception 'own bank account required'; end if;
  new.updated_at := now();
  insert into public.worker_document_statuses(company_id, worker_id, requirement_id, status, original_verified, updated_by, updated_at)
  select new.company_id, new.worker_id, dr.id, 'submitted', false, auth.uid(), now()
  from public.document_requirements dr
  where dr.company_id = new.company_id and dr.name = '銀行口座情報' and dr.is_active
  on conflict (worker_id, requirement_id) do update
  set status = 'submitted', original_verified = false, updated_by = auth.uid(), updated_at = now();
  return new;
end;
$function$
;
revoke all on function private.sync_bank_document_status() from public,anon,authenticated,service_role;
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

create trigger sync_bank_document_status before insert or update on public.worker_private_bank_accounts for each row execute function private.sync_bank_document_status();
