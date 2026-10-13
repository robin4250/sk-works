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
