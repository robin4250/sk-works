CREATE OR REPLACE FUNCTION public.decide_worker_personnel_change(p_request_id uuid, p_approve boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_user uuid:=auth.uid();
  v_req public.worker_personnel_change_requests%rowtype;
  v_count integer;
  v_required integer;
begin
  select * into v_req
  from public.worker_personnel_change_requests
  where id=p_request_id
  for update;

  if not found or v_req.status<>'pending' then
    raise exception '変更申請を確認できません';
  end if;
  if v_req.requested_by=v_user then
    raise exception '自分の申請は承認できません';
  end if;
  if not private.is_worker_personnel_approver(v_req.company_id) then
    raise exception '承認権限がありません';
  end if;

  insert into public.worker_personnel_change_approvals(
    request_id,approver_user_id,decision
  )
  values(
    p_request_id,v_user,case when p_approve then 'approve' else 'reject' end
  )
  on conflict(request_id,approver_user_id) do nothing;

  if not p_approve then
    update public.worker_personnel_change_requests
    set status='rejected',resolved_at=now()
    where id=p_request_id;
    return jsonb_build_object('status','rejected');
  end if;

  select count(*) into v_count
  from public.worker_personnel_change_approvals a
  where a.request_id=p_request_id and a.decision='approve';

  v_required:=greatest(1,least(coalesce(v_req.required_approvals,1),3));

  if v_count>=v_required then
    perform private.apply_worker_personnel_payload(
      v_req.worker_id,v_req.proposed,v_user
    );
    update public.worker_personnel_change_requests
    set status='approved',resolved_at=now()
    where id=p_request_id;

    insert into public.app_notifications(
      company_id,recipient_user_id,kind,title,body,action_key,action_id
    )
    values(
      v_req.company_id,v_req.requested_by,'approval',
      '社員個人情報の変更が承認されました',
      format('%s名の承認が完了し、社員個人情報へ反映されました。',v_required),
      'worker_personnel_change_completed',
      p_request_id
    );

    return jsonb_build_object(
      'status','approved',
      'approval_count',v_count,
      'required_approvals',v_required
    );
  end if;

  return jsonb_build_object(
    'status','pending',
    'approval_count',v_count,
    'required_approvals',v_required
  );
end
$function$

