begin;
set local lock_timeout='5s';
-- Conversion receipts are independent of live pricing and payroll/attendance.
create table private.line_historical_invoice_commands (
 company_id uuid not null, actor_id uuid not null, command_id uuid not null,
 quote_id uuid not null unique references private.line_historical_quote_snapshots(id),
 group_id uuid not null,work_month date not null,
 unique(company_id,group_id,work_month),
 payload jsonb not null, result jsonb not null, created_at timestamptz not null default now(),
 primary key(company_id,actor_id,command_id)
);
create table private.line_historical_invoice_links (
 company_id uuid not null,customer_id uuid not null,work_month date not null,
 quote_id uuid not null references private.line_historical_quote_snapshots(id),
 actor_id uuid not null,command_id uuid not null,invoice_id uuid not null,
 invoice_fingerprint text not null,last_refresh_fingerprint text,refresh_result jsonb,
 primary key(company_id,customer_id,work_month),
 foreign key(company_id,actor_id,command_id) references private.line_historical_invoice_commands(company_id,actor_id,command_id)
);
alter table private.line_historical_invoice_commands enable row level security;
alter table private.line_historical_invoice_links enable row level security;
revoke all on private.line_historical_invoice_commands,private.line_historical_invoice_links from public,anon,authenticated;

create function private.require_line_historical_invoice_quote(p_quote_id uuid)
returns private.line_historical_quote_snapshots language plpgsql stable security definer set search_path='' as $$
declare q private.line_historical_quote_snapshots; cid uuid;
begin
 select * into q from private.line_historical_quote_snapshots where id=p_quote_id;
 if q.id is null then raise exception 'Historical quote unavailable' using errcode='42501';end if;
 cid:=private.line_historical_quote_access(q.group_id);
 if q.company_id is distinct from cid or q.snapshot->>'is_historical_review' is distinct from 'true'
  or q.snapshot->>'invoice_created' is distinct from 'false' or q.work_month>=date_trunc('month',now() at time zone 'Asia/Tokyo')::date then
  raise exception 'Historical quote unavailable' using errcode='42501';end if;
 return q;
