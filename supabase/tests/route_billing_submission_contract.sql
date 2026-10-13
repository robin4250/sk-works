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
