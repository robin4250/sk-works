-- Owners/admins can directly register and update employee personnel data.
-- Managers/sub-admins keep the configurable 1-3 approver workflow.

create or replace function public.save_worker_personnel_profile(
  p_worker_id uuid,p_payload jsonb
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
  v_actor_role text;
  v_required integer;
begin
  if v_actor is null then raise exception 'ログインが必要です'; end if;
  if not private.can_edit_worker_personnel(p_worker_id) then
    raise exception '社員個人情報を変更する権限がありません';
  end if;

  select w.company_id into v_company
  from public.workers w
  where w.id=p_worker_id;

  if v_company is null then raise exception '社員を確認できません'; end if;

  select cm.role::text into v_actor_role
  from public.company_members cm
  where cm.company_id=v_company
    and cm.user_id=v_actor
  limit 1;

  if v_actor_role is null then
    raise exception '会社への所属が必要です';
  end if;

  select exists(
    select 1
    from public.worker_personnel_profiles p
    where p.worker_id=p_worker_id
  ) into v_existing;

  v_current:=private.worker_personnel_payload(p_worker_id);

  if not v_existing then
    perform private.apply_worker_personnel_payload(p_worker_id,p_payload,v_actor);
    return jsonb_build_object(
      'status','saved',
      'requires_approval',false,
      'saved_directly',true
    );
  end if;

  if v_current=p_payload then
    return jsonb_build_object(
      'status','unchanged',
      'requires_approval',false,
      'saved_directly',false
    );
  end if;

  if v_actor_role in ('owner','admin') then
    perform private.apply_worker_personnel_payload(p_worker_id,p_payload,v_actor);

    update public.worker_personnel_change_requests
    set status='rejected',resolved_at=now()
    where worker_id=p_worker_id
      and status='pending';

    return jsonb_build_object(
      'status','saved',
      'requires_approval',false,
      'saved_directly',true
    );
  end if;

  select count(*)::integer into v_required
  from public.worker_personnel_approvers a
  where a.company_id=v_company
    and a.user_id<>v_actor;

  if v_required<1 then
    raise exception '社員個人情報の承認者を1〜3名で設定してください（申請者本人は承認できません）';
  end if;

  v_required:=least(v_required,3);

  update public.worker_personnel_change_requests
  set status='rejected',resolved_at=now()
  where worker_id=p_worker_id
    and requested_by=v_actor
    and status='pending';

  insert into public.worker_personnel_change_requests(
    company_id,worker_id,requested_by,proposed,required_approvals
  ) values(v_company,p_worker_id,v_actor,p_payload,v_required)
  returning id into v_request;

  insert into public.app_notifications(
    company_id,recipient_user_id,kind,title,body,action_key,action_id
  )
  select v_company,a.user_id,'approval','社員個人情報の変更申請',
    '社員個人情報の変更申請があります。登録済み承認者の承認後に反映されます。',
    'worker_personnel_change',v_request
  from public.worker_personnel_approvers a
  where a.company_id=v_company
    and a.user_id<>v_actor;

  return jsonb_build_object(
    'status','pending',
    'requires_approval',true,
    'request_id',v_request,
    'required_approvals',v_required,
    'saved_directly',false
  );
end
$$;
