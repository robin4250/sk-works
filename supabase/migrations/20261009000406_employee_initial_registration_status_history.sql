-- Source only: activation is a separate deployment decision. No invitation/Auth mutation.
create table private.employee_initial_registration_rollout (
 company_id uuid primary key references public.companies(id) on delete cascade,
 enabled boolean not null default false
);
alter table private.employee_initial_registration_rollout enable row level security;
revoke all on private.employee_initial_registration_rollout from public,anon,authenticated;
create table private.employee_initial_registration_delivery_history (
 event_id uuid primary key,
 company_id uuid not null,
 worker_id uuid not null,
 invitation_id uuid not null,
 delivery_state text not null check(delivery_state in ('manual_sent','unknown')),
 recorded_by uuid not null,
 recorded_at timestamptz not null default clock_timestamp()
);
alter table private.employee_initial_registration_delivery_history enable row level security;
revoke all on private.employee_initial_registration_delivery_history from public,anon,authenticated;
create index on private.employee_initial_registration_delivery_history(company_id,worker_id,invitation_id,recorded_at desc,event_id);

create function private.require_employee_initial_registration_access(p_company_id uuid)
returns void language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or not exists(select 1 from public.company_members m
  where m.company_id=p_company_id and m.user_id=auth.uid() and m.role::text in ('owner','admin'))
  or not private.source_notification_recipient_eligible(p_company_id,auth.uid()) then
  raise exception 'management permission required' using errcode='42501';
 end if;
 perform 1 from private.employee_initial_registration_rollout where company_id=p_company_id and enabled for share;
 if not found then raise exception 'initial registration status unavailable' using errcode='55000'; end if;
end $$;
revoke all on function private.require_employee_initial_registration_access(uuid) from public,anon,authenticated;

create function public.employee_initial_registration_status_rows(p_company_id uuid)
returns table(worker_id uuid, invitation_id uuid, invitation_status text,
 initial_registration_completed boolean, approved_at timestamptz,password_changed_at timestamptz,
 delivery_state text,delivery_recorded_at timestamptz)
language plpgsql security definer set search_path='' as $$
begin
 perform private.require_employee_initial_registration_access(p_company_id);
 return query select w.id,i.id,i.status,
 coalesce(i.status='approved' and i.approved_at is not null,false),i.approved_at,i.password_changed_at,
 coalesce(d.delivery_state,'unknown'),d.recorded_at
 from public.workers w
 left join public.employee_registration_invites i on i.company_id=w.company_id and i.worker_id=w.id
 left join lateral(select h.delivery_state,h.recorded_at from private.employee_initial_registration_delivery_history h
  where h.company_id=w.company_id and h.worker_id=w.id and h.invitation_id=i.id
  order by h.recorded_at desc,h.event_id desc limit 1) d on true
 where w.company_id=p_company_id and w.affiliation='employee';
end $$;

create function public.record_employee_initial_registration_delivery(
 p_company_id uuid,p_worker_id uuid,p_invitation_id uuid,p_event_id uuid,
 p_delivery_state text,p_explicit_confirmation boolean default false)
returns void language plpgsql security definer set search_path='' as $$
declare v_prior private.employee_initial_registration_delivery_history%rowtype;
begin
 perform private.require_employee_initial_registration_access(p_company_id);
 if p_event_id is null or p_delivery_state is null or p_delivery_state not in ('manual_sent','unknown')
  or (p_delivery_state='manual_sent' and p_explicit_confirmation is distinct from true) then
  raise exception 'explicit manual delivery confirmation required' using errcode='22023';
 end if;
 perform 1 from public.employee_registration_invites i join public.workers w
 on w.id=i.worker_id and w.company_id=i.company_id and w.affiliation='employee'
 where i.id=p_invitation_id and i.worker_id=p_worker_id and i.company_id=p_company_id
 for update of i;
 if not found then raise exception 'invitation not found' using errcode='42501'; end if;
 insert into private.employee_initial_registration_delivery_history
 (event_id,company_id,worker_id,invitation_id,delivery_state,recorded_by)
 values(p_event_id,p_company_id,p_worker_id,p_invitation_id,p_delivery_state,auth.uid())
 on conflict(event_id) do nothing;
 select * into v_prior from private.employee_initial_registration_delivery_history where event_id=p_event_id;
 if v_prior.company_id<>p_company_id or v_prior.worker_id<>p_worker_id or v_prior.invitation_id<>p_invitation_id
  or v_prior.delivery_state<>p_delivery_state or v_prior.recorded_by<>auth.uid() then
  raise exception 'delivery event identity differs' using errcode='22023';
 end if;
end $$;
revoke all on function public.employee_initial_registration_status_rows(uuid) from public,anon;
revoke all on function public.record_employee_initial_registration_delivery(uuid,uuid,uuid,uuid,text,boolean) from public,anon;
grant execute on function public.employee_initial_registration_status_rows(uuid) to authenticated;
grant execute on function public.record_employee_initial_registration_delivery(uuid,uuid,uuid,uuid,text,boolean) to authenticated;
