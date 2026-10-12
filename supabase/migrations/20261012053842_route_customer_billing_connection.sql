-- CLI-generated migration: explicit approved route quantities, never payroll writes.
begin;
do $$begin
 if to_regclass('private.route_billing_quantity_requests') is not null then raise exception 'Unexpected existing route billing schema; inspect before applying';end if;
 if (select md5(prosrc) from pg_proc where oid='private.refresh_automatic_invoice(uuid,uuid,date)'::regprocedure) is distinct from '60686abe4566c3d626772010c0397872' then raise exception 'Current invoice generator differs; inspect before applying';end if;
 if (select md5(prosrc) from pg_proc where oid='private.resolve_rate_formula(numeric,jsonb,jsonb,text)'::regprocedure) is distinct from 'aafab0bfb09c813dae8da9fc06dbb762' then raise exception 'Shared rate resolver differs; inspect before applying';end if;
end $$;
-- Reference contract for the CLI-generated migration and isolated tests.
-- Dedicated billing quantity only; never writes canonical attendance or payroll.
create table private.route_billing_quantity_requests(
 id uuid primary key default gen_random_uuid(),company_id uuid not null,worker_id uuid not null,worker_name text not null,
 work_date date not null,customer_id uuid not null,customer_name text not null,
 requested_quantity numeric not null check(requested_quantity in (0.5,1)),
 quantity numeric not null check(quantity in (0.5,1)),status text not null default 'pending' check(status in ('pending','approved','rejected')),
 version integer not null default 1,requested_by uuid not null,reviewed_by uuid,reviewed_at timestamptz,
 representative_site_id uuid,unit_price_yen integer check(unit_price_yen>0),review_note text,
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 unique(company_id,worker_id,work_date,customer_id)
);
create table private.route_billing_quantity_evidence(
 request_id uuid not null references private.route_billing_quantity_requests(id),report_id uuid not null,
 source_clock_in_id uuid not null,start_capture_id uuid not null,end_capture_id uuid not null,
 site_id uuid not null,site_name text not null,customer_id uuid not null,
 primary key(request_id,start_capture_id)
);
create table private.route_billing_quantity_audit(
 id uuid primary key default gen_random_uuid(),request_id uuid not null,version integer not null,
 actor_id uuid not null,action text not null,snapshot jsonb not null,created_at timestamptz not null default now()
);
alter table private.route_billing_quantity_requests enable row level security;
alter table private.route_billing_quantity_evidence enable row level security;
alter table private.route_billing_quantity_audit enable row level security;
revoke all on private.route_billing_quantity_requests,private.route_billing_quantity_evidence,private.route_billing_quantity_audit from public,anon,authenticated;

-- Retain every sent revision, including requests revised before first approval.
create function private.route_billing_submission_audit() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if tg_op='INSERT' or new.version is distinct from old.version then
  insert into private.route_billing_quantity_audit(request_id,version,actor_id,action,snapshot)
  values(new.id,new.version,auth.uid(),'submit',to_jsonb(new));
 end if;
 return new;
end $$;
revoke all on function private.route_billing_submission_audit() from public,anon,authenticated;
create trigger route_billing_submission_history after insert or update on private.route_billing_quantity_requests
for each row execute function private.route_billing_submission_audit();

create function private.route_billing_actor_can_review(p_company_id uuid) returns boolean
language sql security definer set search_path='' as $$
 select auth.uid() is not null and private.account_access_allowed()
 and private.has_company_feature(p_company_id,'can_manage_invoices') and exists(
 select 1 from public.company_members m where m.company_id=p_company_id and m.user_id=auth.uid() and m.role::text in ('owner','admin','manager'))
