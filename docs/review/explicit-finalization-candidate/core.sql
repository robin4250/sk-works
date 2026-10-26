create schema explicit_report_finalization_private;
revoke all on schema explicit_report_finalization_private from public,anon,authenticated,service_role;
create table explicit_report_finalization_private.rollout(company_id uuid primary key references public.companies(id),starts_on date not null,new_report_from timestamptz not null,enabled boolean not null default false);
create table explicit_report_finalization_private.reports(company_id uuid not null references public.companies(id),report_id uuid primary key references public.daily_reports(id) on delete cascade,enabled boolean not null default false);
create table explicit_report_finalization_private.states(report_id uuid primary key references public.daily_reports(id) on delete cascade,company_id uuid not null,revision bigint not null default 1,enrolled_by uuid not null,enrolled_at timestamptz not null default clock_timestamp());
create table explicit_report_finalization_private.events(id bigint generated always as identity primary key,report_id uuid not null,company_id uuid not null,revision bigint not null,kind text not null,actor_id uuid not null,session_id uuid not null,reason text,before_state jsonb,expected_at timestamptz,expected_scope text,created_at timestamptz not null default clock_timestamp());
create table explicit_report_finalization_private.receipts(report_id uuid not null,revision bigint not null,role text not null,signer text not null,signature jsonb not null,basis jsonb not null,actor_id uuid not null,session_id uuid not null,created_at timestamptz not null default clock_timestamp(),primary key(report_id,revision,role));
create table explicit_report_finalization_private.management_reports(report_id uuid primary key references public.daily_reports(id) on delete cascade,company_id uuid not null,operation_id uuid not null,actor_id uuid not null,session_id uuid not null);
create table explicit_report_finalization_private.permits(report_id uuid primary key,kind text not null,transaction_id bigint not null,actor_id uuid not null,session_id uuid not null,old_report jsonb not null);
alter table explicit_report_finalization_private.rollout enable row level security;
alter table explicit_report_finalization_private.reports enable row level security;
alter table explicit_report_finalization_private.states enable row level security;
alter table explicit_report_finalization_private.events enable row level security;
alter table explicit_report_finalization_private.receipts enable row level security;
alter table explicit_report_finalization_private.permits enable row level security;
alter table explicit_report_finalization_private.management_reports enable row level security;
revoke all on all tables in schema explicit_report_finalization_private from public,anon,authenticated,service_role;
revoke all on all sequences in schema explicit_report_finalization_private from public,anon,authenticated,service_role;

