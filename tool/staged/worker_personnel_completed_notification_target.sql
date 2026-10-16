-- STAGED ONLY: not a migration and not deployed. No tables, policies or existing functions change.
-- Source contract: main a8fe1e2e; 20261006192517 completion action_id=request;
-- 20261011204715 personnel_view_allowed; 20261002013757 request table grants.
begin;
create function private.worker_personnel_completed_notification_target(
  p_company uuid, p_notification uuid, p_request uuid
) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_actor uuid:=auth.uid(); v_target jsonb;
begin
  if v_actor is null or private.account_access_allowed() is distinct from true then
    raise exception '通知の対象を確認できません' using errcode='42501';
  end if;
  select jsonb_build_object('company_id',r.company_id,'request_id',r.id,
    'worker_id',w.id,'status',r.status)
  into v_target
  from public.app_notifications n
  join public.worker_personnel_change_requests r
    on r.id=p_request and r.id=n.action_id and r.company_id=n.company_id
  join public.workers w on w.id=r.worker_id and w.company_id=r.company_id
  where n.id=p_notification and n.company_id=p_company
    and n.recipient_user_id=v_actor
    and n.action_key='worker_personnel_change_completed'
    and r.status='approved' and r.resolved_at is not null
    -- Notification action fields alone are not an authorization source.
    and r.requested_by=v_actor
    and w.status::text='active'
    and exists(select 1 from public.company_members m
      where m.company_id=p_company and m.user_id=v_actor)
    and (w.user_id=v_actor or private.personnel_view_allowed(p_company));
  if v_target is null then
    raise exception '通知の対象を確認できません' using errcode='42501';
  end if;
  return v_target;
end $$;
revoke all on function private.worker_personnel_completed_notification_target(uuid,uuid,uuid) from public,anon;
grant execute on function private.worker_personnel_completed_notification_target(uuid,uuid,uuid) to authenticated;
create function public.worker_personnel_completed_notification_target(
  p_company uuid,p_notification uuid,p_request uuid
) returns jsonb language sql stable security invoker set search_path='' as $$
  select private.worker_personnel_completed_notification_target(p_company,p_notification,p_request);
$$;
revoke all on function public.worker_personnel_completed_notification_target(uuid,uuid,uuid) from public,anon;
grant execute on function public.worker_personnel_completed_notification_target(uuid,uuid,uuid) to authenticated;
commit;
