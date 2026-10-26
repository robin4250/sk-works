-- Bind only existing, unique, closed actual clock pairs; never create a punch.
create table explicit_report_finalization_private.source_bindings(id bigint generated always as identity primary key,report_id uuid not null,worker_id uuid not null,actor_id uuid not null,session_id uuid not null,review_scope text not null,before_sources jsonb not null,after_sources jsonb not null,created_at timestamptz not null default clock_timestamp());
alter table explicit_report_finalization_private.source_bindings enable row level security;
revoke all on explicit_report_finalization_private.source_bindings from public,anon,authenticated,service_role;
revoke all on sequence explicit_report_finalization_private.source_bindings_id_seq from public,anon,authenticated,service_role;
create function explicit_report_finalization_private.assert_payload(rid uuid,payload jsonb) returns void language plpgsql stable security definer set search_path='' as $$
declare w public.daily_report_workers%rowtype;item jsonb;
begin
 if jsonb_typeof(payload) is distinct from 'array' or jsonb_array_length(payload) not between 1 and 100 or octet_length(payload::text)>8388608
  or jsonb_array_length(payload)<>(select count(*) from public.daily_report_workers where report_id=rid)
  or (select count(distinct value->>'worker_id') from jsonb_array_elements(payload))<>jsonb_array_length(payload) then raise sqlstate '22023' using message='explicit_report_saved_preview_changed';end if;
 for w in select * from public.daily_report_workers where report_id=rid order by worker_id loop
  select value into item from jsonb_array_elements(payload) where value->>'worker_id'=w.worker_id::text;
  if item is null or item->>'work_category' is distinct from w.work_category or w.work_category is null
   or (item->>'overtime_hours')::numeric is distinct from w.overtime_hours
   or (item->>'early_hours')::numeric is distinct from w.early_hours
   or (item->>'night_hours')::numeric is distinct from w.night_hours
   or (item->>'allowance_amount')::integer is distinct from w.allowance_amount
   or coalesce(nullif(btrim(item->>'allowance_label'),''),'') is distinct from coalesce(nullif(btrim(w.allowance_label),''),'')
   or item->'company_allowance_selections' is distinct from w.company_allowance_selections then raise sqlstate '40001' using message='explicit_report_saved_preview_changed';end if;
 end loop;