create function explicit_report_finalization_private.admin_context(rid uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare c jsonb;cid uuid;
begin
 c:=attendance_admin_override_private.current_context();
 if c is null then return null;end if;
 select company_id into cid from public.daily_reports where id=rid;
 if c->>'company_id'=cid::text and c->'report_ids' @> jsonb_build_array(rid) then return c;end if;
 return null;
end $$;
create function explicit_report_finalization_private.enabled(rid uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.daily_reports r where r.id=rid and (
  exists(select 1 from explicit_report_finalization_private.reports x where x.report_id=r.id and x.company_id=r.company_id and x.enabled)
  or exists(select 1 from explicit_report_finalization_private.rollout x where x.company_id=r.company_id and x.enabled and r.report_date>=x.starts_on and r.created_at>=x.new_report_from)))
$$;
create function explicit_report_finalization_private.required(rid uuid) returns boolean language sql stable security definer set search_path='' as $$
 select not exists(select 1 from explicit_report_finalization_private.management_reports where report_id=rid) and explicit_report_finalization_private.admin_context(rid) is null and (exists(select 1 from explicit_report_finalization_private.states where report_id=rid)
 or (explicit_report_finalization_private.enabled(rid) and exists(select 1 from public.daily_reports where id=rid and status='draft')))
$$;
create function explicit_report_finalization_private.enroll(rid uuid) returns void language plpgsql security definer set search_path='' as $$
declare actor uuid;r public.daily_reports%rowtype;
begin
 actor:=checkout_report_registration_private.current_actor();
 if not explicit_report_finalization_private.required(rid) then return;end if;
 if not explicit_report_finalization_private.enabled(rid) then raise sqlstate '55000' using message='explicit_report_finalization_disabled';end if;
 select * into r from public.daily_reports where id=rid;
 insert into explicit_report_finalization_private.states(report_id,company_id,enrolled_by) values(r.id,r.company_id,actor) on conflict do nothing;
end $$;
create function explicit_report_finalization_private.actor_allowed(rid uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.daily_reports r join public.company_members m on m.company_id=r.company_id and m.user_id=auth.uid() where r.id=rid
  and (private.has_company_feature(r.company_id,'can_manage_attendance') is true or shared_daily_report_private.approved_editor(r.id) or (r.status='signed' and shared_daily_report_private.approved_editor(r.id,true) and exists(select 1 from explicit_report_finalization_private.events e where e.report_id=r.id and e.kind='finalized' and e.actor_id=auth.uid() and e.session_id=(auth.jwt()->>'session_id')::uuid)) or exists(
   select 1 from public.daily_report_workers rw join public.workers w on w.id=rw.worker_id and w.company_id=r.company_id and w.user_id=auth.uid()
   join public.attendance_verifications i on i.worker_id=w.id and i.company_id=r.company_id and i.work_date=r.report_date and i.event_type='clock_in'
   where rw.report_id=r.id and i.site_id is not distinct from r.site_id and i.route_assignment_id is not distinct from r.route_assignment_id
    and (i.daily_report_id is null or i.daily_report_id=r.id))))
$$;
create function explicit_report_finalization_private.lock_actor(rid uuid) returns void language plpgsql security definer set search_path='' as $$
declare actor uuid;cid uuid;n integer;
begin
 actor:=checkout_report_registration_private.current_actor();
 perform 1 from auth.users where id=actor for share;
 perform 1 from auth.sessions where id=(auth.jwt()->>'session_id')::uuid and user_id=actor for share;
 perform checkout_report_registration_private.current_actor();
 select company_id into cid from public.daily_reports where id=rid;
 -- SHARE also protects an absent permission row from a concurrent deny insert.
 lock table public.member_feature_permissions in share mode;
 perform 1 from public.company_members where company_id=cid and user_id=actor for share;
 select count(*) into n from public.company_members where company_id=cid and user_id=actor;
 if n<>1 then raise sqlstate '42501' using message='explicit_report_membership_required';end if;
 perform 1 from public.workers where company_id=cid and user_id=actor order by id for share;
 if not explicit_report_finalization_private.actor_allowed(rid) then raise sqlstate '42501' using message='explicit_report_actor_required';end if;
end $$;
create function explicit_report_finalization_private.basis(rid uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('report',jsonb_build_object('id',r.id,'company_id',r.company_id,'report_date',r.report_date,'site_id',r.site_id,'route_assignment_id',r.route_assignment_id,'work_description',r.work_description),
  'workers',(select jsonb_agg(to_jsonb(w) order by worker_id) from public.daily_report_workers w where report_id=r.id)) from public.daily_reports r where r.id=rid
$$;
create function explicit_report_finalization_private.facts_match(rid uuid,wid uuid,facts jsonb) returns boolean language sql stable security definer set search_path='' as $$
 select coalesce((to_jsonb(w)||(facts-'schema'))=to_jsonb(w),false) from public.daily_report_workers w where report_id=rid and worker_id=wid
$$;
create function explicit_report_finalization_private.initial_hours(rid uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare wid uuid;input jsonb;answer jsonb:='[]';
begin
 for wid in select worker_id from public.daily_report_workers where report_id=rid order by worker_id loop
  input:=checkout_shared_hours_private.read_input(rid,wid);
  answer:=answer||jsonb_build_array(jsonb_build_object('worker_id',wid,'hours',case when input->>'facts_current'='true' then input->'hours' else 'null'::jsonb end));
 end loop;
 return answer;
end $$;
create function explicit_report_finalization_private.representative_current(rid uuid,proof jsonb) returns boolean language plpgsql stable security definer set search_path='' as $$
declare item jsonb;current_input jsonb;
begin
 if proof is null or proof-'initial_hours' is distinct from explicit_report_finalization_private.basis(rid) or jsonb_typeof(proof->'initial_hours') is distinct from 'array' then return false;end if;
 for item in select value from jsonb_array_elements(proof->'initial_hours') loop
  if item->'hours'<>'null'::jsonb then
   current_input:=checkout_shared_hours_private.read_input(rid,(item->>'worker_id')::uuid);
   if current_input->'hours' is distinct from item->'hours' then return false;end if;
  end if;
 end loop;
 return true;
end $$;
create function explicit_report_finalization_private.assert_hours_unchanged(rid uuid,wid uuid,hours numeric) returns void language plpgsql stable security definer set search_path='' as $$
declare proof jsonb;initial_value numeric;
begin
 if not explicit_report_finalization_private.required(rid) or not exists(select 1 from public.daily_reports where id=rid and representative_signature_json is not null) then return;end if;
 select p.basis into proof from explicit_report_finalization_private.receipts p join explicit_report_finalization_private.states s on s.report_id=p.report_id and s.revision=p.revision where p.report_id=rid and p.role='representative';
 select (value->>'hours')::numeric into initial_value from jsonb_array_elements(proof->'initial_hours') where value->>'worker_id'=wid::text;
 if initial_value is not null and hours is distinct from initial_value then raise sqlstate '55000' using message='explicit_report_edit_before_facts_change';end if;
end $$;
create function explicit_report_finalization_private.ready(rid uuid) returns boolean language plpgsql stable security definer set search_path='' as $$
declare r public.daily_reports%rowtype;s explicit_report_finalization_private.states%rowtype;annex jsonb;item jsonb;proof explicit_report_finalization_private.receipts%rowtype;
begin
 if not explicit_report_finalization_private.required(rid) or not explicit_report_finalization_private.enabled(rid) then return false;end if;
 select * into r from public.daily_reports where id=rid;
 select * into s from explicit_report_finalization_private.states where report_id=rid;
 if s.report_id is null or r.status<>'draft' or shared_daily_report_private.document_mode(rid)
  or not checkout_report_registration_private.has_signature(r.representative_signer_name,r.representative_signature_json)
  or not checkout_report_registration_private.has_signature(r.supervisor_signer_name,r.supervisor_signature_json) then return false;end if;
 select * into proof from explicit_report_finalization_private.receipts where report_id=rid and revision=s.revision and role='representative';
 if proof.signature is distinct from r.representative_signature_json or proof.signer is distinct from r.representative_signer_name
  or explicit_report_finalization_private.representative_current(rid,proof.basis) is distinct from true then return false;end if;
 annex:=checkout_shared_hours_private.supervisor_snapshot(rid);
 if annex->>'ready' is distinct from 'true' then return false;end if;
 for item in select value from jsonb_array_elements(annex->'inputs') loop
  if explicit_report_finalization_private.facts_match(rid,(item->>'worker_id')::uuid,item->'worker_facts') is distinct from true then return false;end if;
 end loop;
 select * into proof from explicit_report_finalization_private.receipts where report_id=rid and revision=s.revision and role='supervisor';
 return proof.signature=r.supervisor_signature_json and proof.signer=r.supervisor_signer_name
  and proof.basis=jsonb_build_object('draft',explicit_report_finalization_private.basis(rid),'annex',annex);
exception when data_exception or object_not_in_prerequisite_state or insufficient_privilege then return false;
end $$;
create function explicit_report_finalization_private.context_metadata(rid uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare actor uuid;r public.daily_reports%rowtype;needed boolean;
begin
 actor:=checkout_report_registration_private.current_actor();
 select * into r from public.daily_reports where id=rid;
 if not exists(select 1 from public.company_members where company_id=r.company_id and user_id=actor) then raise sqlstate '42501' using message='shared_report_unavailable';end if;
 needed:=explicit_report_finalization_private.required(rid);
 return jsonb_build_object('explicit_finalization_required',needed,'explicit_finalization_ready',needed and explicit_report_finalization_private.ready(rid),
  'explicit_finalization_completed',needed and r.status='signed' and exists(select 1 from explicit_report_finalization_private.events e join explicit_report_finalization_private.states s on s.report_id=e.report_id and s.revision=e.revision where e.report_id=rid and e.kind='finalized'),
  'explicit_finalization_editable',needed and r.status='draft' and explicit_report_finalization_private.enabled(rid) and explicit_report_finalization_private.actor_allowed(rid));
end $$;
create function explicit_report_finalization_private.record_receipts() returns trigger language plpgsql security definer set search_path='' as $$
declare rev bigint;actor uuid;role_value text;name_value text;signature_value jsonb;proof jsonb;admin_proof jsonb;
begin
 if not explicit_report_finalization_private.enabled(new.id) and not exists(select 1 from explicit_report_finalization_private.states where report_id=new.id) and not exists(select 1 from explicit_report_finalization_private.management_reports where report_id=new.id) then return new;end if;
 admin_proof:=explicit_report_finalization_private.admin_context(new.id);
 if admin_proof is not null then
  actor:=checkout_report_registration_private.current_actor();
  insert into explicit_report_finalization_private.management_reports values(new.id,new.company_id,(admin_proof->>'operation_id')::uuid,actor,(auth.jwt()->>'session_id')::uuid)
   on conflict(report_id) do update set operation_id=excluded.operation_id,actor_id=excluded.actor_id,session_id=excluded.session_id;
  select revision into rev from explicit_report_finalization_private.states where report_id=new.id;
  insert into explicit_report_finalization_private.events(report_id,company_id,revision,kind,actor_id,session_id,before_state)
   values(new.id,new.company_id,coalesce(rev,1),'management_override',actor,(auth.jwt()->>'session_id')::uuid,jsonb_build_object('report',to_jsonb(old),'context',admin_proof,'draft',explicit_report_finalization_private.basis(new.id)));
  return new;
 end if;
 if not explicit_report_finalization_private.required(new.id) then return new;end if;
 actor:=checkout_report_registration_private.current_actor();
 perform explicit_report_finalization_private.enroll(new.id);
 if old.status='signed' and new.status='draft' then
  update explicit_report_finalization_private.states set revision=revision+1 where report_id=new.id;
 end if;
 select revision into rev from explicit_report_finalization_private.states where report_id=new.id;
 foreach role_value in array array['representative','supervisor'] loop
  signature_value:=case when role_value='representative' then new.representative_signature_json else new.supervisor_signature_json end;
  name_value:=case when role_value='representative' then new.representative_signer_name else new.supervisor_signer_name end;
  if signature_value is not null and (case when role_value='representative' then old.representative_signature_json else old.supervisor_signature_json end) is distinct from signature_value then
   proof:=explicit_report_finalization_private.basis(new.id);
   if role_value='supervisor' then proof:=jsonb_build_object('draft',proof,'annex',checkout_shared_hours_private.supervisor_snapshot(new.id));
   else proof:=proof||jsonb_build_object('initial_hours',explicit_report_finalization_private.initial_hours(new.id));end if;
   insert into explicit_report_finalization_private.receipts(report_id,revision,role,signer,signature,basis,actor_id,session_id)
   values(new.id,rev,role_value,name_value,signature_value,proof,actor,(auth.jwt()->>'session_id')::uuid)
   on conflict(report_id,revision,role) do update set signer=excluded.signer,signature=excluded.signature,basis=excluded.basis,actor_id=excluded.actor_id,session_id=excluded.session_id,created_at=clock_timestamp();
  end if;
 end loop;
 return new;
end $$;
create trigger zzzz_explicit_report_receipts after update on public.daily_reports for each row execute function explicit_report_finalization_private.record_receipts();
create function explicit_report_finalization_private.permitted(rid uuid,kind_value text) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from explicit_report_finalization_private.permits p where p.report_id=rid and p.kind=kind_value and p.transaction_id=txid_current() and p.actor_id=auth.uid() and p.session_id=(auth.jwt()->>'session_id')::uuid)
$$;
create function explicit_report_finalization_private.edit_permitted(before_row jsonb,after_row jsonb) returns boolean language sql stable security definer set search_path='' as $$
 select explicit_report_finalization_private.permitted((before_row->>'id')::uuid,'edit')
 and exists(select 1 from explicit_report_finalization_private.permits p where p.report_id=(before_row->>'id')::uuid and p.old_report=before_row)
 and before_row->>'status'='draft' and after_row->>'status'='draft'
 and (before_row-array['representative_signer_name','representative_signature_json','supervisor_signer_name','supervisor_signature_json','signature_json','signer_name','signed_at','updated_by','updated_at'])
  =(after_row-array['representative_signer_name','representative_signature_json','supervisor_signer_name','supervisor_signature_json','signature_json','signer_name','signed_at','updated_by','updated_at'])
 and after_row->'representative_signature_json'='null'::jsonb and after_row->'supervisor_signature_json'='null'::jsonb and after_row->'signature_json'='null'::jsonb
$$;
create function explicit_report_finalization_private.assert_supervisor(rid uuid) returns void language plpgsql security definer set search_path='' as $$
declare r public.daily_reports%rowtype;rev bigint;proof explicit_report_finalization_private.receipts%rowtype;annex jsonb;item jsonb;
begin
 select * into r from public.daily_reports where id=rid;
 select revision into rev from explicit_report_finalization_private.states where report_id=rid;
 select * into proof from explicit_report_finalization_private.receipts where report_id=rid and revision=rev and role='representative';
 if proof.signature is distinct from r.representative_signature_json or proof.signer is distinct from r.representative_signer_name
  or explicit_report_finalization_private.representative_current(rid,proof.basis) is distinct from true then raise sqlstate '55000' using message='explicit_report_actual_revision_required';end if;
 annex:=checkout_shared_hours_private.supervisor_snapshot(rid);
 if annex->>'ready' is distinct from 'true' then raise sqlstate '55000' using message='explicit_report_finalization_facts_pending';end if;
 for item in select value from jsonb_array_elements(annex->'inputs') loop
  if explicit_report_finalization_private.facts_match(rid,(item->>'worker_id')::uuid,item->'worker_facts') is distinct from true then raise sqlstate '55000' using message='explicit_report_edit_before_facts_change';end if;
 end loop;
end $$;
create function explicit_report_finalization_private.auto_confirm(rid uuid,payload jsonb default null) returns void language plpgsql security definer set search_path='' as $$
declare w public.daily_report_workers%rowtype;state jsonb;facts jsonb;item jsonb;hours numeric;is_own boolean;reason text;cid uuid;
begin
 if not explicit_report_finalization_private.required(rid) then return;end if;
 for w in select * from public.daily_report_workers where report_id=rid order by worker_id loop
  if w.work_category is null then raise sqlstate '22023' using message='explicit_shared_worker_category_required';end if;
  state:=checkout_shared_hours_private.read_input(rid,w.worker_id);
  if state->>'source_blocked'='true' or state->>'source_kind'<>'clocked_shift' then continue;end if;
  facts:=shared_worker_facts_private.propose_worker_facts(rid,w.worker_id);
  if facts is null then raise sqlstate '22023' using message='explicit_report_actual_facts_required';end if;
  select value into item from jsonb_array_elements(coalesce(payload,'[]')) where value->>'worker_id'=w.worker_id::text;
  hours:=case when item?'confirmed_hours' and item->'confirmed_hours'<>'null'::jsonb then (item->>'confirmed_hours')::numeric when state->>'facts_current'='true' then (state->>'hours')::numeric else null end;
  if checkout_shared_hours_private.hour_required(rid,w.worker_id,facts) and hours is null then continue;end if;
  select company_id into cid from public.daily_reports where id=rid;
  select exists(select 1 from public.workers where id=w.worker_id and company_id=cid and user_id=auth.uid()) into is_own;
  reason:=nullif(btrim(item->>'confirmation_reason'),'');
  if not is_own and explicit_report_finalization_private.coordinator_available(rid,w.worker_id) then
   perform public.confirm_shared_site_report_facts(rid,w.worker_id,facts-'company_allowance_legacy_labels',hours,(state->>'revision')::bigint,state->>'scope_fingerprint',reason);
   continue;
  end if;
  if not is_own and private.has_company_feature(cid,'can_manage_attendance') is true and reason is null then continue;end if;
  if length(reason)>1000 then raise sqlstate '22023' using message='explicit_report_confirmation_reason_invalid';end if;
  if state->>'editable'='true' or private.has_company_feature(cid,'can_manage_attendance') is true then
   perform checkout_shared_hours_private.confirm_facts(rid,w.worker_id,facts-'company_allowance_legacy_labels',hours,(state->>'revision')::bigint,state->>'scope_fingerprint',
    case when not is_own and private.has_company_feature(cid,'can_manage_attendance') then reason else null end);
  end if;
 end loop;
end $$;

create function public.start_shared_report_finalization_edit(p_report_id uuid,p_expected_updated_at timestamptz,p_expected_signature_scope text,p_reason text) returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid;r public.daily_reports%rowtype;scope jsonb;rev bigint;
begin
 actor:=checkout_report_registration_private.current_actor();
 perform explicit_report_finalization_private.lock_actor(p_report_id);
 if not explicit_report_finalization_private.actor_allowed(p_report_id) or not explicit_report_finalization_private.required(p_report_id) or nullif(btrim(p_reason),'') is null or length(p_reason)>1000 then raise sqlstate '42501' using message='explicit_report_edit_not_allowed';end if;
 scope:=payroll_scope_private.report_sources(p_report_id);perform payroll_scope_private.lock_scopes(scope->'scopes');
 select * into r from public.daily_reports where id=p_report_id for update;
 perform 1 from public.daily_report_workers where report_id=r.id order by worker_id for share;
 if not explicit_report_finalization_private.actor_allowed(r.id) then raise sqlstate '42501' using message='explicit_report_actor_required';end if;
 if r.status<>'draft' then raise sqlstate '55000' using message='signed_report_requires_existing_approved_edit';end if;
 if r.updated_at is distinct from p_expected_updated_at or shared_daily_report_private.signature_scope(r.id)->>'signature_scope_fingerprint' is distinct from p_expected_signature_scope then raise sqlstate '40001' using message='shared_report_signature_scope_changed';end if;
 perform explicit_report_finalization_private.enroll(r.id);
 select revision into rev from explicit_report_finalization_private.states where report_id=r.id;
 insert into explicit_report_finalization_private.events(report_id,company_id,revision,kind,actor_id,session_id,reason,before_state)
 values(r.id,r.company_id,rev,'edit',actor,(auth.jwt()->>'session_id')::uuid,btrim(p_reason),jsonb_build_object('report',to_jsonb(r),'draft',explicit_report_finalization_private.basis(r.id),'receipts',(select jsonb_agg(to_jsonb(x)) from explicit_report_finalization_private.receipts x where report_id=r.id),'confirmations',(select jsonb_agg(to_jsonb(x)) from checkout_shared_hours_private.confirmations x where report_id=r.id)));
 insert into explicit_report_finalization_private.permits values(r.id,'edit',txid_current(),actor,(auth.jwt()->>'session_id')::uuid,to_jsonb(r));
 update public.daily_reports set representative_signer_name=null,representative_signature_json=null,supervisor_signer_name=null,supervisor_signature_json=null,signature_json=null,signer_name=null,signed_at=null,updated_by=actor,updated_at=clock_timestamp() where id=r.id;
 delete from explicit_report_finalization_private.permits where report_id=r.id;
 update explicit_report_finalization_private.states set revision=revision+1 where report_id=r.id;
 update shared_daily_report_private.document_rollout set enabled=false where report_id=r.id and company_id=r.company_id;
 update shared_daily_report_private.work_protocol set document_only=false,document_editor_actor=null,document_editor_session=null where report_id=r.id;
 update checkout_shared_hours_private.work_protocol set first_work_event_id=null where report_id=r.id;
 return shared_daily_report_private.read_context(r.id);
end $$;

create function explicit_report_finalization_private.assert_invoice(rid uuid,cid uuid,customer uuid,first_day date,last_day date) returns void language plpgsql security definer set search_path='' as $$
declare v public.invoices%rowtype;site uuid;
begin
 if customer is null or not exists(select 1 from public.customers where id=customer and company_id=cid and nullif(btrim(name),'') is not null and notes is distinct from 'sko_system_unassigned_invoice_customer') then raise sqlstate '55000' using message='explicit_report_invoice_customer_required';end if;
 select * into v from public.invoices where company_id=cid and customer_id=customer and billing_period_start=first_day and billing_period_end=last_day and automatic_calculation is true order by created_at,id limit 1;
 if v.id is null then
  if exists(select 1 from public.invoices where company_id=cid and customer_id=customer and billing_period_start=first_day and billing_period_end=last_day and (automatic_calculation is distinct from true or status is distinct from 'draft' or finalized_at is not null)) then raise sqlstate '55000' using message='explicit_report_finalized_invoice_protected';end if;
  raise sqlstate '55000' using message='explicit_report_invoice_projection_missing';end if;
 if v.status is distinct from 'draft' or v.finalized_at is not null then raise sqlstate '55000' using message='explicit_report_finalized_invoice_protected';end if;
 if v.calculation_blocked is distinct from false then raise sqlstate '55000' using message='explicit_report_invoice_projection_blocked';end if;
 select site_id into site from public.daily_reports where id=rid;
 if site is not null and not exists(select 1 from jsonb_array_elements(v.snapshot->'sites') x where x->>'site_id'=site::text) then raise sqlstate '55000' using message='explicit_report_invoice_source_missing';end if;
end $$;
create function explicit_report_finalization_private.assert_financial_projection(rid uuid) returns void language plpgsql security definer set search_path='' as $$
declare r public.daily_reports%rowtype;w public.daily_report_workers%rowtype;p public.payroll_statements%rowtype;v public.invoices%rowtype;cid uuid;first_day date;last_day date;customer_row record;customer_count integer:=0;
begin
 select * into r from public.daily_reports where id=rid;
 first_day:=date_trunc('month',r.report_date)::date;last_day:=(first_day+interval '1 month - 1 day')::date;
 if r.report_date>(current_timestamp at time zone 'Asia/Tokyo')::date then raise sqlstate '55000' using message='explicit_report_future_finance_not_supported';end if;
 for w in select * from public.daily_report_workers where report_id=rid order by worker_id loop
  if (select count(*) from public.attendance_entries where source_report_id=rid and worker_id=w.worker_id)<>1
   or not exists(select 1 from checkout_shared_hours_private.ledger l where l.report_id=rid and l.worker_id=w.worker_id and l.company_id=r.company_id) then
   raise sqlstate '55000' using message='explicit_report_financial_source_missing';end if;
  select * into p from public.payroll_statements where company_id=r.company_id and worker_id=w.worker_id and period_start=first_day and period_end=last_day;
  if p.id is null then raise sqlstate '55000' using message='explicit_report_payroll_projection_missing';end if;
  if p.automatic_calculation is distinct from true or p.workflow_state is distinct from 'draft' then raise sqlstate '55000' using message='explicit_report_finalized_payroll_protected';end if;
  if p.calculation_blocked is distinct from false then raise sqlstate '55000' using message='explicit_report_payroll_projection_blocked';end if;
 end loop;
 if r.site_id is not null then
  select (to_jsonb(x)->>'customer_id')::uuid into cid from public.sites x where x.id=r.site_id and x.company_id=r.company_id;
  perform explicit_report_finalization_private.assert_invoice(r.id,r.company_id,cid,first_day,last_day);
 elsif r.route_assignment_id is not null then
  -- The actual signed checkout source enumerates visit customers. Never infer
  -- one system invoice from a route_assignment field that does not exist.
  if to_regprocedure('private.route_signed_checkout_sources(uuid,date,date)') is null then raise sqlstate '55000' using message='explicit_report_route_invoice_sources_unavailable';end if;
  for customer_row in execute 'select distinct customer_id,source_ready from private.route_signed_checkout_sources($1,$2,$3) where report_id=$4' using r.company_id,first_day,last_day,r.id loop
   if customer_row.source_ready is distinct from true then raise sqlstate '55000' using message='explicit_report_invoice_source_missing';end if;
   customer_count:=customer_count+1;
   perform explicit_report_finalization_private.assert_invoice(r.id,r.company_id,customer_row.customer_id,first_day,last_day);
  end loop;
  if customer_count=0 then raise sqlstate '55000' using message='explicit_report_invoice_source_missing';end if;
 else raise sqlstate '55000' using message='explicit_report_financial_source_missing';
 end if;
end $$;

create function public.finalize_shared_daily_report(p_report_id uuid,p_expected_updated_at timestamptz,p_expected_signature_scope text) returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid;r public.daily_reports%rowtype;scope jsonb;annex jsonb;rev bigint;prior explicit_report_finalization_private.events%rowtype;
begin
 actor:=checkout_report_registration_private.current_actor();
 perform explicit_report_finalization_private.lock_actor(p_report_id);
 if not explicit_report_finalization_private.actor_allowed(p_report_id) or not explicit_report_finalization_private.required(p_report_id) then raise sqlstate '42501' using message='explicit_report_finalization_not_allowed';end if;
 scope:=payroll_scope_private.report_sources(p_report_id);perform payroll_scope_private.lock_scopes(scope->'scopes');
 select * into r from public.daily_reports where id=p_report_id for update;
 perform 1 from public.daily_report_workers where report_id=r.id order by worker_id for share;
 if not explicit_report_finalization_private.actor_allowed(r.id) then raise sqlstate '42501' using message='explicit_report_actor_required';end if;
 select revision into rev from explicit_report_finalization_private.states where report_id=r.id;
 select * into prior from explicit_report_finalization_private.events where report_id=r.id and revision=rev and kind='finalized' order by id desc limit 1;
 if r.status='signed' and prior.id is not null then
  if prior.expected_at is distinct from p_expected_updated_at or prior.expected_scope is distinct from p_expected_signature_scope then raise sqlstate '40001' using message='shared_report_signature_scope_changed';end if;
  return shared_daily_report_private.read_context(r.id);
 end if;
 if r.updated_at is distinct from p_expected_updated_at or shared_daily_report_private.signature_scope(r.id)->>'signature_scope_fingerprint' is distinct from p_expected_signature_scope then raise sqlstate '40001' using message='shared_report_signature_scope_changed';end if;
 if not explicit_report_finalization_private.ready(r.id) then raise sqlstate '55000' using message='explicit_report_finalization_not_ready';end if;
 if payroll_scope_private.report_sources(r.id) is distinct from scope then raise sqlstate '40001' using message='shared_report_scope_changed';end if;
 insert into explicit_report_finalization_private.permits values(r.id,'finalize',txid_current(),actor,(auth.jwt()->>'session_id')::uuid,to_jsonb(r));
 annex:=checkout_shared_hours_private.supervisor_snapshot(r.id);
 perform checkout_shared_hours_private.prepare_supervisor(r.id,annex->>'fingerprint');
 perform public.sign_daily_report(r.id,r.supervisor_signer_name,jsonb_build_object('version',3,'representative',r.representative_signature_json,'supervisor',r.supervisor_signature_json));
 perform explicit_report_finalization_private.assert_financial_projection(r.id);
 if not exists(select 1 from public.daily_reports where id=r.id and status='signed' and representative_signature_json=r.representative_signature_json and supervisor_signature_json=r.supervisor_signature_json) then raise sqlstate '55000' using message='explicit_report_finalization_result_changed';end if;
 insert into explicit_report_finalization_private.events(report_id,company_id,revision,kind,actor_id,session_id,before_state,expected_at,expected_scope)
 values(r.id,r.company_id,rev,'finalized',actor,(auth.jwt()->>'session_id')::uuid,jsonb_build_object('report',to_jsonb(r),'draft',explicit_report_finalization_private.basis(r.id),'annex',annex),p_expected_updated_at,p_expected_signature_scope);
 delete from explicit_report_finalization_private.permits where report_id=r.id;
 return shared_daily_report_private.read_context(r.id);
end $$;
revoke all on all functions in schema explicit_report_finalization_private from public,anon,authenticated,service_role;
revoke all on function public.finalize_shared_daily_report(uuid,timestamptz,text),public.start_shared_report_finalization_edit(uuid,timestamptz,text,text) from public,anon,authenticated,service_role;
grant execute on function public.finalize_shared_daily_report(uuid,timestamptz,text),public.start_shared_report_finalization_edit(uuid,timestamptz,text,text) to authenticated;
