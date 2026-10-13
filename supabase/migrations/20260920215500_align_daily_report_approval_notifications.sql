create or replace function public.request_daily_report_edit(
  p_report_id uuid,
  p_reason text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_company_id uuid;
  v_request_id uuid;
  v_approver record;
begin
  if v_user_id is null then
    raise exception 'authentication required';
  end if;

  select dr.company_id
  into v_company_id
  from public.daily_reports dr
  join public.company_members cm
    on cm.company_id = dr.company_id
   and cm.user_id = v_user_id
  where dr.id = p_report_id
    and dr.status = 'signed';

  if v_company_id is null then
    raise exception 'signed daily report not found';
  end if;

  insert into public.daily_report_edit_requests(
    report_id, company_id, requested_by, reason
  )
  values(
    p_report_id, v_company_id, v_user_id,
    nullif(trim(coalesce(p_reason, '')), '')
  )
  returning id into v_request_id;

  for v_approver in
    select cm.user_id
    from public.company_members cm
    left join public.member_feature_permissions mfp
      on mfp.company_id = cm.company_id
     and mfp.user_id = cm.user_id
    where cm.company_id = v_company_id
      and cm.user_id <> v_user_id
      and (
        cm.role::text in ('owner', 'admin')
        or coalesce(mfp.can_approve_daily_report_edits, false)
      )
  loop
    perform private.enqueue_notification(
      v_company_id,
      v_approver.user_id,
      'approval',
      '日報の修正承認',
      '確定済み日報の修正申請があります。',
      'daily_report_edit_request',
      v_request_id
    );
  end loop;

  return v_request_id;
end;
$$;
