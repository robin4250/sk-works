CREATE OR REPLACE FUNCTION public.save_employee_onboarding_profile(p_address text, p_blood_type text, p_family_composition text, p_emergency_relation text, p_emergency_name text, p_emergency_phone text, p_emergency_address text, p_portrait_path text, p_my_number_front_path text, p_my_number_back_path text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
declare
  v_user_id uuid := auth.uid();
  v_company_id uuid;
  v_invite_id uuid;
  v_reviewer record;
begin
  if v_user_id is null then
    raise exception 'authentication required';
  end if;

  if nullif(trim(coalesce(p_address, '')), '') is null
     or nullif(trim(coalesce(p_blood_type, '')), '') is null
     or nullif(trim(coalesce(p_family_composition, '')), '') is null
     or nullif(trim(coalesce(p_emergency_relation, '')), '') is null
     or nullif(trim(coalesce(p_emergency_name, '')), '') is null
     or nullif(trim(coalesce(p_emergency_phone, '')), '') is null
     or nullif(trim(coalesce(p_emergency_address, '')), '') is null
 then
    raise exception 'required onboarding field missing';
  end if;

  if nullif(trim(coalesce(p_portrait_path,'')),'') is not null
     or nullif(trim(coalesce(p_my_number_front_path,'')),'') is not null
     or nullif(trim(coalesce(p_my_number_back_path,'')),'') is not null then
    raise exception 'official_document_uploads_paused_for_initial_beta';
  end if;

  update public.employee_registration_invites eri
  set address = trim(p_address),
      blood_type = trim(p_blood_type),
      family_composition = trim(p_family_composition),
      emergency_relation = trim(p_emergency_relation),
      emergency_name = trim(p_emergency_name),
      emergency_phone = trim(p_emergency_phone),
      emergency_address = trim(p_emergency_address),
      portrait_path = null,
      my_number_front_path = null,
      my_number_back_path = null,
      status = 'approval_pending',
      submitted_at = now()
  where eri.auth_user_id = v_user_id
    and (eri.password_changed_at is not null or eri.identity_verified_at is not null)
    and eri.status in ('profile_pending','approval_pending')
  returning eri.id, eri.company_id into v_invite_id, v_company_id;

  if v_invite_id is null then
    raise exception 'employee onboarding is not ready for profile submission';
  end if;

  for v_reviewer in
    select distinct cm.user_id
    from public.company_members cm
    left join public.company_approval_assignees caa
      on caa.company_id = cm.company_id
     and caa.user_id = cm.user_id
    where cm.company_id = v_company_id
      and (
        cm.role::text in ('owner','admin')
        or caa.user_id is not null
      )
  loop
    perform private.enqueue_notification(
      v_company_id,
      v_reviewer.user_id,
      'approval',
      '従業員の本登録申請',
      '本人情報の登録が完了しました。本登録を確認してください。',
      'employee_onboarding_approval',
      v_invite_id
    );
  end loop;
end;
$function$

