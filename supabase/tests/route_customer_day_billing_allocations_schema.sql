-- DRAFT schema awaiting CLI-generated migration and invoice integration review.
-- Dedicated billing quantity only; never writes canonical attendance or payroll.
create table private.route_billing_quantity_requests(
 id uuid primary key default gen_random_uuid(),company_id uuid not null,worker_id uuid not null,worker_name text not null,
 work_date date not null,customer_id uuid not null,customer_name text not null,
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

create function private.route_billing_actor_can_review(p_company_id uuid) returns boolean
language sql security definer set search_path='' as $$
 select auth.uid() is not null and private.account_access_allowed() and exists(
 select 1 from public.company_members m where m.company_id=p_company_id and m.user_id=auth.uid() and m.role::text in ('owner','admin','manager'))
$$;
create function private.route_billing_quantity_detail(p_request_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare r private.route_billing_quantity_requests%rowtype; evidence jsonb; options jsonb;
begin
 if auth.uid() is null or not private.account_access_allowed() then raise exception 'account unavailable' using errcode='42501'; end if;
 select * into r from private.route_billing_quantity_requests where id=p_request_id;
 if not found or not exists(select 1 from public.company_members m where m.company_id=r.company_id and m.user_id=auth.uid())
 or (r.requested_by<>auth.uid() and not private.route_billing_actor_can_review(r.company_id)) then raise exception 'billing request unavailable' using errcode='42501'; end if;
 select coalesce(jsonb_agg(to_jsonb(e) order by e.start_capture_id),'[]') into evidence from private.route_billing_quantity_evidence e where e.request_id=r.id;
 select coalesce(jsonb_agg(to_jsonb(o) order by o.site_id),'[]') into options from (
 select distinct e.site_id,e.site_name,f.billing_unit_price_yen as unit_price_yen,
 (coalesce(f.billing_unit_price_yen,0)>0 and coalesce(f.billing_square_meter_unit_price_yen,0)=0 and coalesce(f.billing_contract_amount_yen,0)=0) as man_day_method
 from private.route_billing_quantity_evidence e left join public.site_financial_settings f on f.company_id=r.company_id and f.site_id=e.site_id where e.request_id=r.id) o;
 return to_jsonb(r)||jsonb_build_object('evidence',evidence,'site_options',options,'report_ids',(select coalesce(jsonb_agg(distinct e.report_id),'[]') from private.route_billing_quantity_evidence e where e.request_id=r.id));
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
  insert into private.route_billing_quantity_requests(company_id,worker_id,worker_name,work_date,customer_id,customer_name,quantity,requested_by)
   select cid,p_worker_id,w.name,day,c.id,c.name,q,auth.uid() from public.customers c where c.id=wanted_customer and c.company_id=cid
   on conflict(company_id,worker_id,work_date,customer_id) do nothing;
  select * into req from private.route_billing_quantity_requests where company_id=cid and worker_id=p_worker_id and work_date=day and customer_id=wanted_customer for update;
  if not found then raise exception 'customer unavailable'; end if;
  -- Exact retries return the original state. New evidence invalidates approval/version.
  if req.quantity is distinct from q or exists(select 1 from private.route_visit_reports v join public.sites st on st.id=v.site_id where v.id=any(p_report_ids) and st.customer_id=wanted_customer
   and not exists(select 1 from private.route_billing_quantity_evidence e where e.request_id=req.id and e.start_capture_id=v.start_capture_id)) and exists(select 1 from private.route_billing_quantity_evidence e where e.request_id=req.id) then
   update private.route_billing_quantity_requests set quantity=q,status='pending',version=version+1,reviewed_by=null,reviewed_at=null,representative_site_id=null,unit_price_yen=null,updated_at=now() where id=req.id returning * into req;
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
   join public.site_financial_settings f on f.site_id=s.id and f.company_id=s.company_id
   where e.request_id=r.id and e.site_id=p_representative_site_id and e.customer_id=r.customer_id and s.customer_id=r.customer_id
   and f.billing_unit_price_yen>0 and coalesce(f.billing_square_meter_unit_price_yen,0)=0 and coalesce(f.billing_contract_amount_yen,0)=0) then raise exception 'representative site must be evidenced man-day billing site'; end if;
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
