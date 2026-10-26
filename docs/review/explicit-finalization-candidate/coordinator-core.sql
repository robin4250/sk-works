-- Explicitly scoped site coordinator attestation; never a self/management claim.
create table explicit_report_finalization_private.coordinator_permits(report_id uuid not null,worker_id uuid not null,actor_id uuid not null,session_id uuid not null,transaction_id bigint not null,expected_revision bigint not null,expected_scope text not null,primary key(report_id,worker_id));
create table explicit_report_finalization_private.coordinator_events(id bigint generated always as identity primary key,report_id uuid not null,worker_id uuid not null,confirmation_id bigint not null,actor_id uuid not null,session_id uuid not null,role text not null check(role in('site_coordinator','approved_editor')),worker_facts jsonb not null,hours numeric,expected_revision bigint not null,expected_scope text not null,input_reason text,created_at timestamptz not null default clock_timestamp());
alter table explicit_report_finalization_private.coordinator_permits enable row level security;
alter table explicit_report_finalization_private.coordinator_events enable row level security;
revoke all on explicit_report_finalization_private.coordinator_permits,explicit_report_finalization_private.coordinator_events from public,anon,authenticated,service_role;
revoke all on sequence explicit_report_finalization_private.coordinator_events_id_seq from public,anon,authenticated,service_role;
create function explicit_report_finalization_private.coordinator_available(rid uuid,wid uuid) returns boolean language plpgsql stable security definer set search_path='' as $$
declare actor uuid;own_worker uuid;target_source jsonb;own_source jsonb;r public.daily_reports%rowtype;approved boolean;
begin
 actor:=checkout_report_registration_private.current_actor();
 select * into r from public.daily_reports where id=rid;
 if not explicit_report_finalization_private.required(rid) or not explicit_report_finalization_private.enabled(rid) or r.status<>'draft' or r.supervisor_signature_json is not null or not explicit_report_finalization_private.actor_allowed(rid) then return false;end if;
 select w.id into own_worker from public.daily_report_workers rw join public.workers w on w.id=rw.worker_id and w.company_id=r.company_id and w.user_id=actor where rw.report_id=rid order by w.id limit 1;
 approved:=shared_daily_report_private.approved_editor(rid);
 if (own_worker is null and not approved) or not exists(select 1 from public.daily_report_workers where report_id=rid and worker_id=wid) then return false;end if;
 if own_worker is not null then own_source:=checkout_shared_hours_private.source_scope(rid,own_worker,false);end if;
 target_source:=checkout_shared_hours_private.source_scope(rid,wid,false);
 return coalesce((approved or (own_source->>'source_kind'='clocked_shift' and own_source->>'blocked'='false')) and target_source->>'source_kind'='clocked_shift' and target_source->>'blocked'='false',false);
exception when data_exception or insufficient_privilege or object_not_in_prerequisite_state then return false;
end $$;
create function explicit_report_finalization_private.coordinator_kind(rid uuid) returns text language sql stable security definer set search_path='' as $$
 select case when shared_daily_report_private.approved_editor(rid) then 'approved_editor' else 'site_coordinator' end
$$;
create function explicit_report_finalization_private.coordinator_permitted(rid uuid,wid uuid) returns boolean language sql stable security definer set search_path='' as $$
 select explicit_report_finalization_private.coordinator_available(rid,wid) and exists(select 1 from explicit_report_finalization_private.coordinator_permits p where p.report_id=rid and p.worker_id=wid and p.actor_id=auth.uid() and p.session_id=(auth.jwt()->>'session_id')::uuid and p.transaction_id=txid_current())
$$;
create function public.confirm_shared_site_report_facts(p_report_id uuid,p_worker_id uuid,p_facts jsonb,p_hours numeric,p_expected_revision bigint,p_expected_scope text,p_reason text default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid;scope jsonb;r public.daily_reports%rowtype;facts jsonb;result jsonb;
begin
 actor:=checkout_report_registration_private.current_actor();perform explicit_report_finalization_private.lock_actor(p_report_id);
 scope:=payroll_scope_private.report_sources(p_report_id);perform payroll_scope_private.lock_scopes(scope->'scopes');
 select * into r from public.daily_reports where id=p_report_id for update;
 perform 1 from public.daily_report_workers where report_id=r.id order by worker_id for share;
 if explicit_report_finalization_private.coordinator_available(r.id,p_worker_id) is distinct from true then raise sqlstate '42501' using message='explicit_report_site_coordinator_unavailable';end if;
 facts:=shared_worker_facts_private.normalize_worker_facts(r.id,p_worker_id,p_facts);
 if explicit_report_finalization_private.facts_match(r.id,p_worker_id,facts) is distinct from true then raise sqlstate '55000' using message='explicit_report_edit_before_facts_change';end if;
 if length(p_reason)>1000 then raise sqlstate '22023' using message='explicit_report_confirmation_reason_invalid';end if;
 perform explicit_report_finalization_private.enroll(r.id);
 insert into explicit_report_finalization_private.coordinator_permits values(r.id,p_worker_id,actor,(auth.jwt()->>'session_id')::uuid,txid_current(),p_expected_revision,p_expected_scope);
 result:=checkout_shared_hours_private.confirm_facts(r.id,p_worker_id,p_facts,p_hours,p_expected_revision,p_expected_scope,null);
 insert into explicit_report_finalization_private.coordinator_events(report_id,worker_id,confirmation_id,actor_id,session_id,role,worker_facts,hours,expected_revision,expected_scope,input_reason)
 select r.id,p_worker_id,(result->>'confirmation_id')::bigint,actor,(auth.jwt()->>'session_id')::uuid,explicit_report_finalization_private.coordinator_kind(r.id),facts,p_hours,p_expected_revision,p_expected_scope,nullif(btrim(p_reason),'')
 where not exists(select 1 from explicit_report_finalization_private.coordinator_events e where e.report_id=r.id and e.worker_id=p_worker_id and e.confirmation_id=(result->>'confirmation_id')::bigint and e.actor_id=actor and e.session_id=(auth.jwt()->>'session_id')::uuid);
 delete from explicit_report_finalization_private.coordinator_permits where report_id=r.id and worker_id=p_worker_id;
 return result||jsonb_build_object('site_coordinator_confirmation_available',true);
end $$;
revoke all on function public.confirm_shared_site_report_facts(uuid,uuid,jsonb,numeric,bigint,text,text) from public,anon,authenticated,service_role;
grant execute on function public.confirm_shared_site_report_facts(uuid,uuid,jsonb,numeric,bigint,text,text) to authenticated;