$$;
-- Match the current invoice calculation source and daily-before-fixed precedence.
-- Internal helper only: callers enforce requester/reviewer company access.
create function private.route_billing_site_daily_rate(p_company_id uuid,p_site_id uuid)
returns table(unit_price_yen integer,man_day_method boolean)
language sql stable security definer set search_path='' as $$
 select rate.value::integer,
 case when pref.source='trade_company' then pref.contract_method='daily' and rate.value>0
 else rate.value>0 and (coalesce(f.billing_unit_price_yen,0)>0 or
  (coalesce(f.billing_monthly_rate_yen,0)<=0 and
   not (coalesce(f.billing_square_meter_unit_price_yen,0)>0 and coalesce(f.billing_square_meter_quantity,0)>0)
   and coalesce(f.billing_contract_amount_yen,0)<=0)) end
 from public.sites s
 left join public.site_financial_settings f on f.company_id=s.company_id and f.site_id=s.id
 left join lateral (
  select p.source,c.contract_method,c.daily_rate_yen
  from public.site_calculation_source_preferences p
  join public.trade_companies t on t.id=p.trade_company_id and t.company_id=p_company_id
  left join public.trade_company_contracts c on c.company_id=p_company_id and c.trade_company_id=t.id
  where p.company_id=p_company_id and p.site_id=p_site_id and p.output_type='invoice' and p.source='trade_company'
  limit 1
 ) pref on true
 cross join lateral(select private.resolve_rate_formula(
  case when pref.source='trade_company' then coalesce(pref.daily_rate_yen,0) else coalesce(f.billing_unit_price_yen,0) end,
  coalesce(f.billing_rate_formula,'{}'),coalesce(f.billing_rate_overrides,'{}'),'daily') value) rate
 where s.company_id=p_company_id and s.id=p_site_id
