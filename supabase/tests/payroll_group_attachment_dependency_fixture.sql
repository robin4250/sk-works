-- Exact staged helper; rollout is synthetic isolated prerequisite only.
create table private.group_checkout_rollout(company_id uuid,enabled boolean);
create function private.group_checkout_anchor(p_anchor uuid)
returns public.attendance_verifications language plpgsql security definer set search_path='' as $$
declare v_anchor public.attendance_verifications%rowtype;
begin
  if auth.uid() is null or not private.account_access_allowed() then
    raise exception 'attendance access unavailable';
  end if;
  select a.* into v_anchor from public.attendance_verifications a
  join public.workers w on w.id=a.worker_id and w.company_id=a.company_id
  join public.company_members m on m.company_id=a.company_id and m.user_id=w.user_id
  join private.group_checkout_rollout g on g.company_id=a.company_id and g.enabled
  where a.id=p_anchor and a.event_type='clock_in' and a.site_id is not null
    and a.route_assignment_id is null and a.work_date is not null
    and w.user_id=auth.uid() and w.status='active';
  if not found then raise exception 'group checkout is disabled or anchor unavailable'; end if;
  return v_anchor;
end $$;
revoke all on function private.group_checkout_anchor(uuid) from public,anon,authenticated;

