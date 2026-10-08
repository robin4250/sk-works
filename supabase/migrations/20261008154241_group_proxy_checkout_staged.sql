-- Staged OFF. No gate rows are inserted; no existing attendance is repaired.
create table private.group_checkout_rollout (
  company_id uuid primary key references public.companies(id) on delete cascade,
  enabled boolean not null default false
);
alter table private.group_checkout_rollout enable row level security;
revoke all on private.group_checkout_rollout from public,anon,authenticated;

alter table public.attendance_verifications add column evidence_origin text;
alter table public.attendance_verifications add column proxy_actor_user_id uuid;
alter table public.attendance_verifications add constraint attendance_proxy_origin_check check (
  (evidence_origin is null and proxy_actor_user_id is null)
  or (evidence_origin is not null and evidence_origin='team_proxy' and event_type='clock_out'
      and source_clock_in_id is not null and proxy_actor_user_id is not null
      and created_by is not null and proxy_actor_user_id=created_by and verification_mode='manual'
      and latitude is null and longitude is null and accuracy_m is null
      and distance_to_site_m is null and photo_storage_path is null)
);

create table private.group_checkout_requests (
  company_id uuid not null references public.companies(id) on delete cascade,
  actor_user_id uuid not null,
  request_token uuid not null,
  anchor_id uuid not null,
  source_ids uuid[] not null,
  result jsonb not null,
  primary key(company_id,actor_user_id,request_token)
);
alter table private.group_checkout_requests enable row level security;
revoke all on private.group_checkout_requests from public,anon,authenticated;

-- Direct client inserts cannot claim proxy origin. A nested private operation
-- records the actor server-side; actor identity must still match auth.uid().
create function private.guard_group_checkout_origin() returns trigger
language plpgsql security invoker set search_path='' as $$
begin
  if TG_OP='UPDATE' then
    if row(NEW.evidence_origin,NEW.proxy_actor_user_id)
       is distinct from row(OLD.evidence_origin,OLD.proxy_actor_user_id) then
      raise exception 'proxy origin is immutable';
    end if;
    if OLD.evidence_origin='team_proxy' and row(NEW.latitude,NEW.longitude,NEW.accuracy_m,
      NEW.distance_to_site_m,NEW.photo_storage_path,NEW.created_by,NEW.verification_mode)
      is distinct from row(OLD.latitude,OLD.longitude,OLD.accuracy_m,
      OLD.distance_to_site_m,OLD.photo_storage_path,OLD.created_by,OLD.verification_mode) then
      raise exception 'proxy evidence is immutable';
    end if;
  elsif NEW.evidence_origin='team_proxy' then
    if current_user <> 'postgres' or NEW.proxy_actor_user_id is distinct from auth.uid() then
      raise exception 'proxy checkout requires the scoped RPC';
    end if;
  end if;
  return NEW;
end $$;
revoke all on function private.guard_group_checkout_origin() from public,anon,authenticated;
create trigger group_checkout_origin_guard before insert or update
on public.attendance_verifications for each row execute function private.guard_group_checkout_origin();

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

create function private.group_checkout_candidates(p_anchor uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare a public.attendance_verifications%rowtype; result jsonb;
begin
  a:=private.group_checkout_anchor(p_anchor);
  if exists(select 1 from public.attendance_verifications s
    join public.workers w on w.id=s.worker_id and w.company_id=s.company_id and w.status='active'
    where s.company_id=a.company_id and s.site_id=a.site_id and s.route_assignment_id is null
      and s.work_date=a.work_date and s.event_type='clock_in'
    group by s.worker_id having count(*)>1) then
    raise exception 'select the correct shift before group checkout';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('source_clock_in_id',s.id,
      'worker_id',s.worker_id,'worker_name',w.name,'work_date',s.work_date,
      'clock_out_at',o.confirmed_at) order by s.id),'[]'::jsonb) into result
  from public.attendance_verifications s
  join public.workers w on w.id=s.worker_id and w.company_id=s.company_id and w.status='active'
  left join public.attendance_verifications o on o.source_clock_in_id=s.id
  where s.company_id=a.company_id and s.site_id=a.site_id and s.route_assignment_id is null
    and s.work_date=a.work_date and s.event_type='clock_in';
  return result;
