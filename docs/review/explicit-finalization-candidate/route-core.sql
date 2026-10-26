create schema explicit_route_finalization_private;
revoke all on schema explicit_route_finalization_private from public,anon,authenticated,service_role;
create table explicit_route_finalization_private.rollout(company_id uuid primary key,starts_on date not null,new_report_from timestamptz not null,enabled boolean not null default false);
create table explicit_route_finalization_private.reports(report_id uuid primary key,company_id uuid not null,enabled boolean not null default false);
create table explicit_route_finalization_private.states(report_id uuid primary key,company_id uuid not null,revision bigint not null default 1);
create table explicit_route_finalization_private.receipts(report_id uuid not null,revision bigint not null,role text not null,signer text not null,signature jsonb not null,basis jsonb not null,actor_id uuid not null,session_id uuid not null,primary key(report_id,revision,role));
create table explicit_route_finalization_private.events(id bigint generated always as identity primary key,report_id uuid not null,revision bigint not null,kind text not null,actor_id uuid not null,session_id uuid not null,before_state jsonb,reason text,expected_at timestamptz,expected_scope text,created_at timestamptz not null default clock_timestamp());
create table explicit_route_finalization_private.permits(report_id uuid primary key,transaction_id bigint not null,actor_id uuid not null,session_id uuid not null);
alter table explicit_route_finalization_private.rollout enable row level security;
alter table explicit_route_finalization_private.reports enable row level security;
alter table explicit_route_finalization_private.states enable row level security;
alter table explicit_route_finalization_private.receipts enable row level security;
alter table explicit_route_finalization_private.events enable row level security;
alter table explicit_route_finalization_private.permits enable row level security;
revoke all on all tables in schema explicit_route_finalization_private from public,anon,authenticated,service_role;
revoke all on all sequences in schema explicit_route_finalization_private from public,anon,authenticated,service_role;
create function explicit_route_finalization_private.enabled(rid uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from private.route_visit_reports r where r.id=rid and (
  exists(select 1 from explicit_route_finalization_private.reports x where x.report_id=r.id and x.company_id=r.company_id and x.enabled)
  or exists(select 1 from explicit_route_finalization_private.rollout x where x.company_id=r.company_id and x.enabled and r.report_date>=x.starts_on and r.created_at>=x.new_report_from)))
$$;
create function explicit_route_finalization_private.required(rid uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from explicit_route_finalization_private.states where report_id=rid)
 or (explicit_route_finalization_private.enabled(rid) and exists(select 1 from private.route_visit_reports where id=rid and status in('draft','reporter_signed')))
$$;
create function explicit_route_finalization_private.actor_allowed(rid uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from private.route_visit_reports r join public.company_members m on m.company_id=r.company_id and m.user_id=auth.uid() where r.id=rid and
  (r.created_by=auth.uid() or exists(select 1 from jsonb_array_elements(r.roster_workers) x join public.workers w on w.id=(x->>'worker_id')::uuid and w.company_id=r.company_id and w.user_id=auth.uid())))
$$;
create function explicit_route_finalization_private.lock_actor(rid uuid) returns void language plpgsql security definer set search_path='' as $$
declare actor uuid;cid uuid;
begin
 actor:=checkout_report_registration_private.current_actor();
 perform 1 from auth.users where id=actor for share;
 perform 1 from auth.sessions where id=(auth.jwt()->>'session_id')::uuid and user_id=actor for share;
 perform checkout_report_registration_private.current_actor();
 select company_id into cid from private.route_visit_reports where id=rid;
 perform 1 from public.company_members where company_id=cid and user_id=actor for share;
 if (select count(*) from public.company_members where company_id=cid and user_id=actor)<>1 then raise sqlstate '42501' using message='explicit_route_membership_required';end if;
 perform 1 from public.workers where company_id=cid and user_id=actor order by id for share;
 if explicit_route_finalization_private.actor_allowed(rid) is distinct from true then raise sqlstate '42501' using message='explicit_route_actor_required';end if;
