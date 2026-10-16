-- REVIEW ONLY: receipt binder, not order dispatch/acceptance. Never applied here.
-- Existing functions/tables are not replaced or written. Invoice source only.
create schema site_contract_binding_private;
revoke all on schema site_contract_binding_private from public,anon,authenticated;
create table site_contract_binding_private.rollout (
 company_id uuid primary key references public.companies(id), enabled boolean not null default false);
create table site_contract_binding_private.bindings (
 company_id uuid not null, command_id uuid not null, item_id uuid not null,
 revision integer not null, actor_id uuid not null, request jsonb not null,
 snapshot jsonb not null, created_at timestamptz not null default now(),
 primary key(company_id,command_id), unique(item_id,revision));
alter table site_contract_binding_private.rollout enable row level security;
alter table site_contract_binding_private.bindings enable row level security;
revoke all on all tables in schema site_contract_binding_private from public,anon,authenticated;

-- The receipt is supplied explicitly; no lookup by time/name/count.
-- Caller must provide the entire preview document, compared byte-semantically
-- as jsonb after fresh source reads. No client-chosen price is saved.
create function site_contract_binding_private.preview(p_company uuid,p_item uuid,p_output text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare x record; conn record; f jsonb; pref record; terms jsonb; source jsonb;
 unit text; amount numeric; formula jsonb; seal jsonb; rev integer; site_snapshot jsonb;
begin
 if auth.uid() is null or not private.account_access_allowed() or not exists(
 select 1 from public.company_members m where m.company_id=p_company
 and m.user_id=auth.uid() and m.role::text in ('owner','admin')) then
 raise exception 'owner/admin required' using errcode='42501';end if;
 if p_output is distinct from 'invoice' then
 raise exception 'payment/payroll source adapter not implemented' using errcode='0A000';end if;
 select d.sender_company_id sender,d.recipient_company_id recipient,
 (i.payload->>'source_site_id')::uuid site,b.status,b.accepted_site_id,i.payload
 into x from private.company_data_delivery_items i
 join private.document_deliveries d on d.id=i.delivery_id
 join private.site_share_inbox b on b.data_item_id=i.id
 and b.recipient_company_id=d.recipient_company_id
 where i.id=p_item and i.payload_kind='site_share' and b.status in ('pending','accepted')
 for share of i,d,b;
 if x.sender is distinct from p_company or x.sender=x.recipient or x.site is null then
 raise exception 'exact sender receipt required' using errcode='42501';end if;
 -- New rollout only. No automatic enablement or public settings API.
 perform 1 from site_contract_binding_private.rollout where company_id in(x.sender,x.recipient)
 order by company_id for share;
 if (select count(*) from site_contract_binding_private.rollout where company_id in(x.sender,x.recipient) and enabled)<>2 then
 raise exception 'binding rollout off' using errcode='55000';end if;
 select c.parent_company_id parent,c.child_company_id child into conn
 from private.company_connections c where c.status='accepted' and
 ((c.parent_company_id=x.sender and c.child_company_id=x.recipient) or
 (c.parent_company_id=x.recipient and c.child_company_id=x.sender)) for share;
 if conn.parent is null then raise exception 'accepted company link required' using errcode='42501';end if;
 perform 1 from public.companies where id in(x.sender,x.recipient) order by id for share;
 if not exists(select 1 from public.sites where id=x.site and company_id=x.sender) or
 (x.status='accepted' and not exists(select 1 from public.sites where id=x.accepted_site_id and company_id=x.recipient)) then
 raise exception 'company/site mismatch' using errcode='42501';end if;
 select to_jsonb(s) into site_snapshot from public.sites s where s.id=x.site for share;
 select p.source,p.trade_company_id,p.selected_at into pref
 from public.site_calculation_source_preferences p
 where p.company_id=p_company and p.site_id=x.site and p.output_type='invoice' for share;
 if not found or pref.source not in ('site','trade_company') then
 raise exception 'explicit registered source required' using errcode='55000';end if;
 select jsonb_build_object('unit_price',z.billing_unit_price_yen,
 'monthly',z.billing_monthly_rate_yen,'square_price',z.billing_square_meter_unit_price_yen,
 'square_quantity',z.billing_square_meter_quantity,'contract',z.billing_contract_amount_yen,
 'formula',z.billing_rate_formula,'overrides',z.billing_rate_overrides)
 into f from public.site_financial_settings z where z.company_id=p_company and z.site_id=x.site for share;
 if f is null then raise exception 'site billing source missing' using errcode='55000';end if;
 formula:=f->'formula';
 if pref.source='trade_company' then
 select to_jsonb(c) into terms from public.trade_company_contracts c
 join public.trade_companies t on t.id=c.trade_company_id and t.company_id=c.company_id
 where c.company_id=p_company and c.trade_company_id=pref.trade_company_id
 and t.linked_company_id=x.recipient and t.trade_role in('customer','both')
 for share of c,t;
 if terms is null then raise exception 'selected company source mismatch' using errcode='42501';end if;
 unit:=case terms->>'contract_method' when 'daily' then 'day' when 'monthly' then 'month'
 when 'square_meter' then 'square_meter' when 'contract' then 'lump_sum' end;
 amount:=case unit when 'day' then (terms->>'daily_rate_yen')::numeric
 when 'month' then (terms->>'monthly_rate_yen')::numeric
 when 'square_meter' then (terms->>'square_meter_unit_price_yen')::numeric
 when 'lump_sum' then (terms->>'contract_amount_yen')::numeric end;
 else
 terms:=f;
 if (f->>'unit_price')::numeric>0 then
 if formula->>'base_mode'='hourly' and formula->>'hourly_base'='true' then unit:='hour';
 elsif formula->>'base_mode'='daily' and formula->>'hourly_base'='false' then unit:='day';
 else raise exception 'unit unknown/contradictory' using errcode='22023';end if;
 amount:=(f->>'unit_price')::numeric;
 elsif (f->>'monthly')::numeric>0 then unit:='month';amount:=(f->>'monthly')::numeric;
 elsif (f->>'square_price')::numeric>0 and (f->>'square_quantity')::numeric>0 then
 unit:='square_meter';amount:=(f->>'square_price')::numeric;
 elsif (f->>'contract')::numeric>0 then unit:='lump_sum';amount:=(f->>'contract')::numeric;
 end if;
 end if;
 if unit is null or amount is null or amount<=0 or amount::text in('NaN','Infinity','-Infinity') then
 raise exception 'registered unit/rate required' using errcode='22023';end if;
 if not exists(select 1 from public.companies where id=p_company and company_seal_enabled) then
 raise exception 'company seal disabled' using errcode='55000';end if;
 seal:=private.document_company_seal_snapshot(null,p_company,true)->'company_seal_snapshot';
 if seal is null or jsonb_typeof(seal)<>'object' or seal='{}' then raise exception 'seal missing' using errcode='55000';end if;
 select coalesce(max(revision),0) into rev from site_contract_binding_private.bindings where item_id=p_item;
 source:=jsonb_build_object('source',pref.source,'trade_company_id',pref.trade_company_id,
 'selected_at',pref.selected_at,'terms',terms,'site_formula',f);
 return jsonb_build_object('company_id',p_company,'actor_id',auth.uid(),'item_id',p_item,
 'sender_company_id',x.sender,'recipient_company_id',x.recipient,
 'parent_company_id',conn.parent,'child_company_id',conn.child,'source_site_id',x.site,
 'recipient_site_id',x.accepted_site_id,'receipt_status',x.status,'receipt_payload',x.payload,
 'output_type',p_output,'source',source,'source_site_snapshot',site_snapshot,'unit',unit,'unit_price_yen',amount,
 'company_tax_rate',(select tax_rate from public.companies where id=p_company),
 'seal_snapshot',seal,'expected_revision',rev);
end $$;
revoke all on function site_contract_binding_private.preview(uuid,uuid,text) from public,anon,authenticated;

create function site_contract_binding_private.bind(p_company uuid,p_item uuid,p_command uuid,
 p_expected_revision integer,p_preview jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare saved site_contract_binding_private.bindings; fresh jsonb; request jsonb;
begin
 -- This API is internal preparation only: not exposed/granted to client roles.
 if auth.uid() is null or not private.account_access_allowed() or not exists(
 select 1 from public.company_members where company_id=p_company and user_id=auth.uid()
 and role::text in('owner','admin')) then raise exception 'owner/admin required' using errcode='42501';end if;
 if p_command is null or p_expected_revision is null or p_expected_revision<0 or
 p_preview is null or jsonb_typeof(p_preview)<>'object' then
 raise exception 'command/revision required' using errcode='22023';end if;
 request:=jsonb_build_object('item',p_item,'revision',p_expected_revision,'preview',p_preview);
 perform pg_advisory_xact_lock(hashtextextended('site-contract-binding:'||p_company||':'||p_command,0));
 select * into saved from site_contract_binding_private.bindings
 where company_id=p_company and command_id=p_command;
 if found then
 if saved.actor_id<>auth.uid() or saved.request<>request then
 raise exception 'command reused for different request' using errcode='22023';end if;
 return saved.snapshot; -- Read-only recovery of the original result.
 end if;
 perform pg_advisory_xact_lock(hashtextextended('site-contract-binding-item:'||p_item,0));
 fresh:=site_contract_binding_private.preview(p_company,p_item,'invoice');
 -- Lock receipt then re-read all dependencies before storing; no old function mutation.
 perform 1 from private.site_share_inbox where data_item_id=p_item for share;
 fresh:=site_contract_binding_private.preview(p_company,p_item,'invoice');
 if (fresh->>'expected_revision')::integer<>p_expected_revision or fresh<>p_preview then
 raise exception 'preview/source changed' using errcode='40001';end if;
 insert into site_contract_binding_private.bindings(company_id,command_id,item_id,revision,actor_id,request,snapshot)
 values(p_company,p_command,p_item,p_expected_revision+1,auth.uid(),request,
 fresh||jsonb_build_object('binding_revision',p_expected_revision+1));
 select * into saved from site_contract_binding_private.bindings where company_id=p_company and command_id=p_command;
 return saved.snapshot;
end $$;
revoke all on function site_contract_binding_private.bind(uuid,uuid,uuid,integer,jsonb) from public,anon,authenticated;
-- No grants, notification, seal acceptance, rollout enablement, or migration.