end $$;
revoke all on function private.group_checkout_candidates(uuid) from public,anon;
grant execute on function private.group_checkout_candidates(uuid) to authenticated;

create function private.commit_group_checkout(p_anchor uuid,p_sources uuid[],p_request_token uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare a public.attendance_verifications%rowtype; s public.attendance_verifications%rowtype;
  v_sources uuid[]; v_prior private.group_checkout_requests%rowtype;
  v_result jsonb:='[]'::jsonb; v_out uuid; v_locked integer; v_time timestamptz:=now(); v_candidates jsonb;
begin
  a:=private.group_checkout_anchor(p_anchor);
  if p_request_token is null or cardinality(p_sources) is null or cardinality(p_sources) not between 1 and 100
     or array_position(p_sources,null) is not null then raise exception 'invalid checkout selection'; end if;
  select array_agg(id order by id) into v_sources from(select distinct unnest(p_sources) id) ids;
  if cardinality(v_sources)<>cardinality(p_sources) then raise exception 'duplicate checkout selection'; end if;
  perform pg_advisory_xact_lock(hashtextextended(a.company_id::text||':'||a.site_id::text||':'||a.work_date::text,0));
  select * into v_prior from private.group_checkout_requests
    where company_id=a.company_id and actor_user_id=auth.uid() and request_token=p_request_token;
  if found then
    if v_prior.anchor_id<>p_anchor or v_prior.source_ids<>v_sources then raise exception 'request token already used'; end if;
    return v_prior.result;
  end if;
  v_candidates:=private.group_checkout_candidates(p_anchor);
  if exists(select 1 from unnest(v_sources) id where not exists(
    select 1 from jsonb_array_elements(v_candidates) c where (c->>'source_clock_in_id')::uuid=id)) then
    raise exception 'selected worker is outside this attendance group';
  end if;
  perform 1 from public.attendance_verifications where id=any(v_sources) order by id for update;
  get diagnostics v_locked=row_count;
  if v_locked<>cardinality(v_sources) then raise exception 'attendance changed; refresh the group'; end if;
  for s in select * from public.attendance_verifications where id=any(v_sources) order by id loop
    select id into v_out from public.attendance_verifications where source_clock_in_id=s.id;
    if v_out is null then
      insert into public.attendance_verifications(company_id,worker_id,site_id,route_assignment_id,
        vehicle_id,event_type,verification_mode,confirmed_at,source_clock_in_id,created_by,
        evidence_origin,proxy_actor_user_id,note)
      values(s.company_id,s.worker_id,s.site_id,s.route_assignment_id,s.vehicle_id,
        'clock_out','manual',v_time,s.id,auth.uid(),'team_proxy',auth.uid(),'現場メンバーによる代理退勤')
      on conflict(source_clock_in_id) where source_clock_in_id is not null do nothing returning id into v_out;
      if v_out is null then select id into v_out from public.attendance_verifications where source_clock_in_id=s.id; end if;
    end if;
    v_result:=v_result||jsonb_build_array(jsonb_build_object('source_clock_in_id',s.id,'clock_out_id',v_out));
  end loop;
  insert into private.group_checkout_requests values(a.company_id,auth.uid(),p_request_token,p_anchor,v_sources,v_result);
  return v_result;
end $$;
revoke all on function private.commit_group_checkout(uuid,uuid[],uuid) from public,anon;
grant execute on function private.commit_group_checkout(uuid,uuid[],uuid) to authenticated;

create function public.group_checkout_candidates(p_source_clock_in_id uuid) returns jsonb
language sql security invoker set search_path='' as $$
  select private.group_checkout_candidates(p_source_clock_in_id)
$$;
create function public.commit_group_checkout(p_source_clock_in_id uuid,p_selected_source_ids uuid[],p_request_token uuid)
returns jsonb language sql security invoker set search_path='' as $$
  select private.commit_group_checkout(p_source_clock_in_id,p_selected_source_ids,p_request_token)
$$;
revoke all on function public.group_checkout_candidates(uuid) from public,anon;
revoke all on function public.commit_group_checkout(uuid,uuid[],uuid) from public,anon;
grant execute on function public.group_checkout_candidates(uuid),public.commit_group_checkout(uuid,uuid[],uuid) to authenticated;
-- No notification emitted at checkout: only successful daily-report registration
-- may notify recipients. UI/report confirmation integration remains separate.
