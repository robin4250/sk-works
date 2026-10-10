-- Additional read contract only. Existing invitation/Auth/history remain unchanged.
-- Uses the existing initial-registration gate, initially OFF.
do $$
declare v_auth_att smallint;
begin
 select attnum into v_auth_att from pg_attribute
 where attrelid='public.employee_registration_invites'::regclass
 and attname='auth_user_id' and atttypid='uuid'::regtype and not attisdropped;
 if v_auth_att is null or not exists(
  select 1 from pg_constraint where conrelid='public.employee_registration_invites'::regclass
  and contype='u' and convalidated and not condeferrable and conkey=array[v_auth_att]::smallint[]
 ) then raise exception 'validated single auth_user_id uniqueness required'; end if;
 if not exists(select 1 from pg_attribute where attrelid='public.workers'::regclass
  and attname='user_id' and atttypid='uuid'::regtype and not attisdropped) then
  raise exception 'workers user_id uuid required'; end if;
end $$;

create function public.employee_initial_registration_status_rows_v2(p_company_id uuid)
returns table(worker_id uuid, invitation_id uuid, invitation_status text,
 initial_registration_completed boolean, approved_at timestamptz,password_changed_at timestamptz,
 delivery_state text,delivery_recorded_at timestamptz,current_invitation boolean)
language plpgsql security definer set search_path='' as $$
begin
 perform private.require_employee_initial_registration_access(p_company_id);
 return query select w.id,i.id,i.status,
 coalesce(i.status='approved' and i.approved_at is not null,false),i.approved_at,i.password_changed_at,
 coalesce(d.delivery_state,'unknown'),d.recorded_at,
 coalesce(w.user_id is not null and i.auth_user_id is not null and w.user_id=i.auth_user_id,false)
 from public.workers w
 left join public.employee_registration_invites i on i.company_id=w.company_id and i.worker_id=w.id
 left join lateral(select h.delivery_state,h.recorded_at from private.employee_initial_registration_delivery_history h
  where h.company_id=w.company_id and h.worker_id=w.id and h.invitation_id=i.id
  order by h.recorded_at desc,h.event_id desc limit 1) d on true
 where w.company_id=p_company_id and w.affiliation='employee';
end $$;
revoke all on function public.employee_initial_registration_status_rows_v2(uuid) from public,anon;
grant execute on function public.employee_initial_registration_status_rows_v2(uuid) to authenticated;