$$;
revoke all on function private.route_billing_site_daily_rate(uuid,uuid) from public,anon,authenticated;
create function private.route_billing_quantity_detail(p_request_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare r private.route_billing_quantity_requests%rowtype; evidence jsonb; options jsonb; reviewer boolean; result jsonb;
begin
 if auth.uid() is null or not private.account_access_allowed() then raise exception 'account unavailable' using errcode='42501'; end if;
 select * into r from private.route_billing_quantity_requests where id=p_request_id;
 if not found or not exists(select 1 from public.company_members m where m.company_id=r.company_id and m.user_id=auth.uid())
 or (r.requested_by<>auth.uid() and not private.route_billing_actor_can_review(r.company_id)) then raise exception 'billing request unavailable' using errcode='42501'; end if;
 reviewer:=private.route_billing_actor_can_review(r.company_id);
 select coalesce(jsonb_agg(to_jsonb(e) order by e.start_capture_id),'[]') into evidence from private.route_billing_quantity_evidence e where e.request_id=r.id;
 select coalesce(jsonb_agg(to_jsonb(o) order by o.site_id),'[]') into options from (
 select distinct e.site_id,e.site_name,f.unit_price_yen,f.man_day_method
 from private.route_billing_quantity_evidence e left join lateral private.route_billing_site_daily_rate(r.company_id,e.site_id) f on true where e.request_id=r.id) o;
 result:=to_jsonb(r)||jsonb_build_object('evidence',evidence,'site_options',case when reviewer then options else '[]'::jsonb end,'report_ids',(select coalesce(jsonb_agg(distinct e.report_id),'[]') from private.route_billing_quantity_evidence e where e.request_id=r.id));
 if not reviewer then result:=result-'unit_price_yen'; end if;
 return result;
end $$;
create function public.route_billing_quantity_request_detail(p_request_id uuid) returns jsonb language sql security invoker set search_path='' as $$select private.route_billing_quantity_detail(p_request_id)$$;
create function private.pending_route_billing_quantity_rows() returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
 if auth.uid() is null or not private.account_access_allowed() then raise exception 'account unavailable' using errcode='42501'; end if;
 select coalesce(jsonb_agg(private.route_billing_quantity_detail(r.id) order by r.work_date,r.id),'[]') into result from private.route_billing_quantity_requests r where r.status='pending' and private.route_billing_actor_can_review(r.company_id);
 return result;
end $$;
create function public.pending_route_billing_quantity_rows() returns jsonb language sql security invoker set search_path='' as $$select private.pending_route_billing_quantity_rows()$$;

create function private.submit_route_customer_day_allocations(p_worker_id uuid,p_report_ids uuid[],p_allocations jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare r private.route_visit_reports%rowtype; w public.workers%rowtype; s public.sites%rowtype; item jsonb;
 cid uuid; day date; req private.route_billing_quantity_requests%rowtype; result jsonb:='[]'; wanted_customer uuid; q numeric;
begin
 if auth.uid() is null or not private.account_access_allowed() then raise exception 'account unavailable' using errcode='42501'; end if;
 if coalesce(cardinality(p_report_ids),0)=0 or p_allocations is null or jsonb_typeof(p_allocations)<>'array' or jsonb_array_length(p_allocations)=0 then raise exception 'visit evidence and allocation required'; end if;
 select * into w from public.workers where id=p_worker_id;
 if not found then raise exception 'worker unavailable'; end if;
 cid:=w.company_id;
 if not exists(select 1 from public.company_members m where m.company_id=cid and m.user_id=auth.uid()) then raise exception 'company unavailable' using errcode='42501'; end if;
 perform pg_advisory_xact_lock(hashtextextended('route-billing:'||cid::text||p_worker_id::text,0));
 -- Freeze complete visit IDs and original ownership; no guessed customer matching.
 foreach wanted_customer in array p_report_ids loop
  select * into r from private.route_visit_reports where id=wanted_customer;
  if not found or r.company_id<>cid or (r.created_by<>auth.uid() and not private.route_billing_actor_can_review(cid))
   or r.status not in ('completed','skipped') or not exists(select 1 from jsonb_array_elements(r.roster_workers) v where v->>'worker_id'=p_worker_id::text) then raise exception 'finished visit evidence unavailable' using errcode='42501'; end if;
  if day is null then day:=r.report_date; elsif day<>r.report_date then raise exception 'allocation must be one work date'; end if;
  select * into s from public.sites where id=r.site_id and company_id=cid;
  if not found or s.customer_id is null then raise exception 'customer unresolved; explicit site registration required'; end if;
 end loop;
 if exists(select 1 from jsonb_array_elements(p_allocations) x group by x->>'customer_id' having count(*)>1) then raise exception 'duplicate customer'; end if;
 -- Every evidence customer must be represented, and no unrelated customer may enter.
 if exists(select 1 from private.route_visit_reports v join public.sites st on st.id=v.site_id where v.id=any(p_report_ids)
 and not exists(select 1 from jsonb_array_elements(p_allocations) x where x->>'customer_id'=st.customer_id::text)) then raise exception 'missing customer allocation'; end if;
 for item in select value from jsonb_array_elements(p_allocations) loop
  wanted_customer:=(item->>'customer_id')::uuid;q:=(item->>'quantity')::numeric;
  if q is null or q not in (0.5,1) then raise exception 'quantity must be 1 or 0.5'; end if;
  if not exists(select 1 from private.route_visit_reports v join public.sites st on st.id=v.site_id where v.id=any(p_report_ids) and st.customer_id=wanted_customer and st.company_id=cid) then raise exception 'customer outside visit evidence'; end if;
  insert into private.route_billing_quantity_requests(company_id,worker_id,worker_name,work_date,customer_id,customer_name,requested_quantity,quantity,requested_by)
   select cid,p_worker_id,w.name,day,c.id,c.name,q,q,auth.uid() from public.customers c where c.id=wanted_customer and c.company_id=cid
   on conflict(company_id,worker_id,work_date,customer_id) do nothing;
  select * into req from private.route_billing_quantity_requests where company_id=cid and worker_id=p_worker_id and work_date=day and customer_id=wanted_customer for update;
  if not found then raise exception 'customer unavailable'; end if;
  -- Exact retries return the original state. New evidence invalidates approval/version.
  if req.requested_quantity is distinct from q or exists(select 1 from private.route_visit_reports v join public.sites st on st.id=v.site_id where v.id=any(p_report_ids) and st.customer_id=wanted_customer
   and not exists(select 1 from private.route_billing_quantity_evidence e where e.request_id=req.id and e.start_capture_id=v.start_capture_id)) and exists(select 1 from private.route_billing_quantity_evidence e where e.request_id=req.id) then
   update private.route_billing_quantity_requests set requested_quantity=q,quantity=q,status='pending',version=version+1,reviewed_by=null,reviewed_at=null,representative_site_id=null,unit_price_yen=null,updated_at=now() where id=req.id returning * into req;
  end if;
  insert into private.route_billing_quantity_evidence(request_id,report_id,source_clock_in_id,start_capture_id,end_capture_id,site_id,site_name,customer_id)
   select req.id,v.id,v.source_clock_in_id,v.start_capture_id,v.end_capture_id,v.site_id,v.site_name,st.customer_id from private.route_visit_reports v join public.sites st on st.id=v.site_id where v.id=any(p_report_ids) and st.customer_id=wanted_customer on conflict do nothing;
  result:=result||jsonb_build_array(private.route_billing_quantity_detail(req.id));
 end loop;
 return result;
end $$;
create function public.submit_route_customer_day_allocations(p_worker_id uuid,p_report_ids uuid[],p_allocations jsonb) returns jsonb language sql security invoker set search_path='' as $$select private.submit_route_customer_day_allocations(p_worker_id,p_report_ids,p_allocations)$$;

create function private.decide_route_billing_quantity(p_request_id uuid,p_quantity numeric,p_decision text,p_note text,p_expected_version integer,p_representative_site_id uuid default null,p_unit_price_yen integer default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare r private.route_billing_quantity_requests%rowtype; result jsonb;
begin
 if auth.uid() is null or not private.account_access_allowed() then raise exception 'account unavailable' using errcode='42501'; end if;
 select * into r from private.route_billing_quantity_requests where id=p_request_id for update;
 if not found or not private.route_billing_actor_can_review(r.company_id) then raise exception 'manager approval required' using errcode='42501'; end if;
 if p_expected_version is null or r.version<>p_expected_version then raise exception 'request changed; reload before approving' using errcode='40001'; end if;
 if p_decision is null or p_decision not in ('approve','reject') then raise exception 'invalid decision'; end if;
 if r.status<>'pending' then
  if r.reviewed_by=auth.uid() and ((p_decision='approve' and r.status='approved' and r.quantity=p_quantity and r.representative_site_id=p_representative_site_id and r.unit_price_yen=p_unit_price_yen) or (p_decision='reject' and r.status='rejected')) then return private.route_billing_quantity_detail(r.id); end if;
  raise exception 'request already reviewed';
 end if;
 if p_decision='approve' then
  if p_quantity is null or p_quantity not in (0.5,1) or p_unit_price_yen is null or p_unit_price_yen<=0 or p_representative_site_id is null then raise exception 'explicit quantity, representative site and price required'; end if;
  if not exists(select 1 from private.route_billing_quantity_evidence e join public.sites s on s.id=e.site_id and s.company_id=r.company_id
   join lateral private.route_billing_site_daily_rate(s.company_id,s.id) f on true
   where e.request_id=r.id and e.site_id=p_representative_site_id and e.customer_id=r.customer_id and s.customer_id=r.customer_id
   and f.man_day_method) then raise exception 'representative site must be evidenced man-day billing site'; end if;
  if exists(select 1 from private.route_billing_quantity_evidence e join public.sites s on s.id=e.site_id where e.request_id=r.id and s.customer_id is distinct from e.customer_id) then raise exception 'customer evidence changed; resubmit'; end if;
 end if;
 update private.route_billing_quantity_requests set quantity=case when p_decision='approve' then p_quantity else quantity end,
 status=case when p_decision='approve' then 'approved' else 'rejected' end,representative_site_id=case when p_decision='approve' then p_representative_site_id end,
 unit_price_yen=case when p_decision='approve' then p_unit_price_yen end,reviewed_by=auth.uid(),reviewed_at=now(),review_note=p_note,updated_at=now() where id=r.id returning * into r;
 result:=private.route_billing_quantity_detail(r.id);
 insert into private.route_billing_quantity_audit(request_id,version,actor_id,action,snapshot) values(r.id,r.version,auth.uid(),p_decision,result);
 return result;
end $$;
create function public.decide_route_billing_quantity(p_request_id uuid,p_quantity numeric,p_decision text,p_note text,p_expected_version integer,p_representative_site_id uuid default null,p_unit_price_yen integer default null) returns jsonb language sql security invoker set search_path='' as $$select private.decide_route_billing_quantity(p_request_id,p_quantity,p_decision,p_note,p_expected_version,p_representative_site_id,p_unit_price_yen)$$;
revoke all on function private.route_billing_actor_can_review(uuid) from public,anon,authenticated;
revoke all on function private.route_billing_quantity_detail(uuid) from public,anon,authenticated;
grant execute on function private.route_billing_quantity_detail(uuid) to authenticated;
revoke all on function public.route_billing_quantity_request_detail(uuid) from public,anon,authenticated;
grant execute on function public.route_billing_quantity_request_detail(uuid) to authenticated;
revoke all on function private.pending_route_billing_quantity_rows() from public,anon,authenticated;
grant execute on function private.pending_route_billing_quantity_rows() to authenticated;
revoke all on function public.pending_route_billing_quantity_rows() from public,anon,authenticated;
grant execute on function public.pending_route_billing_quantity_rows() to authenticated;
revoke all on function private.submit_route_customer_day_allocations(uuid,uuid[],jsonb) from public,anon,authenticated;
grant execute on function private.submit_route_customer_day_allocations(uuid,uuid[],jsonb) to authenticated;
revoke all on function public.submit_route_customer_day_allocations(uuid,uuid[],jsonb) from public,anon,authenticated;
grant execute on function public.submit_route_customer_day_allocations(uuid,uuid[],jsonb) to authenticated;
revoke all on function private.decide_route_billing_quantity(uuid,numeric,text,text,integer,uuid,integer) from public,anon,authenticated;
grant execute on function private.decide_route_billing_quantity(uuid,numeric,text,text,integer,uuid,integer) to authenticated;
revoke all on function public.decide_route_billing_quantity(uuid,numeric,text,text,integer,uuid,integer) from public,anon,authenticated;
grant execute on function public.decide_route_billing_quantity(uuid,numeric,text,text,integer,uuid,integer) to authenticated;

-- Staged integration: do not deploy until migration and concurrency tests pass.
-- Keep the existing ordinary invoice generator, sealed history and payroll intact.
create index route_billing_customer_month_idx on private.route_billing_quantity_requests(company_id,customer_id,work_date);
create index route_billing_evidence_report_idx on private.route_billing_quantity_evidence(report_id,request_id);
create function private.route_billing_invoice_blocked(cid uuid, customer uuid, first_day date, last_day date)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from private.route_billing_quantity_requests q
  where q.company_id=cid and q.customer_id=customer and q.work_date between first_day and last_day
  and (q.status='pending' or (q.status='approved' and exists(
   select 1 from private.route_billing_quantity_evidence e join public.sites s on s.id=e.site_id
   where e.request_id=q.id and (s.company_id<>cid or s.customer_id is distinct from e.customer_id)))))
 or exists(select 1 from private.route_visit_reports v
  join public.sites s on s.id=v.site_id and s.company_id=v.company_id,
  lateral jsonb_array_elements(v.workers) w
  where v.company_id=cid and s.customer_id=customer and v.report_date between first_day and last_day
  and v.status='completed' and not exists(
   select 1 from private.route_billing_quantity_requests q join private.route_billing_quantity_evidence e on e.request_id=q.id
   where q.company_id=cid and q.customer_id=customer and q.work_date=v.report_date
   and q.worker_id::text=w->>'worker_id' and e.report_id=v.id));
$$;
revoke all on function private.route_billing_invoice_blocked(uuid,uuid,date,date) from public,anon,authenticated;

create function private.route_billing_invoice_components(cid uuid, customer uuid, first_day date, last_day date)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare r record; blocks jsonb:='[]'; lines jsonb; base numeric; welfare numeric; tax numeric;
 subtotal numeric:=0; tax_total numeric:=0; welfare_total numeric:=0; tax_rate numeric;
begin
 select greatest(coalesce(c.tax_rate,0),0) into tax_rate from public.companies c where c.id=cid;
 for r in select q.*,coalesce(nullif(s.formal_name,''),s.name) site_name,
  case when f.welfare_rate between 0 and 100 then f.welfare_rate else 0 end welfare_rate
  from private.route_billing_quantity_requests q join public.sites s on s.id=q.representative_site_id
  left join public.site_financial_settings f on f.company_id=cid and f.site_id=s.id
  where q.company_id=cid and q.customer_id=customer and q.work_date between first_day and last_day
  and q.status='approved' and s.company_id=cid and s.customer_id=customer
  and not exists(select 1 from private.route_billing_quantity_evidence e join public.sites es on es.id=e.site_id
   where e.request_id=q.id and (es.company_id<>cid or es.customer_id is distinct from e.customer_id))
  order by q.work_date,q.worker_id,q.id loop
  base:=round(r.quantity*r.unit_price_yen);
  welfare:=round(base*r.welfare_rate/100);tax:=round((base+welfare)*tax_rate/100);
  lines:=jsonb_build_array(jsonb_build_object('site_label',r.site_name,'work_content','ルート作業',
   'quantity',r.quantity,'unit_price',r.unit_price_yen,'unit_price_text',r.unit_price_yen::text,'amount',base,
   'route_billing_request_id',r.id,'route_billing_version',r.version));
  if welfare>0 then lines:=lines||jsonb_build_array(jsonb_build_object('site_label','〃','work_content','（法定福利費）',
   'quantity',0,'unit_price',0,'unit_price_text','','amount',welfare));end if;
  if tax>0 then lines:=lines||jsonb_build_array(jsonb_build_object('site_label','〃','work_content','（消費税）',
   'quantity',0,'unit_price',0,'unit_price_text',tax_rate::text||'%','amount',tax));end if;
  blocks:=blocks||jsonb_build_array(jsonb_build_object('site_id',r.representative_site_id,'site_name',r.site_name,
   'route_billing_request_id',r.id,'manual_adjustment',0,'welfare_rate_bps',r.welfare_rate*100,
   'subtotal',base+welfare,'tax',tax,'grand_total',base+welfare+tax,'lines',lines));
  subtotal:=subtotal+base+welfare;tax_total:=tax_total+tax;welfare_total:=welfare_total+welfare;
 end loop;
 return jsonb_build_object('sites',blocks,'subtotal',subtotal,'tax',tax_total,'welfare',welfare_total,
  'blocked',private.route_billing_invoice_blocked(cid,customer,first_day,last_day),
  'has_requests',exists(select 1 from private.route_billing_quantity_requests q where q.company_id=cid
   and q.customer_id=customer and q.work_date between first_day and last_day));
end $$;
revoke all on function private.route_billing_invoice_components(uuid,uuid,date,date) from public,anon,authenticated;

-- Patch narrowly inside the current definition, including its existing seal additions.
do $$
declare definition text; anchor text; addition text;
begin
 definition:=pg_get_functiondef('private.refresh_automatic_invoice(uuid,uuid,date)'::regprocedure);
 anchor:='  n integer:=0;';
 if (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 then raise exception 'Unexpected invoice declaration';end if;
 definition:=replace(definition,anchor,anchor||E'\n  route_parts jsonb; route_blocked boolean:=false;');
 anchor:='  if n=0 then';
 if (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 then raise exception 'Unexpected invoice totals';end if;
 addition:=$hook$  route_parts:=private.route_billing_invoice_components(cid,customer,first_day,last_day);
  route_blocked:=(route_parts->>'blocked')::boolean;
  sites_json:=sites_json||(route_parts->'sites');
  total_pre_tax:=total_pre_tax+(route_parts->>'subtotal')::numeric;
  total_tax:=total_tax+(route_parts->>'tax')::numeric;
  total_welfare:=total_welfare+(route_parts->>'welfare')::numeric;
  if (route_parts->>'has_requests')::boolean or route_blocked then n:=n+1;end if;
$hook$;
 definition:=replace(definition,anchor,addition||anchor);
 anchor:='snapshot_value:=snapshot_value||private.document_company_seal_snapshot';
 if strpos(definition,anchor)>0 then
  definition:=replace(definition,anchor,E'snapshot_value:=snapshot_value||jsonb_build_object(''route_quantity_pending'',route_blocked);\n  '||anchor);
 else
  anchor:='  if existing.id is null then';
  if (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 then raise exception 'Unexpected invoice snapshot';end if;
  definition:=replace(definition,anchor,E'  snapshot_value:=snapshot_value||jsonb_build_object(''route_quantity_pending'',route_blocked);\n'||anchor);
 end if;
 anchor:='snapshot_value,true,false';
 if (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 then raise exception 'Unexpected invoice insert';end if;
 definition:=replace(definition,anchor,'snapshot_value,true,route_blocked');
 anchor:='calculation_blocked=false';
 if (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 then raise exception 'Unexpected invoice update';end if;
 execute replace(definition,anchor,'calculation_blocked=route_blocked');
end $$;

-- Acquire invoice locks before request row locks, including manager decisions.
do $$
declare definition text; anchor text; addition text;
begin
 definition:=pg_get_functiondef('private.decide_route_billing_quantity(uuid,numeric,text,text,integer,uuid,integer)'::regprocedure);
 anchor:=' select * into r from private.route_billing_quantity_requests where id=p_request_id for update;';
 if (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 then raise exception 'Unexpected billing decision lock';end if;
 addition:=$hook$ select * into r from private.route_billing_quantity_requests where id=p_request_id;
 if not found or not private.route_billing_actor_can_review(r.company_id) then raise exception 'manager approval required' using errcode='42501';end if;
 perform pg_advisory_xact_lock(hashtextextended('invoice:'||r.company_id::text||r.customer_id::text||date_trunc('month',r.work_date)::date::text,0));
$hook$;
 execute replace(definition,anchor,addition||anchor);
 definition:=pg_get_functiondef('private.submit_route_customer_day_allocations(uuid,uuid[],jsonb)'::regprocedure);
 anchor:=' for item in select value from jsonb_array_elements(p_allocations) loop';
 if (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 then raise exception 'Unexpected allocation lock';end if;
 addition:=$hook$ for wanted_customer in select (x->>'customer_id')::uuid from jsonb_array_elements(p_allocations) x order by x->>'customer_id' loop
  perform pg_advisory_xact_lock(hashtextextended('invoice:'||cid::text||wanted_customer::text||date_trunc('month',day)::date::text,0));
 end loop;
$hook$;
 execute replace(definition,anchor,addition||anchor);
end $$;

create function private.route_billing_request_invoice_lock() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 perform pg_advisory_xact_lock(hashtextextended('invoice:'||new.company_id::text||new.customer_id::text||date_trunc('month',new.work_date)::date::text,0));
 if exists(select 1 from public.invoices i where i.company_id=new.company_id and i.customer_id=new.customer_id
  and new.work_date between i.billing_period_start and i.billing_period_end
  and (i.status<>'draft' or i.finalized_at is not null or i.approval_finalized_at is not null or not i.automatic_calculation)) then
  raise exception '確定済みまたは手動編集の請求書があります。先に請求書を確認してください。';
 end if;
 return new;
end $$;
revoke all on function private.route_billing_request_invoice_lock() from public,anon,authenticated;
create trigger route_billing_invoice_lock before insert or update on private.route_billing_quantity_requests
for each row execute function private.route_billing_request_invoice_lock();

create function private.route_billing_refresh_invoice() returns trigger
language plpgsql security definer set search_path='' as $$
begin perform private.refresh_automatic_invoice(new.company_id,new.customer_id,new.work_date);return new;end $$;
revoke all on function private.route_billing_refresh_invoice() from public,anon,authenticated;
create trigger route_billing_invoice_refresh after insert or update on private.route_billing_quantity_requests
for each row execute function private.route_billing_refresh_invoice();

create function private.route_billing_invoice_finalization_guard() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if (tg_op='INSERT' or (old.status='draft' and old.finalized_at is null and old.approval_finalized_at is null))
  and (new.status<>'draft' or new.finalized_at is not null or new.approval_finalized_at is not null) then
  -- UPDATE already holds the invoice row: never wait on a generator that needs it.
  if not pg_try_advisory_xact_lock(hashtextextended('invoice:'||new.company_id::text||new.customer_id::text||new.billing_period_start::text,0)) then
   raise exception '請求数量を更新中です。再読み込みしてから確定してください。' using errcode='40001';
  end if;
  if private.route_billing_invoice_blocked(new.company_id,new.customer_id,new.billing_period_start,new.billing_period_end) then
   raise exception 'ルート請求数量の申請・承認が完了していません。';
  end if;
 end if;
 return new;
end $$;
revoke all on function private.route_billing_invoice_finalization_guard() from public,anon,authenticated;
create trigger route_billing_invoice_finalization before insert or update on public.invoices
for each row execute function private.route_billing_invoice_finalization_guard();

-- Staged contract for explicit submissions after checkout. No payroll writes.
create function public.route_customer_day_quantity_candidates(p_worker_id uuid,p_work_date date)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare cid uuid; result jsonb; unresolved integer;
begin
 if auth.uid() is null or not private.account_access_allowed() then raise exception 'account unavailable' using errcode='42501';end if;
 select company_id into cid from public.workers where id=p_worker_id;
 if cid is null or p_work_date is null or not exists(select 1 from public.company_members m where m.company_id=cid and m.user_id=auth.uid()) then
  raise exception 'worker unavailable' using errcode='42501';end if;
 select count(*) into unresolved from private.route_visit_reports v left join public.sites s on s.id=v.site_id and s.company_id=cid
 where v.company_id=cid and v.created_by=auth.uid() and v.report_date=p_work_date and v.status='completed'
 and exists(select 1 from jsonb_array_elements(v.workers) w where w->>'worker_id'=p_worker_id::text)
 and exists(select 1 from public.attendance_verifications a where a.source_clock_in_id=v.source_clock_in_id and a.company_id=cid and a.event_type='clock_out')
 and (s.customer_id is null or not exists(select 1 from public.customers c where c.id=s.customer_id and c.company_id=cid));
 select coalesce(jsonb_agg(to_jsonb(x) order by x.customer_name,x.customer_id),'[]') into result from (
  select c.id customer_id,c.name customer_name,jsonb_agg(v.id order by v.created_at,v.id) report_ids,
  jsonb_agg(jsonb_build_object('id',v.id,'site_name',v.site_name) order by v.created_at,v.id) visits,
  q.id request_id,coalesce(q.version,0) version,q.status,q.requested_quantity,q.quantity
  from private.route_visit_reports v join public.sites s on s.id=v.site_id and s.company_id=cid
  join public.customers c on c.id=s.customer_id and c.company_id=cid
  left join private.route_billing_quantity_requests q on q.company_id=cid and q.worker_id=p_worker_id and q.work_date=p_work_date and q.customer_id=c.id
  where v.company_id=cid and v.created_by=auth.uid() and v.report_date=p_work_date and v.status='completed'
  and exists(select 1 from jsonb_array_elements(v.workers) w where w->>'worker_id'=p_worker_id::text)
  and exists(select 1 from public.attendance_verifications a where a.source_clock_in_id=v.source_clock_in_id and a.company_id=cid and a.event_type='clock_out')
  group by c.id,c.name,q.id,q.version,q.status,q.requested_quantity,q.quantity
 ) x;
 return jsonb_build_object('customers',result,'unresolved_count',unresolved);
end $$;
revoke all on function public.route_customer_day_quantity_candidates(uuid,date) from public,anon,authenticated;
grant execute on function public.route_customer_day_quantity_candidates(uuid,date) to authenticated;

create function public.submit_route_customer_day_allocations_checked(
 p_worker_id uuid,p_work_date date,p_report_ids uuid[],p_allocations jsonb,p_expected_versions jsonb
) returns jsonb language plpgsql security definer set search_path='' as $$
declare cid uuid; item jsonb; wanted uuid; actual integer; expected integer; available jsonb;
 current_request private.route_billing_quantity_requests%rowtype;
begin
 if auth.uid() is null or not private.account_access_allowed() then raise exception 'account unavailable' using errcode='42501';end if;
 select company_id into cid from public.workers where id=p_worker_id;
 if cid is null or p_work_date is null or not exists(select 1 from public.company_members m where m.company_id=cid and m.user_id=auth.uid()) then raise exception 'worker unavailable' using errcode='42501';end if;
 if p_expected_versions is null or jsonb_typeof(p_expected_versions)<>'object' or p_allocations is null or jsonb_typeof(p_allocations)<>'array' or jsonb_array_length(p_allocations)=0 then raise exception 'expected versions and allocations required';end if;
 perform pg_advisory_xact_lock(hashtextextended('route-billing:'||cid::text||p_worker_id::text,0));
 for wanted in select (x->>'customer_id')::uuid from jsonb_array_elements(p_allocations) x order by x->>'customer_id' loop
  perform pg_advisory_xact_lock(hashtextextended('invoice:'||cid::text||wanted::text||date_trunc('month',p_work_date)::date::text,0));
 end loop;
 available:=public.route_customer_day_quantity_candidates(p_worker_id,p_work_date);
 if (available->>'unresolved_count')::int>0 then raise exception '取引会社未設定の現場があります。登録を確認してください。';end if;
 if coalesce(cardinality(p_report_ids),0)=0 or exists(select 1 from unnest(p_report_ids) report_id where not exists(
  select 1 from jsonb_array_elements(available->'customers') c,jsonb_array_elements_text(c->'report_ids') saved_id where saved_id=report_id::text)) then raise exception 'checked-out visit evidence unavailable' using errcode='42501';end if;
 -- Submit the complete displayed day; a newly finished visit cannot be omitted.
 if exists(select 1 from jsonb_array_elements(available->'customers') c,jsonb_array_elements_text(c->'report_ids') saved_id where not saved_id=any(select unnest(p_report_ids)::text)) then
  raise exception '訪問日報が更新されました。再読み込みしてください。' using errcode='40001';end if;
 for item in select value from jsonb_array_elements(p_allocations) loop
  wanted:=(item->>'customer_id')::uuid;
  if not (p_expected_versions ? wanted::text) or jsonb_typeof(p_expected_versions->wanted::text)<>'number' then raise exception 'expected customer version required';end if;
  expected:=(p_expected_versions->>wanted::text)::integer;
  select * into current_request from private.route_billing_quantity_requests where company_id=cid and worker_id=p_worker_id and work_date=p_work_date and customer_id=wanted;
  actual:=current_request.version;
  if coalesce(actual,0)<>expected then raise exception '申請が更新されました。再読み込みしてください。' using errcode='40001';end if;
  if current_request.status='rejected' and current_request.requested_quantity=(item->>'quantity')::numeric then
   raise exception '却下済みの申請です。数量の変更または管理者への確認が必要です。';end if;
 end loop;
 return private.submit_route_customer_day_allocations(p_worker_id,p_report_ids,p_allocations);
end $$;
revoke all on function public.submit_route_customer_day_allocations_checked(uuid,date,uuid[],jsonb,jsonb) from public,anon,authenticated;
grant execute on function public.submit_route_customer_day_allocations_checked(uuid,date,uuid[],jsonb,jsonb) to authenticated;
-- No legacy client is connected in production. The unchecked wrapper is internal only.
revoke execute on function public.submit_route_customer_day_allocations(uuid,uuid[],jsonb) from authenticated;
revoke execute on function private.submit_route_customer_day_allocations(uuid,uuid[],jsonb) from authenticated;

commit;
