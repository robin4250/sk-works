CREATE OR REPLACE FUNCTION private.pending_route_billing_quantity_rows()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare result jsonb;
begin
 if auth.uid() is null or not private.account_access_allowed() then raise exception 'account unavailable' using errcode='42501'; end if;
 select coalesce(jsonb_agg(private.route_billing_quantity_detail(r.id) order by r.work_date,r.id),'[]') into result from private.route_billing_quantity_requests r where r.status='pending' and private.route_billing_actor_can_review(r.company_id);
 return result;
end $function$;
CREATE OR REPLACE FUNCTION private.route_billing_invoice_blocked(cid uuid, customer uuid, first_day date, last_day date)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$;
CREATE OR REPLACE FUNCTION private.route_billing_invoice_components(cid uuid, customer uuid, first_day date, last_day date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
end $function$;