end $$;
create function private.line_historical_invoice_workspace(p_quote_id uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare q private.line_historical_quote_snapshots; customers jsonb; receipts jsonb;
begin
 q:=private.require_line_historical_invoice_quote(p_quote_id);
 select coalesce(jsonb_agg(jsonb_build_object('id',c.id,'name',c.name,'address',coalesce(c.billing_address,'')) order by c.name,c.id),'[]') into customers
 from public.customers c where c.company_id=q.company_id and c.notes is distinct from 'sko_system_unassigned_invoice_customer';
 select coalesce(jsonb_agg(jsonb_build_object('customer_id',r.customer_id,'invoice_id',r.invoice_id,'customer_name',i.snapshot->>'customer_name','work_month',r.work_month,'grand_total',i.grand_total,'invoice_exists',i.id is not null,'status',i.status) order by r.customer_id),'[]') into receipts
 from private.line_historical_invoice_links r left join public.invoices i on i.id=r.invoice_id and i.company_id=r.company_id where r.company_id=q.company_id and r.quote_id=q.id;
 return jsonb_build_object('quote_id',q.id,'quote',q.snapshot,'quote_fingerprint',md5(jsonb_build_object('id',q.id,'snapshot',q.snapshot,'rates',q.input_rates,'source',q.source_fingerprint)::text),'customers',customers,'created_invoices',receipts);
end $$;

create function private.line_historical_invoice_preview(p_quote_id uuid,p_quote_fingerprint text,p_site_terms jsonb,p_tax_rate_bps integer,p_terms_confirmed boolean)
returns jsonb language plpgsql security definer set search_path='' as $$
declare q private.line_historical_quote_snapshots; site record; customer record; category jsonb; term jsonb; lines jsonb; sites jsonb:='[]'; quotes jsonb:='[]'; data jsonb;
 allowance record; amount numeric; base numeric; welfare numeric; tax numeric; site_total numeric; subtotal numeric; tax_total numeric; welfare_total numeric; expense jsonb; expenses numeric;
 site_name text; content text; fingerprint text;
begin
 q:=private.require_line_historical_invoice_quote(p_quote_id);
 fingerprint:=md5(jsonb_build_object('id',q.id,'snapshot',q.snapshot,'rates',q.input_rates,'source',q.source_fingerprint)::text);
 if p_quote_fingerprint is distinct from fingerprint then raise exception 'Historical quote changed' using errcode='40001';end if;
 if p_terms_confirmed is distinct from true or p_tax_rate_bps is null or p_tax_rate_bps not between 0 and 10000
  or p_site_terms is null or jsonb_typeof(p_site_terms)<>'array' then raise exception 'Explicit historical customer and tax/welfare terms required' using errcode='22023';end if;
 if jsonb_typeof(q.snapshot->'lines') is distinct from 'array' or jsonb_array_length(q.snapshot->'lines')=0
  or jsonb_typeof(q.snapshot->'rows') is distinct from 'array' then raise exception 'Saved quote lines unavailable' using errcode='22023';end if;
 if jsonb_array_length(p_site_terms)<>(select count(distinct x->>'site_id') from jsonb_array_elements(q.snapshot->'lines') x)
  or exists(select 1 from jsonb_array_elements(p_site_terms) t where not exists(select 1 from jsonb_array_elements(q.snapshot->'lines') x where x->>'site_id'=t->>'site_id')) then
  raise exception 'One explicit term per historical site required' using errcode='22023';end if;
 -- Only identity/address metadata are read; no current rates, tax or welfare defaults.
 begin lock table public.customers,public.sites in share mode nowait;
 exception when lock_not_available then raise exception 'Customer metadata changing; preview again' using errcode='40001';end;
 for site in select distinct x->>'site_id' id from jsonb_array_elements(q.snapshot->'lines') x order by 1 loop
  if (select count(*) from jsonb_array_elements(p_site_terms) t where t->>'site_id'=site.id)<>1 then raise exception 'Duplicate historical site terms' using errcode='22023';end if;
  select t into term from jsonb_array_elements(p_site_terms) t where t->>'site_id'=site.id;
  site_name:=nullif(trim(term->>'site_name'),'');
  if site_name is null or length(site_name)>200 or jsonb_typeof(term->'welfare_rate_bps') is distinct from 'number'
   or (term->>'welfare_rate_bps')::numeric not between 0 and 10000 or (term->>'welfare_rate_bps')::numeric<>trunc((term->>'welfare_rate_bps')::numeric)
   or not exists(select 1 from public.sites s where s.id=site.id::uuid and s.company_id=q.company_id)
   or not exists(select 1 from public.customers c where c.id=(term->>'customer_id')::uuid and c.company_id=q.company_id and c.notes is distinct from 'sko_system_unassigned_invoice_customer') then
   raise exception 'Confirm historical site, customer and welfare terms' using errcode='22023';end if;
  lines:='[]';base:=0;
  for category in select value from jsonb_array_elements(q.snapshot->'lines') where value->>'site_id'=site.id order by value->>'work_category' loop
   content:=case category->>'work_category' when 'day' then '日勤' when 'night' then '夜勤' when 'holiday' then '休日出勤' when 'holiday_night' then '休日夜勤' else null end;
   if content is null then raise exception 'Historical work category unavailable' using errcode='22023';end if;
   amount:=round((category->>'man_days')::numeric*(category->'rates'->>'day')::numeric);base:=base+amount;
   lines:=lines||jsonb_build_array(jsonb_build_object('site_label',site_name,'work_content',content,'quantity',category->'man_days','unit_price',category->'rates'->'day','unit_price_text',category->'rates'->>'day','amount',amount,'unit','人工'));
   if (category->>'overtime_hours')::numeric>0 then
    amount:=round((category->>'overtime_hours')::numeric*(category->'rates'->>'overtime')::numeric);base:=base+amount;
    lines:=lines||jsonb_build_array(jsonb_build_object('site_label','〃','work_content',content||'残業','quantity',category->'overtime_hours','unit_price',category->'rates'->'overtime','unit_price_text',category->'rates'->>'overtime','amount',amount,'unit','時間'));
   end if;
   if (category->>'early_hours')::numeric>0 then
    amount:=round((category->>'early_hours')::numeric*(category->'rates'->>'early')::numeric);base:=base+amount;
    lines:=lines||jsonb_build_array(jsonb_build_object('site_label','〃','work_content',content||'早出','quantity',category->'early_hours','unit_price',category->'rates'->'early','unit_price_text',category->'rates'->>'early','amount',amount,'unit','時間'));
   end if;
   for allowance in select name,count(*) quantity from (select distinct r->>'row_id' row_id,a.name from jsonb_array_elements(q.snapshot->'rows') r cross join lateral jsonb_array_elements_text(r->'allowance_names') a(name) where coalesce(r->>'excluded','false')<>'true' and r->>'site_id'=site.id and r->>'work_category'=category->>'work_category') names group by name order by name loop
    amount:=allowance.quantity*(category->'rates'->'allowances'->>allowance.name)::numeric;base:=base+amount;
    lines:=lines||jsonb_build_array(jsonb_build_object('site_label','〃','work_content',allowance.name,'quantity',allowance.quantity,'unit_price',category->'rates'->'allowances'->allowance.name,'unit_price_text',category->'rates'->'allowances'->>allowance.name,'amount',amount,'unit','回','allowance_name',allowance.name));
   end loop;
  end loop;
  if base is distinct from (select sum((c->>'subtotal')::numeric) from jsonb_array_elements(q.snapshot->'lines') c where c->>'site_id'=site.id) then raise exception 'Saved subtotal inconsistent' using errcode='22023';end if;
  welfare:=round(base*(term->>'welfare_rate_bps')::numeric/10000);site_total:=base+welfare;tax:=round(site_total*p_tax_rate_bps/10000);
  if welfare>0 then lines:=lines||jsonb_build_array(jsonb_build_object('site_label','〃','work_content','法定福利費','quantity',0,'unit_price',0,'unit_price_text','','amount',welfare));end if;
  if tax>0 then lines:=lines||jsonb_build_array(jsonb_build_object('site_label','〃','work_content','消費税','quantity',0,'unit_price',0,'unit_price_text',(p_tax_rate_bps::numeric/100)::text||'%','amount',tax));end if;
  sites:=sites||jsonb_build_array(jsonb_build_object('site_id',site.id,'site_name',site_name,'customer_id',term->>'customer_id','historical_base_subtotal',base,'welfare_rate_bps',term->'welfare_rate_bps','welfare',welfare,'subtotal',site_total,'tax',tax,'grand_total',site_total+tax,'manual_adjustment',0,'lines',lines));
 end loop;
 for customer in select distinct c.id,c.name,c.billing_address from public.customers c join jsonb_array_elements(p_site_terms) t on c.id=(t->>'customer_id')::uuid where c.company_id=q.company_id order by c.id loop
  select sum((s->>'subtotal')::numeric),sum((s->>'tax')::numeric),sum((s->>'welfare')::numeric) into subtotal,tax_total,welfare_total from jsonb_array_elements(sites) s where s->>'customer_id'=customer.id::text;
  perform private.expense_cost_scope_lock(q.company_id,'customer',customer.id,q.work_month);
  perform e.id from private.expense_claims e join private.expense_settlement_choices sc on sc.claim_id=e.id and sc.company_id=e.company_id where e.company_id=q.company_id and e.incurred_on between q.work_month and (q.work_month+interval '1 month - 1 day')::date and e.allocation='customer' and e.counterparty_id=customer.id and sc.cost_allocation_current order by e.id for share of e,sc;
  expense:=private.expense_cost_components('invoice',q.company_id,customer.id,q.work_month,(q.work_month+interval '1 month - 1 day')::date,null);
  expenses:=(expense->>'amount_yen')::numeric;
  if expenses is null or expenses<0 or subtotal+tax_total+expenses>2147483647 then raise exception 'Invoice total unavailable or out of range' using errcode='22023';end if;
  quotes:=quotes||jsonb_build_array(jsonb_build_object('customer_id',customer.id,'customer_name',customer.name,'customer_address',coalesce(customer.billing_address,''),'sites',(select jsonb_agg(s order by s->>'site_id') from jsonb_array_elements(sites) s where s->>'customer_id'=customer.id::text),'subtotal',subtotal,'tax',tax_total,'welfare',welfare_total,'grand_total',subtotal+tax_total+expenses,'tax_rate_bps',p_tax_rate_bps,'expense_extra_amount_yen',expenses,'expense_extra_claims',expense->'claims','expense_extra_source_version',1));
 end loop;
 data:=jsonb_build_object('quote_id',q.id,'quote_fingerprint',fingerprint,'work_month',q.work_month,'site_terms',p_site_terms,'tax_rate_bps',p_tax_rate_bps,'quotes',quotes,'historical_base_subtotal',q.snapshot->'subtotal','people',q.snapshot->'people','man_days',q.snapshot->'man_days','status','draft');
 return data||jsonb_build_object('fingerprint',md5(data::text));
end $$;

create function private.create_line_historical_invoices(p_command_id uuid,p_quote_id uuid,p_quote_fingerprint text,p_site_terms jsonb,p_tax_rate_bps integer,p_terms_confirmed boolean,p_preview_fingerprint text,p_preview_confirmed boolean)
returns jsonb language plpgsql security definer set search_path='' as $$
declare q private.line_historical_quote_snapshots; receipt private.line_historical_invoice_commands; payload jsonb; preview jsonb; quote jsonb; iid uuid; results jsonb:='[]'; result jsonb; snapshot jsonb;
begin
 q:=private.require_line_historical_invoice_quote(p_quote_id);
 if p_command_id is null or p_preview_confirmed is distinct from true or nullif(p_preview_fingerprint,'') is null then raise exception 'Confirm the displayed draft preview' using errcode='22023';end if;
 payload:=jsonb_build_object('quote_id',p_quote_id,'quote_fingerprint',p_quote_fingerprint,'site_terms',p_site_terms,'tax_rate_bps',p_tax_rate_bps,'terms_confirmed',p_terms_confirmed,'preview_fingerprint',p_preview_fingerprint);
 perform pg_advisory_xact_lock(hashtextextended('line-historical-invoice-command:'||q.company_id::text||auth.uid()::text||p_command_id::text,0));
 select * into receipt from private.line_historical_invoice_commands where company_id=q.company_id and actor_id=auth.uid() and command_id=p_command_id;
 if found then if receipt.payload is distinct from payload then raise exception 'Command content changed' using errcode='22023';end if;return receipt.result;end if;
 perform 1 from private.line_historical_quote_snapshots where id=q.id for share;
 for quote in select value from jsonb_array_elements(p_site_terms) order by value->>'customer_id' loop
  if not pg_try_advisory_xact_lock(hashtextextended('invoice:'||q.company_id::text||(quote->>'customer_id')||q.work_month::text,0)) then raise exception 'Another invoice operation is active' using errcode='40001';end if;
 end loop;
 -- Keep the original invoice INSERT/UPDATE triggers enabled. The shared lock
 -- prevents every existing manual/automatic generator racing the overlap check.
 begin lock table public.invoices in share row exclusive mode nowait;
 exception when lock_not_available then raise exception 'Another invoice operation is active' using errcode='40001';end;
 preview:=private.line_historical_invoice_preview(p_quote_id,p_quote_fingerprint,p_site_terms,p_tax_rate_bps,p_terms_confirmed);
 if preview->>'fingerprint' is distinct from p_preview_fingerprint then raise exception 'Customer metadata or saved expenses changed; preview again' using errcode='40001';end if;
 if exists(select 1 from private.line_historical_invoice_commands c where c.company_id=q.company_id and c.group_id=q.group_id and c.work_month=q.work_month)
  or exists(select 1 from private.line_invoice_submissions s join private.line_import_drafts d on d.id=s.draft_id and d.company_id=s.company_id where s.company_id=q.company_id and d.group_id=q.group_id and s.work_month=q.work_month) then raise exception 'LINE month already converted; review existing invoices' using errcode='22023';end if;
 for quote in select value from jsonb_array_elements(preview->'quotes') loop
  if exists(select 1 from public.invoices i where i.company_id=q.company_id and i.customer_id=(quote->>'customer_id')::uuid and i.billing_period_start<=(q.work_month+interval '1 month - 1 day')::date and i.billing_period_end>=q.work_month)
   or exists(select 1 from private.line_invoice_submissions s where s.company_id=q.company_id and s.customer_id=(quote->>'customer_id')::uuid and s.work_month=q.work_month)
   or exists(select 1 from private.line_historical_invoice_links s where s.company_id=q.company_id and s.customer_id=(quote->>'customer_id')::uuid and s.work_month=q.work_month) then raise exception 'An invoice already exists for this customer and month' using errcode='22023';end if;
  snapshot:=quote-'customer_id'||jsonb_build_object('billing_period',to_char(q.work_month,'YYYY年MM月'),'detail_mode','consolidated_only','line_historical_quote_evidence',jsonb_build_object('quote_id',q.id,'source_fingerprint',q.source_fingerprint,'quote_fingerprint',p_quote_fingerprint,'draft_id',q.draft_id,'draft_revision',q.draft_revision,'rows',q.snapshot->'rows','source_messages',q.snapshot->'source_messages','input_rates',q.input_rates,'site_terms',p_site_terms,'tax_rate_bps',p_tax_rate_bps,'master_actor_id',auth.uid()));
  insert into public.invoices(company_id,customer_id,billing_period_start,billing_period_end,status,subtotal,tax,welfare_amount,adjustments,grand_total,snapshot,detail_mode,automatic_calculation)
  values(q.company_id,(quote->>'customer_id')::uuid,q.work_month,(q.work_month+interval '1 month - 1 day')::date,'draft',(quote->>'subtotal')::integer,(quote->>'tax')::integer,(quote->>'welfare')::integer,0,(quote->>'grand_total')::integer,snapshot,'consolidated_only',false) returning id into iid;
  results:=results||jsonb_build_array(jsonb_build_object('invoice_id',iid,'customer_id',quote->>'customer_id','customer_name',quote->>'customer_name','work_month',q.work_month,'grand_total',quote->'grand_total','invoice_exists',true,'status','draft'));
 end loop;
 result:=jsonb_build_object('invoices',results,'status','draft','issued',false,'approved',false);
 insert into private.line_historical_invoice_commands(company_id,actor_id,command_id,quote_id,group_id,work_month,payload,result) values(q.company_id,auth.uid(),p_command_id,q.id,q.group_id,q.work_month,payload,result);
 insert into private.line_historical_invoice_links(company_id,customer_id,work_month,quote_id,actor_id,command_id,invoice_id,invoice_fingerprint)
 select q.company_id,(r->>'customer_id')::uuid,q.work_month,q.id,auth.uid(),p_command_id,(r->>'invoice_id')::uuid,(select md5((to_jsonb(i)-'updated_at')::text) from public.invoices i where i.id=(r->>'invoice_id')::uuid) from jsonb_array_elements(results) r;
 return result;
end $$;

create function private.guard_line_invoice_after_historical_conversion() returns trigger
language plpgsql security definer set search_path='' as $$
declare gid uuid;
begin
 select group_id into gid from private.line_import_drafts where id=new.draft_id and company_id=new.company_id;
 if exists(select 1 from private.line_historical_invoice_commands c where c.company_id=new.company_id and c.group_id=gid and c.work_month=new.work_month) then
  raise exception 'Historical LINE month already converted; review existing invoices' using errcode='22023';end if;
 return new;
end $$;
revoke all on function private.guard_line_invoice_after_historical_conversion() from public,anon,authenticated,service_role;
create trigger line_invoice_after_historical_conversion before insert on private.line_invoice_submissions for each row execute function private.guard_line_invoice_after_historical_conversion();

create function public.line_historical_invoice_workspace(p_quote_id uuid) returns jsonb language sql stable security invoker set search_path='' as $$select private.line_historical_invoice_workspace(p_quote_id)$$;
create function public.line_historical_invoice_preview(p_quote_id uuid,p_quote_fingerprint text,p_site_terms jsonb,p_tax_rate_bps integer,p_terms_confirmed boolean) returns jsonb language sql security invoker set search_path='' as $$select private.line_historical_invoice_preview(p_quote_id,p_quote_fingerprint,p_site_terms,p_tax_rate_bps,p_terms_confirmed)$$;
create function public.create_line_historical_invoices(p_command_id uuid,p_quote_id uuid,p_quote_fingerprint text,p_site_terms jsonb,p_tax_rate_bps integer,p_terms_confirmed boolean,p_preview_fingerprint text,p_preview_confirmed boolean) returns jsonb language sql security invoker set search_path='' as $$select private.create_line_historical_invoices(p_command_id,p_quote_id,p_quote_fingerprint,p_site_terms,p_tax_rate_bps,p_terms_confirmed,p_preview_fingerprint,p_preview_confirmed)$$;
revoke all on function private.require_line_historical_invoice_quote(uuid) from public,anon,authenticated,service_role;
revoke all on function private.line_historical_invoice_workspace(uuid),private.line_historical_invoice_preview(uuid,text,jsonb,integer,boolean),private.create_line_historical_invoices(uuid,uuid,text,jsonb,integer,boolean,text,boolean),public.line_historical_invoice_workspace(uuid),public.line_historical_invoice_preview(uuid,text,jsonb,integer,boolean),public.create_line_historical_invoices(uuid,uuid,text,jsonb,integer,boolean,text,boolean) from public,anon;
grant execute on function private.line_historical_invoice_workspace(uuid),private.line_historical_invoice_preview(uuid,text,jsonb,integer,boolean),private.create_line_historical_invoices(uuid,uuid,text,jsonb,integer,boolean,text,boolean),public.line_historical_invoice_workspace(uuid),public.line_historical_invoice_preview(uuid,text,jsonb,integer,boolean),public.create_line_historical_invoices(uuid,uuid,text,jsonb,integer,boolean,text,boolean) to authenticated;
-- Refresh only bridge-owned, unchanged, unapproved drafts. Frozen source rows,
-- rates, tax/welfare, identity and seal evidence remain untouched.
create function private.line_historical_invoice_expenses(p_quote_id uuid,p_invoice_id uuid,p_preview_fingerprint text default null,p_confirmed boolean default false)
returns jsonb language plpgsql security definer set search_path='' as $$
declare q private.line_historical_quote_snapshots; link private.line_historical_invoice_links; invoice public.invoices;
 row_data jsonb; baseline text; component jsonb; data jsonb; fingerprint text; total numeric;
begin
 q:=private.require_line_historical_invoice_quote(p_quote_id);
 select * into link from private.line_historical_invoice_links where company_id=q.company_id and quote_id=q.id and invoice_id=p_invoice_id;
 if not found then raise exception 'Bridge invoice unavailable' using errcode='42501';end if;
 if not pg_try_advisory_xact_lock(hashtextextended('invoice:'||q.company_id::text||link.customer_id::text||link.work_month::text,0)) then raise exception 'Another invoice operation is active' using errcode='40001';end if;
 begin lock table public.invoices in share row exclusive mode nowait;
 exception when lock_not_available then raise exception 'Another invoice operation is active' using errcode='40001';end;
 begin perform 1 from public.companies where id=q.company_id for update nowait;
 exception when lock_not_available then raise exception 'Another approval operation is active' using errcode='40001';end;
 select * into link from private.line_historical_invoice_links where company_id=q.company_id and quote_id=q.id and invoice_id=p_invoice_id for update;
 select * into invoice from public.invoices where id=p_invoice_id and company_id=q.company_id for update;
 if not found then raise exception 'Bridge invoice unavailable' using errcode='42501';end if;
 row_data:=to_jsonb(invoice);
 baseline:=md5((row_data-'updated_at')::text);
 if invoice.status is distinct from 'draft' or invoice.finalized_at is not null or row_data->>'approval_finalized_at' is not null
  or exists(select 1 from public.invoice_approvals a where a.invoice_id=invoice.id and a.status='approved')
  or invoice.automatic_calculation is distinct from false or baseline is distinct from link.invoice_fingerprint then
  raise exception 'Invoice was edited or finalized; use its existing review screen' using errcode='22023';end if;
 if p_confirmed and p_preview_fingerprint=link.last_refresh_fingerprint then return link.refresh_result;end if;
 perform private.expense_cost_scope_lock(q.company_id,'customer',link.customer_id,link.work_month);
 perform e.id from private.expense_claims e join private.expense_settlement_choices sc on sc.claim_id=e.id and sc.company_id=e.company_id
 where e.company_id=q.company_id and e.incurred_on between invoice.billing_period_start and invoice.billing_period_end and e.allocation='customer' and e.counterparty_id=link.customer_id and sc.cost_allocation_current order by e.id for share of e,sc;
 component:=private.expense_cost_components('invoice',q.company_id,link.customer_id,invoice.billing_period_start,invoice.billing_period_end,invoice.id);
 total:=invoice.subtotal::numeric+invoice.tax::numeric+invoice.adjustments::numeric+(component->>'amount_yen')::numeric;
 if total is null or total<0 or total>2147483647 then raise exception 'Invoice total unavailable' using errcode='22023';end if;
 data:=jsonb_build_object('invoice_id',invoice.id,'quote_id',q.id,'customer_name',invoice.snapshot->>'customer_name','previous_expense_amount_yen',invoice.snapshot->'expense_extra_amount_yen','expense_extra_amount_yen',component->'amount_yen','expense_extra_claims',component->'claims','subtotal',invoice.subtotal,'tax',invoice.tax,'welfare',invoice.welfare_amount,'grand_total',total,'invoice_fingerprint',baseline);
 fingerprint:=md5(data::text);data:=data||jsonb_build_object('fingerprint',fingerprint);
 if not p_confirmed then return data;end if;
 if p_preview_fingerprint is distinct from fingerprint then raise exception 'Invoice or expenses changed; preview again' using errcode='40001';end if;
 update public.invoices set grand_total=total::integer,snapshot=invoice.snapshot||jsonb_build_object('grand_total',total,'expense_extra_amount_yen',component->'amount_yen','expense_extra_claims',component->'claims','expense_extra_source_version',1),updated_at=now() where id=invoice.id and company_id=q.company_id;
 select md5((to_jsonb(i)-'updated_at')::text) into baseline from public.invoices i where i.id=invoice.id;
 update private.line_historical_invoice_links set invoice_fingerprint=baseline,last_refresh_fingerprint=fingerprint,refresh_result=data where company_id=q.company_id and quote_id=q.id and invoice_id=invoice.id;
 return data;
end $$;
create function public.line_historical_invoice_expense_preview(p_quote_id uuid,p_invoice_id uuid) returns jsonb language sql security invoker set search_path='' as $$select private.line_historical_invoice_expenses(p_quote_id,p_invoice_id)$$;
create function public.refresh_line_historical_invoice_expenses(p_quote_id uuid,p_invoice_id uuid,p_preview_fingerprint text,p_confirmed boolean) returns jsonb language sql security invoker set search_path='' as $$select private.line_historical_invoice_expenses(p_quote_id,p_invoice_id,p_preview_fingerprint,p_confirmed)$$;
revoke all on function private.line_historical_invoice_expenses(uuid,uuid,text,boolean),public.line_historical_invoice_expense_preview(uuid,uuid),public.refresh_line_historical_invoice_expenses(uuid,uuid,text,boolean) from public,anon;
grant execute on function private.line_historical_invoice_expenses(uuid,uuid,text,boolean),public.line_historical_invoice_expense_preview(uuid,uuid),public.refresh_line_historical_invoice_expenses(uuid,uuid,text,boolean) to authenticated;

commit;
