create or replace function public.save_worker_personnel_profile(
  p_worker_id uuid,
  p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_company uuid;
  v_existing boolean;
  v_request uuid;
  v_current jsonb;
  v_actor uuid:=auth.uid();
  v_requires_approval boolean:=false;
begin
  if v_actor is null then raise exception 'ログインが必要です'; end if;
  if not private.can_edit_worker_personnel(p_worker_id) then
    raise exception '社員個人情報を変更する権限がありません';
  end if;

  select w.company_id into v_company
  from public.workers w
  where w.id=p_worker_id;
  if v_company is null then raise exception '社員を確認できません'; end if;

  select exists(
    select 1 from public.worker_personnel_profiles p
    where p.worker_id=p_worker_id
  ) into v_existing;

  v_current:=private.worker_personnel_payload(p_worker_id);

  if not v_existing then
    perform private.apply_worker_personnel_payload(p_worker_id,p_payload,v_actor);
    return jsonb_build_object('status','saved','requires_approval',false);
  end if;

  if v_current = p_payload then
    return jsonb_build_object('status','unchanged','requires_approval',false);
  end if;

  v_requires_approval :=
    (
      coalesce(v_current->>'name','') <> coalesce(p_payload->>'name','')
      and coalesce(v_current->>'name','') <> ''
    )
    or (
      coalesce(v_current->>'blood_type','') <> coalesce(p_payload->>'blood_type','')
      and coalesce(v_current->>'blood_type','') <> ''
    )
    or (
      coalesce(v_current->>'role','') <> coalesce(p_payload->>'role','')
      and coalesce(v_current->>'role','') <> ''
    )
    or (
      coalesce(v_current->>'phone','') <> coalesce(p_payload->>'phone','')
      and coalesce(v_current->>'phone','') <> ''
    )
    or (
      coalesce(v_current->>'address','') <> coalesce(p_payload->>'address','')
      and coalesce(v_current->>'address','') <> ''
    )
    or (
      coalesce(v_current->>'emergency_name','') <> coalesce(p_payload->>'emergency_name','')
      and coalesce(v_current->>'emergency_name','') <> ''
    )
    or (
      coalesce(v_current->>'emergency_relation','') <> coalesce(p_payload->>'emergency_relation','')
      and coalesce(v_current->>'emergency_relation','') <> ''
    )
    or (
      coalesce(v_current->>'emergency_phone','') <> coalesce(p_payload->>'emergency_phone','')
      and coalesce(v_current->>'emergency_phone','') <> ''
    )
    or (
      coalesce(v_current->>'emergency_address','') <> coalesce(p_payload->>'emergency_address','')
      and coalesce(v_current->>'emergency_address','') <> ''
    );

  if not v_requires_approval then
    perform private.apply_worker_personnel_payload(p_worker_id,p_payload,v_actor);
    return jsonb_build_object('status','saved','requires_approval',false);
  end if;

  if (
    select count(distinct u.user_id)
    from (
      select a.user_id
      from public.company_approval_assignees a
      where a.company_id=v_company
      union
      select cm.user_id
      from public.company_members cm
      where cm.company_id=v_company
        and cm.role::text in ('owner','admin')
    ) u
    where u.user_id<>v_actor
  ) < 2 then
    raise exception '社員個人情報の編集には承認者が2名必要です';
  end if;

  update public.worker_personnel_change_requests
  set status='rejected',resolved_at=now()
  where worker_id=p_worker_id
    and requested_by=v_actor
    and status='pending';

  insert into public.worker_personnel_change_requests(
    company_id,worker_id,requested_by,proposed
  )
  values(v_company,p_worker_id,v_actor,p_payload)
  returning id into v_request;

  insert into public.app_notifications(
    company_id,recipient_user_id,kind,title,body,action_key,action_id
  )
  select distinct
    v_company,u.user_id,'approval',
    '社員個人情報の変更申請',
    '社員個人情報の変更申請があります。2名の承認後に反映されます。',
    'worker_personnel_change',
    v_request
  from (
    select a.user_id
    from public.company_approval_assignees a
    where a.company_id=v_company
    union
    select cm.user_id
    from public.company_members cm
    where cm.company_id=v_company
      and cm.role::text in ('owner','admin')
  ) u
  where u.user_id<>v_actor;

  return jsonb_build_object(
    'status','pending',
    'requires_approval',true,
    'request_id',v_request
  );
end
$$;