end $$;
create function explicit_report_finalization_private.bind_closed_sources(rid uuid,review_scope text) returns void language plpgsql security definer set search_path='' as $$
declare actor uuid;r public.daily_reports%rowtype;wid uuid;i public.attendance_verifications%rowtype;o public.attendance_verifications%rowtype;n integer;before_rows jsonb;after_rows jsonb;
begin
 actor:=checkout_report_registration_private.current_actor();perform explicit_report_finalization_private.lock_actor(rid);
 select * into r from public.daily_reports where id=rid for update;
 if explicit_report_finalization_private.required(rid) is distinct from true or explicit_report_finalization_private.enabled(rid) is distinct from true or r.status<>'draft' or r.supervisor_signature_json is not null or nullif(review_scope,'') is null then raise sqlstate '55000' using message='explicit_report_provisional_preparation_unavailable';end if;
 if exists(select 1 from public.daily_report_workers rw where rw.report_id=rid and not exists(select 1 from public.workers w where w.id=rw.worker_id and w.company_id=r.company_id)) then raise sqlstate '42501' using message='shared_report_roster_unavailable';end if;
 perform 1 from public.attendance_verifications a where a.company_id=r.company_id and a.work_date=r.report_date and a.worker_id in(select worker_id from public.daily_report_workers where report_id=rid)
  and a.site_id is not distinct from r.site_id and a.route_assignment_id is not distinct from r.route_assignment_id order by a.id for update;
 for wid in select worker_id from public.daily_report_workers where report_id=rid order by worker_id loop
  select count(*) into n from public.attendance_verifications a where a.company_id=r.company_id and a.worker_id=wid and a.work_date=r.report_date and a.event_type='clock_in' and a.site_id is not distinct from r.site_id and a.route_assignment_id is not distinct from r.route_assignment_id;
  if n=0 then continue;end if;
  if n<>1 then raise sqlstate '55000' using message='explicit_report_closed_source_ambiguous';end if;
  select * into i from public.attendance_verifications a where a.company_id=r.company_id and a.worker_id=wid and a.work_date=r.report_date and a.event_type='clock_in' and a.site_id is not distinct from r.site_id and a.route_assignment_id is not distinct from r.route_assignment_id;
  select count(*) into n from public.attendance_verifications where source_clock_in_id=i.id and event_type='clock_out';
  if n=0 then continue;end if;
  if n<>1 then raise sqlstate '55000' using message='explicit_report_closed_source_ambiguous';end if;
  select * into o from public.attendance_verifications where source_clock_in_id=i.id and event_type='clock_out';
  if i.confirmed_at is null or o.confirmed_at is null then continue;end if;
  if row(o.company_id,o.worker_id,o.work_date,o.site_id,o.route_assignment_id) is distinct from row(i.company_id,i.worker_id,i.work_date,i.site_id,i.route_assignment_id) or o.confirmed_at<=i.confirmed_at then raise sqlstate '55000' using message='explicit_report_closed_source_invalid';end if;
  if (i.daily_report_id is not null and i.daily_report_id<>rid) or (o.daily_report_id is not null and o.daily_report_id<>rid) then raise sqlstate '55000' using message='shared_report_source_conflict';end if;
  if i.daily_report_id=rid and o.daily_report_id=rid then continue;end if;
  select jsonb_agg(to_jsonb(a) order by id) into before_rows from public.attendance_verifications a where id in(i.id,o.id);
  update public.attendance_verifications set daily_report_id=rid where id in(i.id,o.id) and daily_report_id is null;
  select jsonb_agg(to_jsonb(a) order by id) into after_rows from public.attendance_verifications a where id in(i.id,o.id);
  if exists(select 1 from jsonb_array_elements(before_rows) b join jsonb_array_elements(after_rows) a on a->>'id'=b->>'id' where (a-array['daily_report_id','updated_at']) is distinct from (b-array['daily_report_id','updated_at']) or a->>'daily_report_id' is distinct from rid::text) then raise sqlstate '55000' using message='explicit_report_source_binding_changed';end if;
  insert into explicit_report_finalization_private.source_bindings(report_id,worker_id,actor_id,session_id,review_scope,before_sources,after_sources) values(rid,wid,actor,(auth.jwt()->>'session_id')::uuid,review_scope,before_rows,after_rows);
 end loop;
end $$;
create function public.prepare_shared_report_provisional_facts(p_report_id uuid,p_expected_updated_at timestamptz,p_expected_signature_scope text,p_workers jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid;r public.daily_reports%rowtype;scope jsonb;
begin
 actor:=checkout_report_registration_private.current_actor();perform explicit_report_finalization_private.lock_actor(p_report_id);
 scope:=payroll_scope_private.report_sources(p_report_id);perform payroll_scope_private.lock_scopes(scope->'scopes');
 select * into r from public.daily_reports where id=p_report_id for update;
 perform 1 from public.daily_report_workers where report_id=r.id order by worker_id for share;
 if r.updated_at is distinct from p_expected_updated_at or shared_daily_report_private.signature_scope(r.id)->>'signature_scope_fingerprint' is distinct from p_expected_signature_scope then raise sqlstate '40001' using message='shared_report_signature_scope_changed';end if;
 if not explicit_report_finalization_private.required(r.id) or not explicit_report_finalization_private.enabled(r.id) or r.status<>'draft' or r.supervisor_signature_json is not null or shared_daily_report_private.document_mode(r.id) then raise sqlstate '55000' using message='explicit_report_provisional_preparation_unavailable';end if;
 perform explicit_report_finalization_private.assert_payload(r.id,p_workers);
 if r.representative_signature_json is null then perform shared_daily_report_private.enroll_work_report(r.id);end if;
 perform explicit_report_finalization_private.enroll(r.id);
 perform explicit_report_finalization_private.bind_closed_sources(r.id,p_expected_signature_scope);
 perform explicit_report_finalization_private.auto_confirm(r.id,p_workers);
 return shared_daily_report_private.read_context(r.id);
end $$;
revoke all on function public.prepare_shared_report_provisional_facts(uuid,timestamptz,text,jsonb) from public,anon,authenticated,service_role;
grant execute on function public.prepare_shared_report_provisional_facts(uuid,timestamptz,text,jsonb) to authenticated;
