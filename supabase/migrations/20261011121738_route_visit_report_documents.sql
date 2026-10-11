-- Separate visit documents: no canonical daily report, attendance or payroll writes.
create table private.route_visit_reports (
 id uuid primary key default gen_random_uuid(), company_id uuid not null, created_by uuid not null,
 source_clock_in_id uuid not null, route_assignment_id uuid not null, route_stop_id uuid not null,
 start_capture_id uuid not null unique, end_capture_id uuid not null unique,
 report_date date not null, site_id uuid, site_name text not null,
 status text not null check(status in ('draft','reporter_signed','completed','skipped')),
 work_description text not null default '', workers jsonb not null default '[]', roster_workers jsonb not null default '[]',
 representative_signer_name text, representative_signature_json jsonb,
 supervisor_signer_name text, supervisor_signature_json jsonb,
 signed_at timestamptz, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
alter table private.route_visit_reports enable row level security;
revoke all on private.route_visit_reports from public,anon,authenticated;

create function private.route_visit_report_context(
 p_source_clock_in_id uuid,p_route_assignment_id uuid,p_route_stop_id uuid,p_start_capture_id uuid,p_end_capture_id uuid
) returns jsonb language plpgsql security definer set search_path='' as $$
declare s jsonb; e jsonb; roster jsonb; site uuid;
begin
 s:=private.route_journey_visit_exact(p_start_capture_id);
 e:=private.route_journey_visit_exact(p_end_capture_id);
 if s is null or e is null or s->>'visit_kind'<>'start' or e->>'visit_kind'<>'end'
  or (e->>'start_capture_id')::uuid is distinct from p_start_capture_id
  or (s->>'source_clock_in_id')::uuid is distinct from p_source_clock_in_id
  or (e->>'source_clock_in_id')::uuid is distinct from p_source_clock_in_id
  or (s->>'route_assignment_id')::uuid is distinct from p_route_assignment_id
  or (e->>'route_assignment_id')::uuid is distinct from p_route_assignment_id
  or (s->>'route_stop_id')::uuid is distinct from p_route_stop_id
  or (e->>'route_stop_id')::uuid is distinct from p_route_stop_id then
  raise exception 'visit context unavailable' using errcode='42501';
 end if;
 select rs.site_id into site from public.route_stops rs where rs.id=p_route_stop_id and rs.route_assignment_id=p_route_assignment_id;
 -- Historical clock-in roster stays available after checkout and feature OFF.
 select coalesce(jsonb_agg(jsonb_build_object('worker_id',w.id,'worker_name',w.name,'workers',jsonb_build_object('name',w.name))), '[]')
 into roster from public.workers w where w.company_id=(s->>'company_id')::uuid
 and (w.id=(s->>'worker_id')::uuid or exists(select 1 from public.attendance_verifications a
 where a.worker_id=w.id and a.company_id=w.company_id and a.route_assignment_id=p_route_assignment_id
 and a.work_date=(s->>'work_date')::date and a.event_type='clock_in'));
 return jsonb_build_object('id',null,'status','pending','company_id',s->>'company_id','created_by',auth.uid(),
 'source_clock_in_id',p_source_clock_in_id,'route_assignment_id',p_route_assignment_id,'route_stop_id',p_route_stop_id,
 'start_capture_id',p_start_capture_id,'end_capture_id',p_end_capture_id,'report_date',s->>'work_date',
 'site_id',site,'site_name',s->>'stop_label','sites',jsonb_build_object('name',s->>'stop_label'),'workers',roster,'daily_report_workers',roster);
end $$;

create function private.route_visit_report_command(
 p_source_clock_in_id uuid,p_route_assignment_id uuid,p_route_stop_id uuid,p_start_capture_id uuid,p_end_capture_id uuid,
 p_command text,p_work_description text default null,p_workers jsonb default null
) returns jsonb language plpgsql security definer set search_path='' as $$
declare c jsonb; r private.route_visit_reports%rowtype;
begin
 if auth.uid() is null or not private.account_access_allowed() then raise exception 'account unavailable' using errcode='42501'; end if;
 if p_command is null or p_command not in ('read','create','skip','draft') then raise exception 'invalid report command'; end if;
 -- One fixed visit key serializes create/skip/draft retries and prevents dual documents.
 perform pg_advisory_xact_lock(hashtextextended(p_start_capture_id::text,0));
 select * into r from private.route_visit_reports where start_capture_id=p_start_capture_id;
 if found then
  if r.created_by<>auth.uid() or not exists(select 1 from public.company_members where company_id=r.company_id and user_id=auth.uid())
   or r.source_clock_in_id is distinct from p_source_clock_in_id or r.route_assignment_id is distinct from p_route_assignment_id
   or r.route_stop_id is distinct from p_route_stop_id or r.end_capture_id is distinct from p_end_capture_id then
   raise exception 'visit context unavailable' using errcode='42501'; end if;
 else
  c:=private.route_visit_report_context(p_source_clock_in_id,p_route_assignment_id,p_route_stop_id,p_start_capture_id,p_end_capture_id);
  if p_command='read' then return c; end if;
  insert into private.route_visit_reports(company_id,created_by,source_clock_in_id,route_assignment_id,route_stop_id,start_capture_id,end_capture_id,report_date,site_id,site_name,status,workers,roster_workers)
   values((c->>'company_id')::uuid,auth.uid(),p_source_clock_in_id,p_route_assignment_id,p_route_stop_id,p_start_capture_id,p_end_capture_id,(c->>'report_date')::date,(c->>'site_id')::uuid,c->>'site_name',case when p_command='skip' then 'skipped' else 'draft' end,c->'workers',c->'workers') returning * into r;
 end if;
 if p_command='draft' and r.status='draft' then
  if p_workers is not null and jsonb_typeof(p_workers)<>'array' then raise exception 'workers must be array'; end if;
  if exists(select 1 from jsonb_array_elements(coalesce(p_workers,'[]')) x
   where jsonb_typeof(x)<>'object' or not exists(select 1 from jsonb_array_elements(r.roster_workers) w where w->>'worker_id'=x->>'worker_id')) then raise exception 'worker outside frozen roster' using errcode='42501'; end if;
  if exists(select 1 from jsonb_array_elements(coalesce(p_workers,'[]')) x group by x->>'worker_id' having count(*)>1) then raise exception 'duplicate worker'; end if;
  update private.route_visit_reports set work_description=coalesce(p_work_description,''),
   workers=case when p_workers is null or p_workers='[]' then workers else
    (select jsonb_agg(coalesce(old.value,'{}')||coalesce(client.value,'{}')||snapshot.value order by snapshot.ordinality)
     from jsonb_array_elements(r.roster_workers) with ordinality snapshot(value,ordinality)
     left join lateral (select value from jsonb_array_elements(r.workers) where value->>'worker_id'=snapshot.value->>'worker_id') old on true
     left join lateral (select value from jsonb_array_elements(p_workers) where value->>'worker_id'=snapshot.value->>'worker_id') client on true) end,updated_at=now() where id=r.id returning * into r;
 elsif p_command='skip' and r.status='draft' then
  update private.route_visit_reports set status='skipped',updated_at=now() where id=r.id returning * into r;
 end if;
 return to_jsonb(r)||jsonb_build_object('daily_report_workers',r.workers,'sites',jsonb_build_object('name',r.site_name));
end $$;

create function public.read_route_visit_report(p_source_clock_in_id uuid,p_route_assignment_id uuid,p_route_stop_id uuid,p_start_capture_id uuid,p_end_capture_id uuid)
returns jsonb language sql security invoker set search_path='' as $$select private.route_visit_report_command(p_source_clock_in_id,p_route_assignment_id,p_route_stop_id,p_start_capture_id,p_end_capture_id,'read')$$;
create function public.choose_route_visit_report(p_source_clock_in_id uuid,p_route_assignment_id uuid,p_route_stop_id uuid,p_start_capture_id uuid,p_end_capture_id uuid,p_create boolean)
returns jsonb language sql security invoker set search_path='' as $$select private.route_visit_report_command(p_source_clock_in_id,p_route_assignment_id,p_route_stop_id,p_start_capture_id,p_end_capture_id,case when p_create is null then null when p_create then 'create' else 'skip' end)$$;
create function public.save_route_visit_report_draft(p_source_clock_in_id uuid,p_route_assignment_id uuid,p_route_stop_id uuid,p_start_capture_id uuid,p_end_capture_id uuid,p_work_description text,p_workers jsonb)
returns jsonb language sql security invoker set search_path='' as $$select private.route_visit_report_command(p_source_clock_in_id,p_route_assignment_id,p_route_stop_id,p_start_capture_id,p_end_capture_id,'draft',p_work_description,p_workers)$$;

create function private.save_route_visit_report_signature(p_report_id uuid,p_role text,p_signer_name text,p_signature_json jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare r private.route_visit_reports%rowtype; stroke jsonb; point jsonb;
begin
 if auth.uid() is null or not private.account_access_allowed() then raise exception 'account unavailable' using errcode='42501'; end if;
 select * into r from private.route_visit_reports where id=p_report_id for update;
 if not found or r.created_by<>auth.uid() or not exists(select 1 from public.company_members where company_id=r.company_id and user_id=auth.uid()) then raise exception 'report unavailable' using errcode='42501'; end if;
 if p_role not in ('reporter','responsible') or p_role is null or nullif(trim(p_signer_name),'') is null
 or p_signature_json is null or jsonb_typeof(p_signature_json)<>'object'
 or jsonb_typeof(p_signature_json->'strokes') is distinct from 'array' or jsonb_array_length(p_signature_json->'strokes')=0 then raise exception 'name and signature required'; end if;
 for stroke in select value from jsonb_array_elements(p_signature_json->'strokes') loop
  if jsonb_typeof(stroke) is distinct from 'array' or jsonb_array_length(stroke)=0 then raise exception 'invalid signature stroke'; end if;
  for point in select value from jsonb_array_elements(stroke) loop
   if jsonb_typeof(point) is distinct from 'object' or jsonb_typeof(point->'x') is distinct from 'number' or jsonb_typeof(point->'y') is distinct from 'number' then raise exception 'invalid signature point'; end if;
   if (point->>'x')::numeric not between 0 and 1 or (point->>'y')::numeric not between 0 and 1 then raise exception 'invalid signature coordinates'; end if;
  end loop;
 end loop;
 if r.status in ('completed','skipped') then return to_jsonb(r); end if;
 if p_role='reporter' and r.representative_signature_json is null then
  update private.route_visit_reports set representative_signer_name=trim(p_signer_name),representative_signature_json=p_signature_json,status='reporter_signed',updated_at=now() where id=r.id returning * into r;
 elsif p_role='responsible' then
  if r.representative_signature_json is null then raise exception 'reporter signature required'; end if;
  update private.route_visit_reports set supervisor_signer_name=trim(p_signer_name),supervisor_signature_json=p_signature_json,status='completed',signed_at=now(),updated_at=now() where id=r.id returning * into r;
 end if;
 return to_jsonb(r)||jsonb_build_object('daily_report_workers',r.workers,'sites',jsonb_build_object('name',r.site_name));
end $$;
create function public.save_route_visit_report_signature(p_report_id uuid,p_role text,p_signer_name text,p_signature_json jsonb)
returns jsonb language sql security invoker set search_path='' as $$select private.save_route_visit_report_signature(p_report_id,p_role,p_signer_name,p_signature_json)$$;
revoke all on function private.route_visit_report_context(uuid,uuid,uuid,uuid,uuid) from public,anon,authenticated;
revoke all on function private.route_visit_report_command(uuid,uuid,uuid,uuid,uuid,text,text,jsonb) from public,anon,authenticated;
grant execute on function private.route_visit_report_command(uuid,uuid,uuid,uuid,uuid,text,text,jsonb) to authenticated;
revoke all on function private.save_route_visit_report_signature(uuid,text,text,jsonb) from public,anon,authenticated;
grant execute on function private.save_route_visit_report_signature(uuid,text,text,jsonb) to authenticated;
revoke all on function public.read_route_visit_report(uuid,uuid,uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function public.read_route_visit_report(uuid,uuid,uuid,uuid,uuid) to authenticated;
revoke all on function public.choose_route_visit_report(uuid,uuid,uuid,uuid,uuid,boolean) from public,anon,authenticated;
grant execute on function public.choose_route_visit_report(uuid,uuid,uuid,uuid,uuid,boolean) to authenticated;
revoke all on function public.save_route_visit_report_draft(uuid,uuid,uuid,uuid,uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.save_route_visit_report_draft(uuid,uuid,uuid,uuid,uuid,text,jsonb) to authenticated;
revoke all on function public.save_route_visit_report_signature(uuid,text,text,jsonb) from public,anon,authenticated;
grant execute on function public.save_route_visit_report_signature(uuid,text,text,jsonb) to authenticated;