end $$;
create function explicit_route_finalization_private.basis(rid uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select to_jsonb(r)-array['status','representative_signer_name','representative_signature_json','supervisor_signer_name','supervisor_signature_json','signed_at','updated_at'] from private.route_visit_reports r where id=rid
$$;
create function explicit_route_finalization_private.scope(rid uuid) returns text language sql stable security definer set search_path='' as $$
 select encode(sha256(convert_to(to_jsonb(r)::text,'UTF8')),'hex') from private.route_visit_reports r where id=rid
$$;
create function explicit_route_finalization_private.enroll(rid uuid) returns void language plpgsql security definer set search_path='' as $$
begin
 if not explicit_route_finalization_private.required(rid) then return;end if;
 if not explicit_route_finalization_private.enabled(rid) then raise sqlstate '55000' using message='explicit_route_finalization_disabled';end if;
 insert into explicit_route_finalization_private.states(report_id,company_id) select id,company_id from private.route_visit_reports where id=rid on conflict do nothing;
end $$;
create function explicit_route_finalization_private.ready(rid uuid) returns boolean language sql stable security definer set search_path='' as $$
 select coalesce(explicit_route_finalization_private.enabled(rid) and r.status='reporter_signed' and nullif(btrim(r.work_description),'') is not null
  and r.representative_signature_json is not null and r.supervisor_signature_json is not null
  and exists(select 1 from explicit_route_finalization_private.receipts p join explicit_route_finalization_private.states s on s.report_id=p.report_id and s.revision=p.revision where p.report_id=r.id and p.role='reporter' and p.signer=r.representative_signer_name and p.signature=r.representative_signature_json and p.basis=explicit_route_finalization_private.basis(r.id))
  and exists(select 1 from explicit_route_finalization_private.receipts p join explicit_route_finalization_private.states s on s.report_id=p.report_id and s.revision=p.revision where p.report_id=r.id and p.role='responsible' and p.signer=r.supervisor_signer_name and p.signature=r.supervisor_signature_json and p.basis=explicit_route_finalization_private.basis(r.id)),false)
 from private.route_visit_reports r where id=rid
$$;
create function explicit_route_finalization_private.decorate(input_row jsonb) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare actor uuid;rid uuid;r private.route_visit_reports%rowtype;needed boolean;
begin
 actor:=checkout_report_registration_private.current_actor();rid:=(input_row->>'id')::uuid;
 if rid is null then return input_row||jsonb_build_object('explicit_finalization_required',false,'explicit_finalization_ready',false,'explicit_finalization_completed',false,'explicit_finalization_editable',false);end if;
 select * into r from private.route_visit_reports where id=rid;
 if explicit_route_finalization_private.actor_allowed(rid) is distinct from true then raise sqlstate '42501' using message='explicit_route_actor_required';end if;
 needed:=explicit_route_finalization_private.required(rid);
 return input_row||jsonb_build_object('actor_id',actor,'explicit_finalization_required',needed,'explicit_finalization_ready',needed and explicit_route_finalization_private.ready(rid),
  'explicit_finalization_completed',needed and r.status='completed' and exists(select 1 from explicit_route_finalization_private.events e join explicit_route_finalization_private.states s on s.report_id=e.report_id and s.revision=e.revision where e.report_id=rid and e.kind='finalized'),
  'explicit_finalization_editable',needed and r.status in('draft','reporter_signed') and explicit_route_finalization_private.enabled(rid),
  'report_updated_at',r.updated_at,'signature_scope_fingerprint',explicit_route_finalization_private.scope(rid));
end $$;
create function explicit_route_finalization_private.record_receipts() returns trigger language plpgsql security definer set search_path='' as $$
declare actor uuid;rev bigint;role_value text;name_value text;sig jsonb;
begin
 if not explicit_route_finalization_private.required(new.id) then return new;end if;
 actor:=checkout_report_registration_private.current_actor();perform explicit_route_finalization_private.enroll(new.id);
 select revision into rev from explicit_route_finalization_private.states where report_id=new.id;
 foreach role_value in array array['reporter','responsible'] loop
  sig:=case when role_value='reporter' then new.representative_signature_json else new.supervisor_signature_json end;
  name_value:=case when role_value='reporter' then new.representative_signer_name else new.supervisor_signer_name end;
  if sig is not null and sig is distinct from (case when role_value='reporter' then old.representative_signature_json else old.supervisor_signature_json end) then
   insert into explicit_route_finalization_private.receipts values(new.id,rev,role_value,name_value,sig,explicit_route_finalization_private.basis(new.id),actor,(auth.jwt()->>'session_id')::uuid);
  end if;
 end loop;
 return new;
end $$;
create trigger zzzz_explicit_route_receipts after update on private.route_visit_reports for each row execute function explicit_route_finalization_private.record_receipts();
create function explicit_route_finalization_private.guard_completion() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if explicit_route_finalization_private.required(old.id) and old.status<>'completed' and new.status='completed'
  and not exists(select 1 from explicit_route_finalization_private.permits p where p.report_id=old.id and p.transaction_id=txid_current() and p.actor_id=auth.uid() and p.session_id=(auth.jwt()->>'session_id')::uuid) then raise sqlstate '55000' using message='explicit_route_finalization_required';end if;
 return new;
end $$;
create trigger explicit_route_completion_gate before update on private.route_visit_reports for each row execute function explicit_route_finalization_private.guard_completion();
create function public.start_route_visit_report_finalization_edit(p_report_id uuid,p_expected_updated_at timestamptz,p_expected_signature_scope text,p_reason text) returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid;r private.route_visit_reports%rowtype;rev bigint;
begin
 actor:=checkout_report_registration_private.current_actor();perform explicit_route_finalization_private.lock_actor(p_report_id);
 select * into r from private.route_visit_reports where id=p_report_id for update;
 if not explicit_route_finalization_private.required(r.id) or r.status not in('draft','reporter_signed') or nullif(btrim(p_reason),'') is null or length(p_reason)>1000 then raise sqlstate '55000' using message='explicit_route_edit_unavailable';end if;
 if r.updated_at is distinct from p_expected_updated_at or explicit_route_finalization_private.scope(r.id) is distinct from p_expected_signature_scope then raise sqlstate '40001' using message='explicit_route_scope_changed';end if;
 perform explicit_route_finalization_private.enroll(r.id);
 select revision into rev from explicit_route_finalization_private.states where report_id=r.id;
 insert into explicit_route_finalization_private.events(report_id,revision,kind,actor_id,session_id,before_state,reason) values(r.id,rev,'edit',actor,(auth.jwt()->>'session_id')::uuid,to_jsonb(r),btrim(p_reason));
 update private.route_visit_reports set status='draft',representative_signer_name=null,representative_signature_json=null,supervisor_signer_name=null,supervisor_signature_json=null,signed_at=null,updated_at=clock_timestamp() where id=r.id;
 update explicit_route_finalization_private.states set revision=revision+1 where report_id=r.id;
 select * into r from private.route_visit_reports where id=r.id;
 return explicit_route_finalization_private.decorate(to_jsonb(r)||jsonb_build_object('daily_report_workers',r.workers,'sites',jsonb_build_object('name',r.site_name)));
end $$;
create function public.finalize_route_visit_report(p_report_id uuid,p_expected_updated_at timestamptz,p_expected_signature_scope text) returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid;r private.route_visit_reports%rowtype;rev bigint;e explicit_route_finalization_private.events%rowtype;
begin
 actor:=checkout_report_registration_private.current_actor();perform explicit_route_finalization_private.lock_actor(p_report_id);
 select * into r from private.route_visit_reports where id=p_report_id for update;
 if explicit_route_finalization_private.actor_allowed(r.id) is distinct from true or not explicit_route_finalization_private.required(r.id) then raise sqlstate '42501' using message='explicit_route_finalization_not_allowed';end if;
 select revision into rev from explicit_route_finalization_private.states where report_id=r.id;
 select * into e from explicit_route_finalization_private.events where report_id=r.id and revision=rev and kind='finalized' order by id desc limit 1;
 if r.status='completed' and e.id is not null then
  if e.expected_at is distinct from p_expected_updated_at or e.expected_scope is distinct from p_expected_signature_scope then raise sqlstate '40001' using message='explicit_route_scope_changed';end if;
  return explicit_route_finalization_private.decorate(to_jsonb(r)||jsonb_build_object('daily_report_workers',r.workers,'sites',jsonb_build_object('name',r.site_name)));
 end if;
 if r.updated_at is distinct from p_expected_updated_at or explicit_route_finalization_private.scope(r.id) is distinct from p_expected_signature_scope then raise sqlstate '40001' using message='explicit_route_scope_changed';end if;
 if explicit_route_finalization_private.ready(r.id) is distinct from true then raise sqlstate '55000' using message='explicit_route_finalization_not_ready';end if;
 insert into explicit_route_finalization_private.permits values(r.id,txid_current(),actor,(auth.jwt()->>'session_id')::uuid);
 update private.route_visit_reports set status='completed',signed_at=clock_timestamp(),updated_at=clock_timestamp() where id=r.id;
 insert into explicit_route_finalization_private.events(report_id,revision,kind,actor_id,session_id,before_state,expected_at,expected_scope) values(r.id,rev,'finalized',actor,(auth.jwt()->>'session_id')::uuid,to_jsonb(r),p_expected_updated_at,p_expected_signature_scope);
 delete from explicit_route_finalization_private.permits where report_id=r.id;
 select * into r from private.route_visit_reports where id=r.id;
 return explicit_route_finalization_private.decorate(to_jsonb(r)||jsonb_build_object('daily_report_workers',r.workers,'sites',jsonb_build_object('name',r.site_name)));
end $$;
revoke all on all functions in schema explicit_route_finalization_private from public,anon,authenticated,service_role;
revoke all on function public.finalize_route_visit_report(uuid,timestamptz,text),public.start_route_visit_report_finalization_edit(uuid,timestamptz,text,text) from public,anon,authenticated,service_role;
grant execute on function public.finalize_route_visit_report(uuid,timestamptz,text),public.start_route_visit_report_finalization_edit(uuid,timestamptz,text,text) to authenticated;
