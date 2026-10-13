create or replace function public.paid_leave_worker_summary(p_worker_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor uuid := auth.uid();
  v_company_id uuid;
  v_worker_user_id uuid;
  v_granted numeric := 0;
  v_used numeric := 0;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  select w.company_id,w.user_id into v_company_id,v_worker_user_id
  from public.workers w where w.id=p_worker_id limit 1;
  if v_company_id is null then raise exception 'worker not found'; end if;
  if v_worker_user_id is distinct from v_actor
     and not exists (
       select 1 from public.company_members cm
       where cm.company_id=v_company_id
         and cm.user_id=v_actor
         and cm.role::text in ('owner','admin','manager')
     ) then
    raise exception 'worker paid leave summary not accessible';
  end if;
  select coalesce(wps.paid_leave_granted_days,0)
    into v_granted
  from public.worker_payroll_settings wps
  where wps.worker_id=p_worker_id limit 1;
  v_granted := coalesce(v_granted,0);
  select count(*) into v_used
  from public.paid_leave_requests r
  where r.worker_id=p_worker_id and r.status='approved';
  return jsonb_build_object(
    'granted_days',v_granted,
    'used_days',v_used,
    'remaining_days',greatest(v_granted-v_used,0)
  );
end;
$$;
revoke execute on function public.paid_leave_worker_summary(uuid)
  from public, anon;
grant execute on function public.paid_leave_worker_summary(uuid)
  to authenticated;
