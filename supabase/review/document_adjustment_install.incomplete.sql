-- REVIEW CANDIDATE. CI, security/parallel and rendered PDF proof pending. NOT APPROVED FOR PRODUCTION.
begin;
do $check$ begin
if (select md5(prosrc) from pg_proc where oid=to_regprocedure('private.refresh_automatic_invoice(uuid,uuid,date)')) is distinct from '9173c4e7237b764ecb4c1e79bad85005' then raise exception 'Source drift: private.refresh_automatic_invoice(uuid,uuid,date)';end if;
if (select md5(prosrc) from pg_proc where oid=to_regprocedure('private.refresh_automatic_payment_certificate(uuid,uuid,date)')) is distinct from '5828ec68ad83ace5f0c0fc8f21851cf8' then raise exception 'Source drift: private.refresh_automatic_payment_certificate(uuid,uuid,date)';end if;
if (select md5(prosrc) from pg_proc where oid=to_regprocedure('private.certificate_calculation_rows(uuid,uuid,date,date)')) is distinct from '5b245861b26afe2ffb581be84f8dfa4c' then raise exception 'Source drift: private.certificate_calculation_rows(uuid,uuid,date,date)';end if;
if (select md5(prosrc) from pg_proc where oid=to_regprocedure('private.expense_payment_v2_guard()')) is distinct from '4d08bd0b372a3048b9eb52dd99a3c321' then raise exception 'Source drift: private.expense_payment_v2_guard()';end if;
if to_regclass('document_adjustment_private.rollout') is not null then raise exception 'Inspect existing installation; do not apply twice';end if;
end $check$;
-- REVIEW CANDIDATE ONLY. Not a deployment or completed registration API.
-- Source refresh integration and access-contract validation must pass before rollout.

create schema if not exists document_adjustment_private;
revoke all on schema document_adjustment_private from public, anon, authenticated, service_role;

create table document_adjustment_private.rollout (
 company_id uuid primary key references public.companies(id),
 enabled boolean not null default false,
 updated_at timestamptz not null default clock_timestamp()
);
create table document_adjustment_private.operation_events (
 id bigint generated always as identity primary key,
 company_id uuid not null references public.companies(id),
 actor_id uuid not null,session_id uuid not null,
 action text not null check(action in ('rollout_change','preview_cleanup')),
 reason text not null check(length(btrim(reason)) between 5 and 500),
 previous_enabled boolean,enabled boolean,details jsonb not null default '{}',
 created_at timestamptz not null default clock_timestamp()
);
create table document_adjustment_private.templates (
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null references public.companies(id),
 kind text not null check(kind in ('invoice','payment_certificate')),
 party_id uuid not null,
 recurrence text not null check(recurrence in ('once','monthly')),
 created_by uuid not null,
 created_at timestamptz not null default clock_timestamp()
);
create table document_adjustment_private.template_versions (
 template_id uuid not null references document_adjustment_private.templates(id),
 version bigint not null check(version>0),
 effective_month date not null check(extract(day from effective_month)=1),
 title text not null check(length(btrim(title)) between 1 and 120),
 sign text not null check(sign in ('plus','minus')),
 amount_yen bigint not null check(amount_yen between 1 and 2147483647),
 calculation_mode text not null check(calculation_mode in ('before_charges','settlement_yen')),
 site_id uuid,
 stopped boolean not null default false,
 actor_id uuid not null,
 created_at timestamptz not null default clock_timestamp(),
 primary key(template_id,version)
);
create table document_adjustment_private.scope_versions (
 company_id uuid not null references public.companies(id),
 kind text not null check(kind in ('invoice','payment_certificate')),
 party_id uuid not null,
 month date not null check(extract(day from month)=1),
 version bigint not null default 0 check(version>=0),
 primary key(company_id,kind,party_id,month)
);
create table document_adjustment_private.occurrences (
 id uuid primary key default gen_random_uuid(),
 template_id uuid not null references document_adjustment_private.templates(id),
 month date not null check(extract(day from month)=1),
 document_id uuid,
 template_version bigint not null,
 override jsonb,
 canceled boolean not null default false,
 finalized_snapshot jsonb,
 unique(template_id,month),
 foreign key(template_id,template_version) references document_adjustment_private.template_versions(template_id,version)
);
create table document_adjustment_private.commands (
 command_id uuid primary key,
 actor_id uuid not null,
 company_id uuid not null references public.companies(id),
 request jsonb not null,
 receipt jsonb not null,
 created_at timestamptz not null default clock_timestamp()
);
create table document_adjustment_private.audit (
 id bigint generated always as identity primary key,
 command_id uuid not null references document_adjustment_private.commands(command_id),
 actor_id uuid not null,
 company_id uuid not null,
 before_state jsonb,
 after_state jsonb not null,
 created_at timestamptz not null default clock_timestamp()
);
do $body$ declare n text; begin
 foreach n in array array['rollout','operation_events','templates','template_versions','scope_versions','occurrences','commands','audit'] loop
  execute format('alter table document_adjustment_private.%I enable row level security',n);
  execute format('revoke all on table document_adjustment_private.%I from public,anon,authenticated,service_role',n);
 end loop;
end $body$;
revoke all on all sequences in schema document_adjustment_private from public,anon,authenticated,service_role;

-- Every projection writer takes company -> rollout gate -> finance scope ->
-- document row. Exclusive OFF waits for all in-flight shared writers to commit;
-- a writer starting after OFF observes false before modifying its ledger.
create function document_adjustment_private.lock_rollout_gate(p_company uuid,p_exclusive boolean default false)
returns void language plpgsql security definer set search_path='' as $body$
begin
 perform 1 from public.companies where id=p_company for share;
 if not found then raise exception '会社情報を確認できません';end if;
 if p_exclusive then
  perform pg_advisory_xact_lock(hashtextextended('document-adjustment-rollout:'||p_company::text,0));
 else
  perform pg_advisory_xact_lock_shared(hashtextextended('document-adjustment-rollout:'||p_company::text,0));
 end if;
end $body$;
revoke all on function document_adjustment_private.lock_rollout_gate(uuid,boolean) from public,anon,authenticated,service_role;

-- Pure arithmetic only. Saved baseline and rates come from the real source,
-- never caller input. Applying a negative pre-charge entry recalculates the
-- original group's welfare/tax rounding; negating an independently rounded
-- positive calculation would be incorrect at half-yen boundaries.
create function document_adjustment_private.charge_delta(
 p_base bigint,p_delta bigint,p_welfare numeric,p_tax numeric
) returns jsonb language plpgsql immutable set search_path='' as $body$
declare old_w bigint;new_w bigint;old_t bigint;new_t bigint;
begin
 if p_base is null or p_delta is null or p_welfare is null or p_tax is null
    or p_welfare<0 or p_welfare>100 or p_tax<0 or p_tax>100 then
  raise exception '保存済みの計算設定を確認できません';
 end if;
 old_w:=round(p_base*p_welfare/100);new_w:=round((p_base+p_delta)*p_welfare/100);
 old_t:=round((p_base+old_w)*p_tax/100);new_t:=round((p_base+p_delta+new_w)*p_tax/100);
 return jsonb_build_object('base_delta_yen',p_delta,
  'welfare_delta_yen',new_w-old_w,'tax_delta_yen',new_t-old_t,
  'total_delta_yen',p_delta+new_w-old_w+new_t-old_t);
end $body$;
revoke all on function document_adjustment_private.charge_delta(bigint,bigint,numeric,numeric) from public,anon,authenticated,service_role;

create function document_adjustment_private.ledger_items(p_company uuid,p_kind text,p_party uuid,p_month date)
returns jsonb language sql stable security definer set search_path='' as $body$
 select coalesce(jsonb_agg(jsonb_build_object(
  'template_id',t.id,'template_version',v.version,'entry_id',o.id,
  'title',coalesce(o.override->>'title',v.title),
  'sign',coalesce(o.override->>'sign',v.sign),
  'amount_yen',coalesce((o.override->>'amount_yen')::bigint,v.amount_yen),
  'calculation_mode',coalesce(o.override->>'calculation_mode',v.calculation_mode),
  'site_id',coalesce(o.override->>'site_id',v.site_id::text),
  'recurrence',t.recurrence,'month',p_month
 ) order by t.created_at,t.id),'[]'::jsonb)
 from document_adjustment_private.templates t
 join lateral (
  select x.* from document_adjustment_private.template_versions x
  where x.template_id=t.id and x.effective_month<=p_month
   and (t.recurrence='monthly' or x.effective_month=p_month)
  order by x.effective_month desc,x.version desc limit 1
 ) v on not v.stopped
 left join document_adjustment_private.occurrences o on o.template_id=t.id and o.month=p_month
 where t.company_id=p_company and t.kind=p_kind and t.party_id=p_party
  and not coalesce(o.canceled,false)
$body$;
revoke all on function document_adjustment_private.ledger_items(uuid,text,uuid,date) from public,anon,authenticated,service_role;
create function document_adjustment_private.active_items(p_company uuid,p_kind text,p_party uuid,p_month date)
returns jsonb language sql stable security definer set search_path='' as $body$
 select case when exists(select 1 from document_adjustment_private.rollout where company_id=p_company and enabled)
 then document_adjustment_private.ledger_items(p_company,p_kind,p_party,p_month) else '[]'::jsonb end
$body$;
revoke all on function document_adjustment_private.active_items(uuid,text,uuid,date) from public,anon,authenticated,service_role;

create function document_adjustment_private.ensure_occurrences(p_company uuid,p_kind text,p_party uuid,p_month date)
returns void language plpgsql security definer set search_path='' as $body$
begin
 insert into document_adjustment_private.occurrences(template_id,month,template_version)
 select (x->>'template_id')::uuid,p_month,(x->>'template_version')::bigint
 from jsonb_array_elements(document_adjustment_private.active_items(p_company,p_kind,p_party,p_month)) x
 on conflict(template_id,month) do update set template_version=excluded.template_version
 where document_adjustment_private.occurrences.override is null
   and document_adjustment_private.occurrences.finalized_snapshot is null;
end $body$;
revoke all on function document_adjustment_private.ensure_occurrences(uuid,text,uuid,date) from public,anon,authenticated,service_role;

create function document_adjustment_private.bind_occurrences(p_company uuid,p_kind text,p_party uuid,p_month date,p_document uuid)
returns void language plpgsql security definer set search_path='' as $body$
begin
 if p_document is null then return;end if;
 update document_adjustment_private.occurrences o set document_id=p_document
 from document_adjustment_private.templates t where t.id=o.template_id and t.company_id=p_company
  and t.kind=p_kind and t.party_id=p_party and o.month=p_month and o.document_id is null;
end $body$;
revoke all on function document_adjustment_private.bind_occurrences(uuid,text,uuid,date,uuid) from public,anon,authenticated,service_role;

create function document_adjustment_private.append_only() returns trigger
language plpgsql set search_path='' as $body$ begin raise exception '監査・操作履歴は変更できません';end $body$;
revoke all on function document_adjustment_private.append_only() from public,anon,authenticated,service_role;
create trigger audit_append_only before update or delete on document_adjustment_private.audit
 for each row execute function document_adjustment_private.append_only();
create trigger commands_append_only before update or delete on document_adjustment_private.commands
 for each row execute function document_adjustment_private.append_only();
create trigger template_versions_append_only before update or delete on document_adjustment_private.template_versions
 for each row execute function document_adjustment_private.append_only();
create trigger operation_events_append_only before update or delete on document_adjustment_private.operation_events
 for each row execute function document_adjustment_private.append_only();
create index operation_events_company_time on document_adjustment_private.operation_events(company_id,id desc);
create index adjustment_templates_scope on document_adjustment_private.templates(company_id,kind,party_id);
create index adjustment_occurrences_document on document_adjustment_private.occurrences(document_id);
create index adjustment_commands_preview on document_adjustment_private.commands((receipt->>'preview_token'));

create function document_adjustment_private.capture_finalized() returns trigger
language plpgsql security definer set search_path='' as $body$
declare d jsonb:=to_jsonb(new);k text;
begin
 k:=case tg_table_name when 'invoices' then 'invoice' else 'payment_certificate' end;
 if d->>'status'<>'draft' or d->>'finalized_at' is not null or d->>'approval_finalized_at' is not null then
  update document_adjustment_private.occurrences o set finalized_snapshot=d->'snapshot'
   from document_adjustment_private.templates t where t.id=o.template_id and t.kind=k
    and t.company_id=(d->>'company_id')::uuid and o.document_id=(d->>'id')::uuid
    and o.finalized_snapshot is null;
 end if;
 return new;
end $body$;
revoke all on function document_adjustment_private.capture_finalized() from public,anon,authenticated,service_role;
create trigger document_adjustments_finalize_invoice after update on public.invoices
 for each row execute function document_adjustment_private.capture_finalized();
create trigger document_adjustments_finalize_certificate after update on public.payment_certificates
 for each row execute function document_adjustment_private.capture_finalized();

-- Preview evaluates changes against a freshly refreshed source snapshot.
-- It does not mutate saved totals or accept client-supplied rates.
create function document_adjustment_private.preview_delta(
 p_kind text,p_snapshot jsonb,p_old jsonb,p_new jsonb
) returns jsonb language plpgsql immutable set search_path='' as $body$
declare s jsonb;g jsonb;old_amount bigint;new_amount bigint;base bigint;
 w numeric;t numeric;delta_base bigint:=0;delta_w bigint:=0;delta_t bigint:=0;
 final_old bigint;final_new bigint;d jsonb;site text;
begin
 if jsonb_typeof(p_old)<>'array' or jsonb_typeof(p_new)<>'array' then
  raise exception '調整明細を確認できません';end if;
 if p_kind='invoice' then
  for site in select distinct x->>'site_id' from jsonb_array_elements(p_old||p_new) x
    where x->>'calculation_mode'='before_charges'
  loop
   select x into s from jsonb_array_elements(p_snapshot->'sites') x where x->>'site_id'=site;
   if s is null then raise exception '計算対象の現場を確認できません';end if;
   select coalesce(sum((x->>'amount')::bigint),0) into old_amount
    from jsonb_array_elements(s->'lines') x where x->>'work_content'='（法定福利費）';
   base:=(s->>'subtotal')::bigint-old_amount;
   w:=(s->>'welfare_rate_bps')::numeric/100;t:=(p_snapshot->>'tax_rate_bps')::numeric/100;
   select coalesce(sum((x->>'amount_yen')::bigint*case when x->>'sign'='minus' then -1 else 1 end),0)
    into old_amount from jsonb_array_elements(p_old) x where x->>'site_id'=site and x->>'calculation_mode'='before_charges';
   select coalesce(sum((x->>'amount_yen')::bigint*case when x->>'sign'='minus' then -1 else 1 end),0)
    into new_amount from jsonb_array_elements(p_new) x where x->>'site_id'=site and x->>'calculation_mode'='before_charges';
   d:=document_adjustment_private.charge_delta(base,new_amount-old_amount,w,t);
   delta_base:=delta_base+(d->>'base_delta_yen')::bigint;
   delta_w:=delta_w+(d->>'welfare_delta_yen')::bigint;
   delta_t:=delta_t+(d->>'tax_delta_yen')::bigint;
  end loop;
 elsif p_kind='payment_certificate' then
  select coalesce(sum((x->>'amount_yen')::bigint),0) into base
   from jsonb_array_elements(p_snapshot->'calculation_rows') x
   where x->>'work_content' not in ('福利厚生費','消費税');
  w:=(p_snapshot->>'welfare_rate')::numeric;t:=(p_snapshot->>'tax_rate')::numeric;
  select coalesce(sum((x->>'amount_yen')::bigint*case when x->>'sign'='minus' then -1 else 1 end),0)
   into old_amount from jsonb_array_elements(p_old) x where x->>'calculation_mode'='before_charges';
  select coalesce(sum((x->>'amount_yen')::bigint*case when x->>'sign'='minus' then -1 else 1 end),0)
   into new_amount from jsonb_array_elements(p_new) x where x->>'calculation_mode'='before_charges';
  d:=document_adjustment_private.charge_delta(base,new_amount-old_amount,w,t);
  delta_base:=(d->>'base_delta_yen')::bigint;delta_w:=(d->>'welfare_delta_yen')::bigint;delta_t:=(d->>'tax_delta_yen')::bigint;
 else raise exception '帳票区分を確認できません';end if;
 select coalesce(sum((x->>'amount_yen')::bigint*case when x->>'sign'='minus' then -1 else 1 end),0)
  into final_old from jsonb_array_elements(p_old) x where x->>'calculation_mode'='settlement_yen';
 select coalesce(sum((x->>'amount_yen')::bigint*case when x->>'sign'='minus' then -1 else 1 end),0)
  into final_new from jsonb_array_elements(p_new) x where x->>'calculation_mode'='settlement_yen';
 return jsonb_build_object('base_delta_yen',delta_base,'welfare_delta_yen',delta_w,
  'tax_delta_yen',delta_t,'settlement_delta_yen',final_new-final_old,
  'total_delta_yen',delta_base+delta_w+delta_t+final_new-final_old);
end $body$;
revoke all on function document_adjustment_private.preview_delta(text,jsonb,jsonb,jsonb) from public,anon,authenticated,service_role;

-- INCOMPLETE REVIEW ONLY. NOT DEPLOYABLE.
CREATE OR REPLACE FUNCTION private.refresh_automatic_invoice(cid uuid, customer uuid, day date)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  named_items jsonb; named_item jsonb; named_final numeric:=0;
  expense_component jsonb; expense_amount numeric:=0;
  first_day date:=date_trunc('month',day)::date;
  last_day date:=(date_trunc('month',day)+interval '1 month - 1 day')::date;
  existing public.invoices%rowtype;
  s record;
  pref record;
  allowance_cfg record;
  rate_group record;
  category_kind text;
  category_label text;
  category_rate numeric;
  overtime_rate numeric;
  early_rate numeric;
  sites_json jsonb:='[]'::jsonb;
  lines jsonb;
  customer_name text;
  snapshot_value jsonb;
  v_system_customer boolean:=false;
  v_tax_rate numeric:=0;
  day_days numeric:=0;
  night_days numeric:=0;
  day_overtime numeric:=0;
  night_overtime numeric:=0;
  day_early numeric:=0;
  night_early numeric:=0;
  unit_rate numeric:=0;
  billing_method text;
  fixed_quantity numeric;
  fixed_unit_price numeric;
  effective_overrides jsonb;
  night_rate numeric:=0;
  method_label text:='';
  qty numeric;
  allowance_count numeric;
  allowance_rate numeric;
  early_amount numeric;
  a numeric;
  b numeric;
  c numeric;
  d numeric;
  site_tax numeric;
  set_pre_tax numeric;
  site_pre_tax numeric;
  site_tax_total numeric;
  total_pre_tax numeric:=0;
  total_tax numeric:=0;
  total_welfare numeric:=0;
  n integer:=0;
  route_parts jsonb; route_blocked boolean:=false;
begin
  if auth.uid() is null then return; end if;
  perform document_adjustment_private.lock_rollout_gate(cid);

  if customer is null then
    customer:=private.ensure_unassigned_invoice_customer(cid);
    v_system_customer:=true;
  else
    select c.notes='sko_system_unassigned_invoice_customer'
    into v_system_customer
    from public.customers c
    where c.id=customer and c.company_id=cid;
    v_system_customer:=coalesce(v_system_customer,false);
  end if;

  if customer is null then return; end if;
  perform pg_advisory_xact_lock(
    hashtextextended('invoice:'||cid::text||customer::text||first_day::text,0)
  );

  select * into existing
  from public.invoices
  where company_id=cid
    and customer_id=customer
    and billing_period_start=first_day
    and automatic_calculation
  for update;

  if found and (existing.status<>'draft' or existing.finalized_at is not null or existing.approval_finalized_at is not null or coalesce(existing.invoice_seal_frozen,false) or exists(select 1 from public.invoice_approvals ia where ia.invoice_id=existing.id and ia.status='approved')) then
    return;
  end if;
  if existing.id is null and exists(
    select 1 from public.invoices
    where company_id=cid
      and customer_id=customer
      and billing_period_start=first_day
  ) then return; end if;

  if existing.snapshot?'document_adjustments_v1' and not exists(
    select 1 from document_adjustment_private.rollout r where r.company_id=cid and r.enabled
  ) then return;end if;
  perform document_adjustment_private.ensure_occurrences(cid,'invoice',customer,first_day);
  named_items:=document_adjustment_private.active_items(cid,'invoice',customer,first_day);
  select name into customer_name
  from public.customers
  where id=customer and company_id=cid;
  if customer_name is null then return; end if;

  select greatest(coalesce(c.tax_rate,0),0)
  into v_tax_rate
  from public.companies c
  where c.id=cid;

  for s in
    select
      st.id,
      coalesce(nullif(st.formal_name,''),st.name) as name,
      coalesce(fs.billing_unit_price_yen,0) as billing_unit_price_yen,
      coalesce(fs.billing_monthly_rate_yen,0) as billing_monthly_rate_yen,
      coalesce(fs.billing_square_meter_unit_price_yen,0) as billing_square_meter_unit_price_yen,
      coalesce(fs.billing_square_meter_quantity,0) as billing_square_meter_quantity,
      coalesce(fs.billing_contract_amount_yen,0) as billing_contract_amount_yen,
      coalesce(fs.billing_overtime_hour_rate_yen,0) as billing_overtime_hour_rate_yen,
      coalesce(fs.billing_early_hour_rate_yen,0) as billing_early_hour_rate_yen,
      coalesce(fs.billing_rate_formula,'{}'::jsonb) as billing_rate_formula,
      coalesce(fs.billing_rate_overrides,'{}'::jsonb) as billing_rate_overrides,
      case when fs.welfare_rate between 0 and 100 then fs.welfare_rate else 0 end as welfare_rate,
      nullif(trim(coalesce(fs.billing_allowance_1_name,'')),'') as allowance_1_name,
      coalesce(fs.billing_allowance_1_amount_yen,0) as allowance_1_amount,
      nullif(trim(coalesce(fs.billing_allowance_2_name,'')),'') as allowance_2_name,
      coalesce(fs.billing_allowance_2_amount_yen,0) as allowance_2_amount,
      nullif(trim(coalesce(fs.billing_allowance_3_name,'')),'') as allowance_3_name,
      coalesce(fs.billing_allowance_3_amount_yen,0) as allowance_3_amount
    from public.sites st
    left join public.site_financial_settings fs
      on fs.site_id=st.id and fs.company_id=cid
    where st.company_id=cid
      and (
        (v_system_customer and st.customer_id is null)
        or (not v_system_customer and st.customer_id=customer)
      )
      and (exists(
        select 1
        from public.attendance_entries e
        where e.site_id=st.id
          and e.company_id=cid
          and e.work_date between first_day and last_day
      ) or exists(select 1 from jsonb_array_elements(named_items) x where x->>'calculation_mode'='before_charges' and x->>'site_id'=st.id::text))
    order by st.created_at, st.id
  loop
    n:=n+1;
    lines:='[]'::jsonb;
    site_pre_tax:=0;
    site_tax_total:=0;

    select
      coalesce(sum(case when e.work_category in ('day','holiday') then coalesce(e.base_man_days,0) else 0 end),0),
      coalesce(sum(case when e.work_category in ('night','holiday_night') then coalesce(e.base_man_days,0) else 0 end),0),
      coalesce(sum(case when e.work_category in ('day','holiday') then coalesce(e.overtime_hours,0) else 0 end),0),
      coalesce(sum(case when e.work_category in ('night','holiday_night') then coalesce(e.overtime_hours,0) else 0 end),0),
      coalesce(sum(case when e.work_category in ('day','holiday') then coalesce(e.early_hours,0) else 0 end),0),
      coalesce(sum(case when e.work_category in ('night','holiday_night') then coalesce(e.early_hours,0) else 0 end),0)
    into day_days,night_days,day_overtime,night_overtime,day_early,night_early
    from public.attendance_entries e
    where e.company_id=cid
      and e.site_id=s.id
      and e.work_date between first_day and last_day;

    pref:=null;
    select
      scsp.source,
      coalesce(ct.contract_method,'none') as contract_method,
      coalesce(ct.daily_rate_yen,0) as daily_rate_yen,
      coalesce(ct.monthly_rate_yen,0) as monthly_rate_yen,
      coalesce(ct.square_meter_unit_price_yen,0) as square_meter_unit_price_yen,
      coalesce(ct.square_meter_quantity,0) as square_meter_quantity,
      coalesce(ct.contract_amount_yen,0) as contract_amount_yen
    into pref
    from public.site_calculation_source_preferences scsp
    join public.trade_companies tc
      on tc.id=scsp.trade_company_id and tc.company_id=cid
    left join public.trade_company_contracts ct
      on ct.company_id=cid and ct.trade_company_id=tc.id
    where scsp.company_id=cid
      and scsp.site_id=s.id
      and scsp.output_type='invoice'
      and scsp.source='trade_company'
    limit 1;

    billing_method:='daily';
    fixed_quantity:=1;
    fixed_unit_price:=0;
    if pref.source='trade_company' then
      if pref.contract_method='daily' then
        unit_rate:=pref.daily_rate_yen;
        method_label:=unit_rate::int::text;
      elsif pref.contract_method='monthly' then
        billing_method:='monthly';
        unit_rate:=pref.monthly_rate_yen;
        method_label:=unit_rate::int::text;
      elsif pref.contract_method='square_meter' then
        billing_method:='square_meter';
        fixed_quantity:=pref.square_meter_quantity;
        fixed_unit_price:=pref.square_meter_unit_price_yen;
        unit_rate:=round(pref.square_meter_unit_price_yen*pref.square_meter_quantity);
        method_label:=pref.square_meter_unit_price_yen::int::text||'×'||pref.square_meter_quantity::text;
      elsif pref.contract_method='contract' then
        billing_method:='contract';
        unit_rate:=pref.contract_amount_yen;
        method_label:=unit_rate::int::text;
      else
        unit_rate:=0;
        method_label:='未設定';
      end if;
    elsif s.billing_unit_price_yen>0 then
      unit_rate:=s.billing_unit_price_yen;
      method_label:=unit_rate::int::text;
    elsif s.billing_monthly_rate_yen>0 then
      billing_method:='monthly';
      unit_rate:=s.billing_monthly_rate_yen;
      method_label:=unit_rate::int::text;
    elsif s.billing_square_meter_unit_price_yen>0 and s.billing_square_meter_quantity>0 then
      billing_method:='square_meter';
      fixed_quantity:=s.billing_square_meter_quantity;
      fixed_unit_price:=s.billing_square_meter_unit_price_yen;
      unit_rate:=round(s.billing_square_meter_unit_price_yen*s.billing_square_meter_quantity);
      method_label:=s.billing_square_meter_unit_price_yen::int::text||'×'||s.billing_square_meter_quantity::text;
    elsif s.billing_contract_amount_yen>0 then
      billing_method:='contract';
      unit_rate:=s.billing_contract_amount_yen;
      method_label:=unit_rate::int::text;
    else
      unit_rate:=0;
      method_label:='未設定';
    end if;

    -- Existing registered month/area/contract fields describe one fixed
    -- site-month charge, not an attendance-day unit price.
    if billing_method<>'daily' and unit_rate>0 then
      site_pre_tax:=unit_rate;
      lines:=lines||jsonb_build_array(jsonb_build_object(
        'site_label',s.name,
        'work_content',case billing_method when 'monthly' then '月単価'
          when 'square_meter' then '平米' else '請負金額' end,
        'quantity',fixed_quantity,
        'unit_price',case when billing_method='square_meter' then fixed_unit_price else unit_rate end,
        'unit_price_text',case when billing_method='square_meter' then fixed_unit_price::text else unit_rate::text end,
        'amount',unit_rate
      ));
    end if;
    -- Positive JSON overrides win; retained legacy direct amounts are next.
    -- Zero JSON values mean automatic calculation in the existing editor.
    effective_overrides:=s.billing_rate_overrides;
    if coalesce((effective_overrides->>'overtime')::numeric,0)<=0
       and s.billing_overtime_hour_rate_yen>0 then
      effective_overrides:=jsonb_set(effective_overrides,'{overtime}',to_jsonb(s.billing_overtime_hour_rate_yen),true);
    end if;
    if coalesce((effective_overrides->>'early')::numeric,0)<=0
       and s.billing_early_hour_rate_yen>0 then
      effective_overrides:=jsonb_set(effective_overrides,'{early}',to_jsonb(s.billing_early_hour_rate_yen),true);
    end if;

    -- Common rate-formula calculation. Day-rate and hourly-base modes use
    -- the same multipliers. A positive override wins over auto calculation.
    for rate_group in
      select
        coalesce(e.work_category,'day') as category,
        coalesce(sum(e.base_man_days),0) as days,
        coalesce(sum(e.overtime_hours),0) as overtime_hours,
        coalesce(sum(e.early_hours),0) as early_hours
      from public.attendance_entries e
      where e.company_id=cid
        and e.site_id=s.id
        and e.work_date between first_day and last_day
      group by coalesce(e.work_category,'day')
      order by coalesce(e.work_category,'day')
    loop
      category_kind:=case rate_group.category
        when 'night' then 'night'
        when 'holiday' then 'holiday'
        when 'holiday_night' then 'holiday_night'
        else 'daily'
      end;
      category_label:=case rate_group.category
        when 'night' then '夜勤'
        when 'holiday' then '休日出勤'
        when 'holiday_night' then '休日夜勤'
        else ''
      end;

      category_rate:=private.resolve_rate_formula(
        unit_rate,s.billing_rate_formula,effective_overrides,category_kind
      );
      overtime_rate:=private.resolve_rate_formula(
        unit_rate,s.billing_rate_formula,effective_overrides,
        case rate_group.category
          when 'night' then 'night_overtime'
          when 'holiday' then 'holiday_overtime'
          when 'holiday_night' then 'holiday_night_overtime'
          else 'overtime'
        end
      );
      early_rate:=case
        when coalesce((effective_overrides->>'early')::numeric,0)>0 then round((effective_overrides->>'early')::numeric)
        when rate_group.category='day' then private.resolve_rate_formula(
          unit_rate,s.billing_rate_formula,effective_overrides,'early'
        )
        else round(
          category_rate
          / greatest(coalesce((s.billing_rate_formula->>'hours_per_day')::numeric,8),0.01)
          * coalesce((s.billing_rate_formula->>'early_multiplier')::numeric,1.25)
        )
      end;

      if billing_method='daily' and rate_group.days>0 then
        a:=round(rate_group.days*category_rate);
        site_pre_tax:=site_pre_tax+a;
        lines:=lines||jsonb_build_array(jsonb_build_object(
          'site_label',case when jsonb_array_length(lines)=0 then s.name else '〃' end,
          'work_content',category_label,
          'quantity',rate_group.days,
          'unit_price',category_rate,
          'unit_price_text',category_rate::int::text,
          'formula',private.rate_formula_label(
            s.billing_rate_formula,category_kind
          ),
          'amount',a
        ));
      end if;

      if rate_group.early_hours>0 then
        a:=round(rate_group.early_hours*early_rate);
        site_pre_tax:=site_pre_tax+a;
        lines:=lines||jsonb_build_array(jsonb_build_object(
          'site_label','〃',
          'work_content',case
            when category_label='' then '（早出）'
            else '（'||category_label||'早出）'
          end,
          'quantity',rate_group.early_hours,
          'unit_price',early_rate,
          'unit_price_text',early_rate::int::text,
          'formula',private.rate_formula_label(
            s.billing_rate_formula,case rate_group.category
              when 'night' then 'night_early' when 'holiday' then 'holiday_early'
              when 'holiday_night' then 'holiday_night_early' else 'early' end
          ),
          'amount',a
        ));
      end if;

      if rate_group.overtime_hours>0 then
        a:=round(rate_group.overtime_hours*overtime_rate);
        site_pre_tax:=site_pre_tax+a;
        lines:=lines||jsonb_build_array(jsonb_build_object(
          'site_label','〃',
          'work_content',case
            when category_label='' then '（残業）'
            else '（'||category_label||'残業）'
          end,
          'quantity',rate_group.overtime_hours,
          'unit_price',overtime_rate,
          'unit_price_text',overtime_rate::int::text,
          'formula',private.rate_formula_label(
            s.billing_rate_formula,
            case rate_group.category
              when 'night' then 'night_overtime'
              when 'holiday' then 'holiday_overtime'
              when 'holiday_night' then 'holiday_night_overtime'
              else 'overtime'
            end
          ),
          'amount',a
        ));
      end if;
    end loop;

    -- Named allowances are calculated once per site/month.
    for allowance_cfg in
      select allowance_name as name,count(*)::numeric as qty
      from public.attendance_entries e,
           unnest(coalesce(e.allowance_names,'{}'::text[])) allowance_name
      where e.company_id=cid
        and e.site_id=s.id
        and e.work_date between first_day and last_day
        and nullif(trim(allowance_name),'') is not null
      group by allowance_name
      order by allowance_name
    loop
      allowance_count:=allowance_cfg.qty;
      allowance_rate:=case
        when allowance_cfg.name=s.allowance_1_name then s.allowance_1_amount
        when allowance_cfg.name=s.allowance_2_name then s.allowance_2_amount
        when allowance_cfg.name=s.allowance_3_name then s.allowance_3_amount
        else 0
      end;
      if allowance_rate>0 then
        a:=round(allowance_count*allowance_rate);
        site_pre_tax:=site_pre_tax+a;
        lines:=lines||jsonb_build_array(jsonb_build_object(
          'site_label','〃',
          'work_content','（'||allowance_cfg.name||'）',
          'quantity',allowance_count,
          'unit_price',allowance_rate,
          'unit_price_text',allowance_rate::int::text,
          'amount',a,
          'allowance_name',allowance_cfg.name
        ));
      end if;
    end loop;

    for named_item in select value from jsonb_array_elements(
      document_adjustment_private.active_items(cid,'invoice',customer,first_day))
      where value->>'calculation_mode'='before_charges' and value->>'site_id'=s.id::text
    loop
      a:=(named_item->>'amount_yen')::numeric * case when named_item->>'sign'='minus' then -1 else 1 end;
      site_pre_tax:=site_pre_tax+a;
      lines:=lines||jsonb_build_array(jsonb_build_object('site_label','〃',
        'work_content',named_item->>'title','quantity',1,'unit_price',a,
        'unit_price_text',a::text,'amount',a,'document_adjustment',named_item));
    end loop;
    d:=round(site_pre_tax*s.welfare_rate/100);
    if d>0 then
      lines:=lines||jsonb_build_array(jsonb_build_object(
        'site_label','〃','work_content','（法定福利費）',
        'quantity',0,'unit_price',0,'unit_price_text','',
        'amount',d
      ));
    end if;
    site_pre_tax:=site_pre_tax+d;
    total_welfare:=total_welfare+d;

    site_tax:=round(site_pre_tax*v_tax_rate/100);
    if site_tax>0 then
      lines:=lines||jsonb_build_array(jsonb_build_object(
        'site_label','〃','work_content','（消費税）',
        'quantity',0,'unit_price',0,
        'unit_price_text',trim(trailing '.' from trim(trailing '0' from to_char(v_tax_rate,'FM999999990.999999999')))||'%',
        'amount',site_tax
      ));
    end if;
    site_tax_total:=site_tax;
    total_pre_tax:=total_pre_tax+site_pre_tax;
    total_tax:=total_tax+site_tax_total;

    sites_json:=sites_json||jsonb_build_array(jsonb_build_object(
      'site_id',s.id,
      'site_name',s.name,
      'manual_adjustment',0,
      'welfare_rate_bps',s.welfare_rate*100,
      'subtotal',site_pre_tax,
      'tax',site_tax_total,
      'grand_total',site_pre_tax+site_tax_total,
      'lines',lines
    ));
  end loop;

  route_parts:=private.route_billing_invoice_components(cid,customer,first_day,last_day);
  route_blocked:=(route_parts->>'blocked')::boolean;
  sites_json:=sites_json||(route_parts->'sites');
  total_pre_tax:=total_pre_tax+(route_parts->>'subtotal')::numeric;
  total_tax:=total_tax+(route_parts->>'tax')::numeric;
  total_welfare:=total_welfare+(route_parts->>'welfare')::numeric;
  if (route_parts->>'has_requests')::boolean or route_blocked then n:=n+1;end if;
  
 expense_component:=private.expense_cost_components('invoice',cid,customer,first_day,last_day,existing.id);
 expense_amount:=(expense_component->>'amount_yen')::numeric;
  if n=0 and expense_amount=0 and jsonb_array_length(named_items)=0 and not coalesce(existing.snapshot?'document_adjustments_v1',false) and existing.id is not null and existing.snapshot?'expense_extra_source_version' then
  update public.invoices set subtotal=0,tax=0,welfare_amount=0,grand_total=0,
   snapshot=existing.snapshot||jsonb_build_object('sites','[]'::jsonb,'subtotal',0,'tax',0,'grand_total',0,
    'route_quantity_pending',false,'route_source_pending',route_blocked,
    'route_signed_checkout_version',1,'expense_extra_amount_yen',0,'expense_extra_claims','[]'::jsonb),
   calculation_blocked=route_blocked,updated_at=now() where id=existing.id;
  return;
 end if;
 if n=0 and expense_amount=0 and jsonb_array_length(named_items)=0 and not coalesce(existing.snapshot?'document_adjustments_v1',false) then
 
    if existing.id is not null
       and existing.status='draft'
       and existing.automatic_calculation then
      delete from public.invoices where id=existing.id;
    end if;
    return;
  end if;

  named_items:=document_adjustment_private.active_items(cid,'invoice',customer,first_day);
  select coalesce(sum((x->>'amount_yen')::numeric * case when x->>'sign'='minus' then -1 else 1 end),0)
  into named_final from jsonb_array_elements(named_items) x where x->>'calculation_mode'='settlement_yen';
  snapshot_value:=jsonb_build_object(
    'customer_name',customer_name,
    'customer_missing',v_system_customer,
    'billing_period',extract(year from first_day)::text||'年'||extract(month from first_day)::text||'月',
    'tax_rate_bps',v_tax_rate*100,
    'subtotal',total_pre_tax,
    'tax',total_tax,
    'grand_total',total_pre_tax+total_tax+expense_amount+named_final,
    'sites',sites_json
  );

  if jsonb_array_length(named_items)>0 or coalesce(existing.snapshot?'document_adjustments_v1',false) then
  snapshot_value:=snapshot_value||jsonb_build_object('document_adjustments_v1',named_items,'document_final_adjustment_yen',named_final);
  end if;
  snapshot_value:=snapshot_value||jsonb_build_object('route_quantity_pending',false,
  'route_source_pending',route_blocked,'route_signed_checkout_version',1,
  'route_source_issues',route_parts->'source_issues');
  
 if coalesce((expense_component->>'has_choices')::boolean,false) or existing.snapshot?'expense_extra_source_version' then
  snapshot_value:=snapshot_value||jsonb_build_object('expense_extra_amount_yen',expense_amount,
   'expense_extra_claims',expense_component->'claims','expense_extra_source_version',1);
 end if;
 snapshot_value:=snapshot_value||private.document_company_seal_snapshot
 (existing.snapshot,cid,existing.id is null);
  if existing.id is null then
    insert into public.invoices(
      company_id,customer_id,billing_period_start,billing_period_end,status,
      subtotal,tax,welfare_amount,grand_total,snapshot,
      automatic_calculation,calculation_blocked
    )
    values(
      cid,customer,first_day,last_day,'draft',
      total_pre_tax::int,total_tax::int,total_welfare::int,
      (total_pre_tax+total_tax+expense_amount+named_final)::int,snapshot_value,true,route_blocked
    );
  elsif existing.snapshot is distinct from snapshot_value
     or existing.calculation_blocked is distinct from route_blocked then
    perform set_config('sko.invoice_auto_refresh','1',true);
    update public.invoices
    set subtotal=total_pre_tax::int,
        tax=total_tax::int,
        welfare_amount=total_welfare::int,
        grand_total=(total_pre_tax+total_tax+expense_amount+named_final)::int,
        snapshot=snapshot_value,
        calculation_blocked=route_blocked,
        updated_at=now()
    where id=existing.id;
    perform set_config('sko.invoice_auto_refresh','0',true);
  end if;
  if jsonb_array_length(named_items)>0 then
  perform document_adjustment_private.bind_occurrences(cid,'invoice',customer,first_day,
    (select id from public.invoices where company_id=cid and customer_id=customer and billing_period_start=first_day and automatic_calculation));
  end if;
end;
$function$
;

CREATE OR REPLACE FUNCTION private.certificate_calculation_rows(v_company_id uuid, v_partner_id uuid, v_start date, v_end date)
 RETURNS TABLE(site_name text, work_content text, quantity_label text, unit_price_yen integer, amount_yen integer)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare
  settings public.partner_payment_settings%rowtype;
  hours_per_day numeric:=8;
  overtime_mul numeric:=1.25;
  early_mul numeric:=1.25;
  night_mul numeric:=1.5;
  night_ot_mul numeric:=1.5;
  holiday_mul numeric:=1.35;
  holiday_ot_mul numeric:=1.35;
  holiday_night_mul numeric:=1.6;
  holiday_night_ot_mul numeric:=1.6;
  r_daily integer:=0;
  r_ot integer:=0;
  r_early integer:=0;
  r_night integer:=0;
  r_night_ot integer:=0;
  r_holiday integer:=0;
  r_holiday_ot integer:=0;
  r_holiday_night integer:=0;
  r_holiday_night_ot integer:=0;
  r_night_early integer:=0;
  r_holiday_early integer:=0;
  r_holiday_night_early integer:=0;
begin
  select * into settings from public.partner_payment_settings
  where company_id=v_company_id and partner_company_id=v_partner_id;

  r_daily:=private.resolve_rate_formula(coalesce(settings.daily_rate_yen,0),settings.rate_formula,'{}'::jsonb,'daily')::integer;
  r_ot:=private.resolve_rate_formula(
    r_daily,settings.rate_formula,
    jsonb_build_object('overtime',coalesce(settings.overtime_hour_rate_yen,0)),
    'overtime'
  )::integer;
  r_early:=private.resolve_rate_formula(
    r_daily,settings.rate_formula,
    jsonb_build_object('early',coalesce(settings.early_hour_rate_yen,0)),
    'early'
  )::integer;
  r_night:=private.resolve_rate_formula(
    r_daily,settings.rate_formula,
    jsonb_build_object('night',coalesce(settings.night_day_rate_yen,0)),
    'night'
  )::integer;
  r_night_ot:=private.resolve_rate_formula(
    r_daily,settings.rate_formula,
    jsonb_build_object('night_overtime',coalesce(settings.night_overtime_hour_rate_yen,0)),
    'night_overtime'
  )::integer;
  r_holiday:=private.resolve_rate_formula(
    r_daily,settings.rate_formula,
    jsonb_build_object('holiday',coalesce(settings.holiday_day_rate_yen,0)),
    'holiday'
  )::integer;
  r_holiday_ot:=private.resolve_rate_formula(
    r_daily,settings.rate_formula,
    jsonb_build_object('holiday_overtime',coalesce(settings.holiday_overtime_hour_rate_yen,0)),
    'holiday_overtime'
  )::integer;
  r_holiday_night:=private.resolve_rate_formula(
    r_daily,settings.rate_formula,
    jsonb_build_object('holiday_night',coalesce(settings.holiday_night_day_rate_yen,0)),
    'holiday_night'
  )::integer;
  r_holiday_night_ot:=private.resolve_rate_formula(
    r_daily,settings.rate_formula,
    jsonb_build_object('holiday_night_overtime',coalesce(settings.holiday_night_overtime_hour_rate_yen,0)),
    'holiday_night_overtime'
  )::integer;

  -- Early work uses the independently registered early multiplier in every category.
  -- A positive direct early rate overrides every category consistently.
  hours_per_day:=greatest(coalesce((settings.rate_formula->>'hours_per_day')::numeric,8),0.01);
  early_mul:=coalesce((settings.rate_formula->>'early_multiplier')::numeric,1.25);
  r_night_early:=case when coalesce(settings.early_hour_rate_yen,0)>0
    then settings.early_hour_rate_yen else round(r_night/hours_per_day*early_mul)::integer end;
  r_holiday_early:=case when coalesce(settings.early_hour_rate_yen,0)>0
    then settings.early_hour_rate_yen else round(r_holiday/hours_per_day*early_mul)::integer end;
  r_holiday_night_early:=case when coalesce(settings.early_hour_rate_yen,0)>0
    then settings.early_hour_rate_yen else round(r_holiday_night/hours_per_day*early_mul)::integer end;

  return query
  with source as (
    select
      coalesce(nullif(s.formal_name,''),s.name,'現場未設定') as site_name,
      coalesce(a.work_category,'day') as work_category,
      sum(coalesce(a.base_man_days,0)) as man_days,
      sum(coalesce(a.overtime_hours,0)) as overtime_hours,
      sum(coalesce(a.early_hours,0)) as early_hours
    from public.attendance_entries a
    join public.workers w on w.id=a.worker_id and w.company_id=a.company_id
    left join public.sites s on s.id=a.site_id and s.company_id=a.company_id
    where a.company_id=v_company_id
      and w.partner_company_id=v_partner_id
      and a.work_date between v_start and v_end
    group by
      coalesce(nullif(s.formal_name,''),s.name,'現場未設定'),
      coalesce(a.work_category,'day')
  ),
  base_lines as (
    select src.site_name,
      case src.work_category
        when 'night' then '夜勤'
        when 'holiday' then '休日出勤'
        when 'holiday_night' then '休日夜勤'
        else '通常作業'
      end as work_content,
      trim_scale(src.man_days)::text||'人' as quantity_label,
      case src.work_category
        when 'night' then r_night
        when 'holiday' then r_holiday
        when 'holiday_night' then r_holiday_night
        else r_daily
      end as unit_price_yen,
      round(src.man_days * case src.work_category
        when 'night' then r_night
        when 'holiday' then r_holiday
        when 'holiday_night' then r_holiday_night
        else r_daily
      end)::integer as amount_yen,
      1 as sort_order
    from source src where man_days<>0
    union all
    select src.site_name,
      case src.work_category
        when 'night' then '夜勤残業'
        when 'holiday' then '休日残業'
        when 'holiday_night' then '休日夜勤残業'
        else '残業'
      end,
      trim_scale(src.overtime_hours)::text||'H',
      case src.work_category
        when 'night' then r_night_ot
        when 'holiday' then r_holiday_ot
        when 'holiday_night' then r_holiday_night_ot
        else r_ot
      end,
      round(src.overtime_hours * case src.work_category
        when 'night' then r_night_ot
        when 'holiday' then r_holiday_ot
        when 'holiday_night' then r_holiday_night_ot
        else r_ot
      end)::integer,
      2
    from source src where overtime_hours<>0
    union all
    select src.site_name,'早出',
      trim_scale(src.early_hours)::text||'H',
      case src.work_category
        when 'night' then r_night_early
        when 'holiday' then r_holiday_early
        when 'holiday_night' then r_holiday_night_early
        else r_early
      end,
      round(src.early_hours * case src.work_category
        when 'night' then r_night_early
        when 'holiday' then r_holiday_early
        when 'holiday_night' then r_holiday_night_early
        else r_early
      end)::integer,
      3
    from source src where early_hours<>0
  ),
  allowance_lines as (
    select
      coalesce(nullif(s.formal_name,''),s.name,'現場未設定') as site_name,
      '（'||cfg.name||'）'::text as work_content,
      count(*)::text||'回' as quantity_label,
      cfg.amount_yen::integer as unit_price_yen,
      (count(*)*cfg.amount_yen)::integer as amount_yen,
      4 as sort_order
    from public.attendance_entries a
    join public.workers w on w.id=a.worker_id and w.company_id=a.company_id
    left join public.sites s on s.id=a.site_id and s.company_id=a.company_id
    cross join lateral unnest(coalesce(a.allowance_names,'{}'::text[])) n(name)
    join lateral (
      select
        x->>'name' as name,
        greatest(coalesce((x->>'amount_yen')::integer,0),0) as amount_yen
      from jsonb_array_elements(coalesce(settings.allowances,'[]'::jsonb)) x
      where x->>'name'=n.name
    ) cfg on true
    where a.company_id=v_company_id
      and w.partner_company_id=v_partner_id
      and a.work_date between v_start and v_end
      and cfg.amount_yen>0
    group by coalesce(nullif(s.formal_name,''),s.name,'現場未設定'),cfg.name,cfg.amount_yen
  ),
  named_lines as (
    select '〃'::text as site_name,x->>'title' as work_content,'1'::text as quantity_label,
      ((x->>'amount_yen')::bigint * case when x->>'sign'='minus' then -1 else 1 end)::integer as unit_price_yen,
      ((x->>'amount_yen')::bigint * case when x->>'sign'='minus' then -1 else 1 end)::integer as amount_yen,
      5 as sort_order
    from jsonb_array_elements(document_adjustment_private.active_items(
      v_company_id,'payment_certificate',v_partner_id,v_start)) x
    where x->>'calculation_mode'='before_charges'
  ),
  pre_totals as (
    select coalesce(sum(q.amount_yen),0)::integer as subtotal
    from (
      select bl.amount_yen from base_lines bl
      union all
      select al.amount_yen from allowance_lines al
      union all select nl.amount_yen from named_lines nl
    ) q
  ),
  summary_lines as (
    select '〃'::text as site_name,'福利厚生費'::text as work_content,
      trim_scale(settings.welfare_rate)::text||'%' as quantity_label,
      0::integer as unit_price_yen,
      round(p.subtotal*coalesce(settings.welfare_rate,0)/100)::integer as amount_yen,
      90 as sort_order
    from pre_totals p where coalesce(settings.welfare_rate,0)>0
    union all
    select '〃','消費税',
      trim_scale(settings.tax_rate)::text||'%',
      0,
      round((p.subtotal + round(p.subtotal*coalesce(settings.welfare_rate,0)/100))
        *coalesce(settings.tax_rate,10)/100)::integer,
      91
    from pre_totals p where coalesce(settings.tax_rate,0)>0
  ),
  lines as (
    select * from base_lines
    union all select * from allowance_lines
    union all select * from named_lines
    union all select * from summary_lines
  )
  select l.site_name,l.work_content,l.quantity_label,l.unit_price_yen,l.amount_yen
  from lines l
  order by l.site_name,l.sort_order,l.work_content;
end
$function$
;

CREATE OR REPLACE FUNCTION private.refresh_automatic_payment_certificate(cid uuid, partner uuid, day date)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 named_items jsonb;named_plus numeric:=0;named_minus numeric:=0;
 expense_component jsonb; expense_amount numeric:=0;
 first_day date:=date_trunc('month',day)::date;
 last_day date:=(date_trunc('month',day)+interval '1 month - 1 day')::date;
 existing public.payment_certificates%rowtype;
 settings public.partner_payment_settings%rowtype;
 attendance_count int:=0;
 gross numeric:=0;
 subtotal numeric:=0;
 welfare numeric:=0;
 tax numeric:=0;
 partner_name text;
 snapshot_value jsonb;
 use_v2 boolean; direction_doc uuid; direction_revision integer;
 expense_deductions numeric:=0; expense_net numeric;
 calculation_rows jsonb;
 s record;
 allowance_cfg record;
 allowance_qty numeric;
 allowance_rate numeric;
 hours_per_day numeric:=8;
 overtime_mul numeric:=1.25;
 early_mul numeric:=1.25;
 night_mul numeric:=1.5;
 night_ot_mul numeric:=1.5;
 holiday_mul numeric:=1.35;
 holiday_ot_mul numeric:=1.35;
 holiday_night_mul numeric:=1.6;
 holiday_night_ot_mul numeric:=1.6;
 r_daily numeric:=0;
 r_ot numeric:=0;
 r_early numeric:=0;
 r_night numeric:=0;
 r_night_ot numeric:=0;
 r_holiday numeric:=0;
 r_holiday_ot numeric:=0;
 r_holiday_night numeric:=0;
 r_holiday_night_ot numeric:=0;
begin
 if auth.uid() is null or partner is null then return; end if;
 perform document_adjustment_private.lock_rollout_gate(cid);
 perform pg_advisory_xact_lock(hashtextextended(
   'payment-certificate:'||cid::text||partner::text||first_day::text,0
 ));

 select * into existing
 from public.payment_certificates
 where company_id=cid and partner_company_id=partner
   and period_start=first_day and period_end=last_day
 for update;
 if found and (existing.status<>'draft' or existing.finalized_at is not null or not existing.automatic_calculation) then return; end if;
 if existing.snapshot?'document_adjustments_v1' and not exists(select 1 from document_adjustment_private.rollout r where r.company_id=cid and r.enabled) then return;end if;
 perform document_adjustment_private.ensure_occurrences(cid,'payment_certificate',partner,first_day);
 named_items:=document_adjustment_private.active_items(cid,'payment_certificate',partner,first_day);
 if existing.snapshot?'expense_cost_direction_v2' and not private.expense_cost_direction_v2_enabled(cid) then return;end if;
 use_v2:=private.expense_cost_direction_v2_enabled(cid) and (existing.id is null or existing.snapshot?'expense_cost_direction_v2');
 direction_doc:=coalesce(existing.id,gen_random_uuid());direction_revision:=coalesce(existing.revision,1);

 select * into settings
 from public.partner_payment_settings
 where company_id=cid and partner_company_id=partner;

 select pc.name into partner_name
 from public.partner_companies pc
 where pc.id=partner and pc.company_id=cid;

 select count(*) into attendance_count
 from public.attendance_entries a
 join public.workers w on w.id=a.worker_id and w.company_id=a.company_id
 where a.company_id=cid
   and w.partner_company_id=partner
   and a.work_date between first_day and last_day;

 
 expense_component:=private.expense_cost_components('paymentCertificate',cid,partner,first_day,last_day,existing.id);
 expense_amount:=(expense_component->>'amount_yen')::numeric;
 if attendance_count=0 and jsonb_array_length(named_items)=0 and not coalesce(existing.snapshot?'document_adjustments_v1',false) and not (expense_component->>'has_choices')::boolean
  and existing.id is not null and existing.snapshot?'expense_extra_source_version' then
  update public.payment_certificates set gross_amount=0,deductions=0,net_amount=0,
   snapshot=existing.snapshot||jsonb_build_object('calculation_rows','[]'::jsonb,'attendance_count',0,
    'expense_extra_amount_yen',0,'expense_extra_claims','[]'::jsonb),
   calculation_blocked=false,revision=revision+1,updated_at=now() where id=existing.id;
  return;
 end if;
 if attendance_count=0 and jsonb_array_length(named_items)=0 and not coalesce(existing.snapshot?'document_adjustments_v1',false) and not (expense_component->>'has_choices')::boolean and (not use_v2 or existing.id is null) then
 
   if existing.id is not null and existing.status='draft'
      and existing.automatic_calculation then
     delete from public.payment_certificates where id=existing.id;
   end if;
   return;
 end if;

 select coalesce(jsonb_agg(to_jsonb(r)),'[]'::jsonb),coalesce(sum(r.amount_yen),0)
 into calculation_rows,gross
 from private.certificate_calculation_rows(cid,partner,first_day,last_day) r;

 if use_v2 then expense_deductions:=expense_amount;else gross:=gross+expense_amount;end if;
 named_items:=document_adjustment_private.active_items(cid,'payment_certificate',partner,first_day);
 select coalesce(sum((x->>'amount_yen')::numeric) filter(where x->>'sign'='plus'),0),
        coalesce(sum((x->>'amount_yen')::numeric) filter(where x->>'sign'='minus'),0)
 into named_plus,named_minus from jsonb_array_elements(named_items) x
 where x->>'calculation_mode'='settlement_yen';
 gross:=gross+named_plus;expense_deductions:=expense_deductions+named_minus;
 expense_net:=gross-expense_deductions;
 snapshot_value:=jsonb_build_object(
   'partner_company_name',coalesce(partner_name,''),
   'period_start',first_day,'period_end',last_day,
   'attendance_count',attendance_count,
   'settings_missing',settings.partner_company_id is null,
   'rate_formula',coalesce(settings.rate_formula,'{}'::jsonb),
   'welfare_rate',coalesce(settings.welfare_rate,0),
   'tax_rate',coalesce(settings.tax_rate,10),
   'calculation_rows',calculation_rows,
   'calculation_version',2
 );

 
 if jsonb_array_length(named_items)>0 or coalesce(existing.snapshot?'document_adjustments_v1',false) then
 snapshot_value:=snapshot_value||jsonb_build_object('document_adjustments_v1',named_items,'document_final_plus_yen',named_plus,'document_final_minus_yen',named_minus);
 end if;
 if use_v2 then
 snapshot_value:=snapshot_value||jsonb_build_object(
 'expense_cost_direction_v2',private.expense_payment_v2_envelope(cid,direction_doc,partner,first_day,direction_revision,expense_amount,expense_component->'claims'),
 'expense_cost_basis',jsonb_build_object('company_id',cid,'document_id',direction_doc,'subject_id',partner,'month',to_char(first_day,'YYYY-MM'),'document_revision',direction_revision,'gross_before_expense_yen',gross,'other_deductions_yen',named_minus));
 elsif coalesce((expense_component->>'has_choices')::boolean,false) or existing.snapshot?'expense_extra_source_version' then
  snapshot_value:=snapshot_value||jsonb_build_object('expense_extra_amount_yen',expense_amount,
   'expense_extra_claims',expense_component->'claims','expense_extra_source_version',1);
 end if;
 snapshot_value:=snapshot_value||private.document_company_seal_snapshot
 (existing.snapshot,cid,existing.id is null);
  if existing.id is null then
   insert into public.payment_certificates(
     id,company_id,partner_company_id,period_start,period_end,status,
     gross_amount,deductions,net_amount,snapshot,
     automatic_calculation,calculation_blocked
   )
   values(
     direction_doc,cid,partner,first_day,last_day,'draft',
     gross::int,expense_deductions::int,expense_net::int,snapshot_value,true,false
   );
 elsif existing.gross_amount is distinct from gross::int
    or existing.net_amount is distinct from expense_net::int
    or (use_v2 and existing.deductions is distinct from expense_deductions::int)
    or existing.snapshot is distinct from snapshot_value
    or existing.calculation_blocked then
   update public.payment_certificates
   set gross_amount=gross::int,deductions=expense_deductions::int,net_amount=expense_net::int,
       snapshot=case when use_v2 then jsonb_set(jsonb_set(snapshot_value,'{expense_cost_direction_v2,document_revision}',to_jsonb(existing.revision+1)),'{expense_cost_basis,document_revision}',to_jsonb(existing.revision+1)) else snapshot_value end,calculation_blocked=false,
       revision=revision+1,updated_at=now()
   where id=existing.id;
 end if;
 if jsonb_array_length(named_items)>0 then
 perform document_adjustment_private.bind_occurrences(cid,'payment_certificate',partner,first_day,
   (select id from public.payment_certificates where company_id=cid and partner_company_id=partner and period_start=first_day));
 end if;
end
$function$
;

CREATE OR REPLACE FUNCTION private.expense_payment_v2_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare envelope jsonb:=new.snapshot->'expense_cost_direction_v2';basis jsonb;expected jsonb;gross numeric;named_plus numeric:=0;named_minus numeric:=0;named_expected jsonb;
begin
 if tg_op='DELETE' then
 if old.snapshot?'expense_cost_direction_v2' and old.status='finalized' then raise exception 'finalized v2 payment immutable';end if;
 return old;end if;
 if tg_op='UPDATE' and old.snapshot?'expense_cost_direction_v2' then
 if not new.snapshot?'expense_cost_direction_v2' then raise exception 'v2 downgrade refused';end if;
 if old.status='finalized' and (to_jsonb(old)-'updated_at') is distinct from (to_jsonb(new)-'updated_at') then raise exception 'finalized v2 payment immutable';end if;
 end if;
 if not new.snapshot?'expense_cost_direction_v2' then return new;end if;
 if not new.automatic_calculation or new.snapshot?'expense_extra_source_version'
 or new.snapshot?'expense_extra_amount_yen' or new.snapshot?'expense_extra_claims'
 then raise exception 'mixed or manual v2 expense source refused';end if;
 if new.company_id is null or new.id is null or new.partner_company_id is null or new.period_start is null or new.period_end is null
 or new.revision is null or new.gross_amount is null or new.deductions is null or new.net_amount is null
 or jsonb_typeof(new.snapshot->'calculation_rows') is distinct from 'array'
 or jsonb_typeof(envelope) is distinct from 'object' or envelope->>'version' is distinct from '2'
 or new.period_start<>date_trunc('month',new.period_start)::date
 or new.period_end<>(date_trunc('month',new.period_start)+interval '1 month - 1 day')::date
 then raise exception 'v2 document period differs';end if;
 expected:=private.expense_payment_v2_envelope(new.company_id,new.id,new.partner_company_id,new.period_start,new.revision,
 (envelope->>'amount_yen')::numeric,envelope->'claims');
 if envelope is distinct from expected then raise exception 'v2 document scope or claims differ';end if;
 select coalesce(sum((r->>'amount_yen')::numeric),0) into gross from jsonb_array_elements(new.snapshot->'calculation_rows') r;
if new.snapshot?'document_adjustments_v1' then
 named_expected:=document_adjustment_private.ledger_items(new.company_id,'payment_certificate',new.partner_company_id,new.period_start);
 if new.snapshot->'document_adjustments_v1' is distinct from named_expected then
  raise exception 'payment adjustments differ from canonical company/party/month ledger';end if;
 select coalesce(sum((x->>'amount_yen')::numeric) filter(where x->>'sign'='plus'),0),
        coalesce(sum((x->>'amount_yen')::numeric) filter(where x->>'sign'='minus'),0)
 into named_plus,named_minus from jsonb_array_elements(named_expected) x
 where x->>'calculation_mode'='settlement_yen';
 if new.snapshot->'document_final_plus_yen' is distinct from to_jsonb(named_plus)
    or new.snapshot->'document_final_minus_yen' is distinct from to_jsonb(named_minus) then
  raise exception 'payment final adjustment amounts differ from ledger';end if;
elsif new.snapshot?'document_final_plus_yen' or new.snapshot?'document_final_minus_yen' then
 raise exception 'orphan payment adjustment amounts refused';
end if;
gross:=gross+named_plus;
 basis:=jsonb_build_object('company_id',new.company_id,'document_id',new.id,'subject_id',new.partner_company_id,
 'month',to_char(new.period_start,'YYYY-MM'),'document_revision',new.revision,'gross_before_expense_yen',gross,'other_deductions_yen',named_minus);
 if new.snapshot->'expense_cost_basis' is distinct from basis or gross<0 or new.gross_amount<>gross
 or new.deductions<>(envelope->>'amount_yen')::numeric+named_minus or new.net_amount<>gross-new.deductions
 then raise exception 'v2 payment amount or calculation basis differs';end if;
 return new;
end $function$;


-- REVIEW ONLY: requires full source integration, approval tests and UI adapter.

create table document_adjustment_private.previews (
 token uuid primary key default gen_random_uuid(),
 company_id uuid not null references public.companies(id),actor_id uuid not null, request jsonb not null,
 source_snapshot jsonb not null, source_total bigint not null,
 result_total bigint not null, result jsonb not null,
 created_at timestamptz not null default clock_timestamp()
);
alter table document_adjustment_private.previews enable row level security;
revoke all on document_adjustment_private.previews from public,anon,authenticated,service_role;
create index adjustment_previews_expiry on document_adjustment_private.previews(company_id,created_at,token);

create function document_adjustment_private.authorize(p_company uuid,p_kind text,p_party uuid)
returns uuid language plpgsql security definer set search_path='' as $body$
declare actor uuid:=auth.uid();r text;
begin
 perform private.require_reauthentication_session();
 select role::text into r from public.company_members where company_id=p_company and user_id=actor;
 if r is null then raise sqlstate '42501' using message='会社へのアクセス権限がありません';end if;
 if p_kind='invoice' then
  if not private.has_company_feature(p_company,'can_manage_invoices') then
   raise sqlstate '42501' using message='請求書の編集権限がありません';end if;
  if p_party is not null and not exists(select 1 from public.customers where id=p_party and company_id=p_company) then
   raise sqlstate '42501' using message='取引会社を確認できません';end if;
 elsif p_kind='payment_certificate' then
  if r not in ('owner','admin') then raise sqlstate '42501' using message='支払証明書の編集権限がありません';end if;
  if p_party is not null and not exists(select 1 from public.partner_companies where id=p_party and company_id=p_company) then
   raise sqlstate '42501' using message='協力会社を確認できません';end if;
 else raise exception '帳票区分を確認できません';end if;
 return actor;
end $body$;
revoke all on function document_adjustment_private.authorize(uuid,text,uuid) from public,anon,authenticated,service_role;

create function document_adjustment_private.authorize_operations(p_company uuid)
returns uuid language plpgsql security definer set search_path='' as $body$
declare sid uuid;
begin
 sid:=private.require_reauthentication_session();
 if not exists(select 1 from public.company_members where company_id=p_company
  and user_id=auth.uid() and role::text in ('owner','admin')) then
  raise sqlstate '42501' using message='会社の管理権限がありません';end if;
 return sid;
end $body$;
revoke all on function document_adjustment_private.authorize_operations(uuid) from public,anon,authenticated,service_role;

create function public.set_trade_document_adjustment_rollout(p_company_id uuid,p_enabled boolean,p_reason text)
returns jsonb language plpgsql security definer set search_path='' as $body$
declare sid uuid;before_enabled boolean;event_id bigint;
begin
 sid:=document_adjustment_private.authorize_operations(p_company_id);
 if p_enabled is null or p_reason is null or length(btrim(p_reason)) not between 5 and 500 then
  raise exception '変更理由を5文字以上500文字以内で入力してください';end if;
 perform document_adjustment_private.lock_rollout_gate(p_company_id,true);
 insert into document_adjustment_private.rollout(company_id) values(p_company_id) on conflict do nothing;
 select enabled into before_enabled from document_adjustment_private.rollout where company_id=p_company_id for update;
 update document_adjustment_private.rollout set enabled=p_enabled,updated_at=clock_timestamp() where company_id=p_company_id;
 insert into document_adjustment_private.operation_events(company_id,actor_id,session_id,action,reason,previous_enabled,enabled)
 values(p_company_id,auth.uid(),sid,'rollout_change',btrim(p_reason),before_enabled,p_enabled) returning id into event_id;
 return jsonb_build_object('company_id',p_company_id,'enabled',p_enabled,'previous_enabled',before_enabled,'event_id',event_id,'actor_id',auth.uid(),'reason',btrim(p_reason));
end $body$;
revoke all on function public.set_trade_document_adjustment_rollout(uuid,boolean,text) from public,anon,service_role;
grant execute on function public.set_trade_document_adjustment_rollout(uuid,boolean,text) to authenticated;

create function document_adjustment_private.cleanup_previews(p_company uuid,p_actor_only uuid,p_limit integer,p_reason text)
returns integer language plpgsql security definer set search_path='' as $body$
declare deleted integer;sid uuid:=private.require_reauthentication_session();
begin
 if p_limit not between 1 and 500 or p_reason is null or length(btrim(p_reason)) not between 5 and 500 then raise exception '整理条件を確認できません';end if;
 with expired as (
  select p.token from document_adjustment_private.previews p
  where p.company_id=p_company and (p_actor_only is null or p.actor_id=p_actor_only)
   and p.created_at<clock_timestamp()-interval '24 hours'
   and not exists(select 1 from document_adjustment_private.commands c where c.receipt->>'preview_token'=p.token::text)
  order by p.created_at,p.token limit p_limit for update skip locked
 ),removed as (delete from document_adjustment_private.previews p using expired e where p.token=e.token returning 1)
 select count(*)::integer into deleted from removed;
 if deleted>0 then
  insert into document_adjustment_private.operation_events(company_id,actor_id,session_id,action,reason,details)
  values(p_company,auth.uid(),sid,'preview_cleanup',p_reason,jsonb_build_object('deleted_unused_previews',deleted,'expiry_hours',24,'actor_only',p_actor_only));
 end if;
 return deleted;
end $body$;
revoke all on function document_adjustment_private.cleanup_previews(uuid,uuid,integer,text) from public,anon,authenticated,service_role;

create function public.cleanup_trade_document_adjustment_previews(p_company_id uuid,p_limit integer default 100,p_reason text default '期限切れ未使用プレビューの整理')
returns jsonb language plpgsql security definer set search_path='' as $body$
declare n integer;
begin
 perform document_adjustment_private.authorize_operations(p_company_id);
 n:=document_adjustment_private.cleanup_previews(p_company_id,null,p_limit,p_reason);
 return jsonb_build_object('company_id',p_company_id,'deleted_unused_previews',n);
end $body$;
revoke all on function public.cleanup_trade_document_adjustment_previews(uuid,integer,text) from public,anon,service_role;
grant execute on function public.cleanup_trade_document_adjustment_previews(uuid,integer,text) to authenticated;

create function public.read_trade_document_adjustment_operations(p_company_id uuid,p_before_id bigint default null)
returns jsonb language plpgsql security definer set search_path='' as $body$
declare events jsonb;flag boolean;
begin
 perform document_adjustment_private.authorize_operations(p_company_id);
 select coalesce((select enabled from document_adjustment_private.rollout where company_id=p_company_id),false) into flag;
 select coalesce(jsonb_agg(to_jsonb(e) order by e.id desc),'[]'::jsonb) into events from (
  select id,actor_id,session_id,action,reason,previous_enabled,enabled,details,created_at
   from document_adjustment_private.operation_events where company_id=p_company_id and (p_before_id is null or id<p_before_id)
   order by id desc limit 100
 ) e;
 return jsonb_build_object('company_id',p_company_id,'enabled',flag,'entries',events);
end $body$;
revoke all on function public.read_trade_document_adjustment_operations(uuid,bigint) from public,anon,service_role;
grant execute on function public.read_trade_document_adjustment_operations(uuid,bigint) to authenticated;

create function document_adjustment_private.source(p_company uuid,p_kind text,p_party uuid,p_month date)
returns jsonb language plpgsql security definer set search_path='' as $body$
declare d jsonb;snap jsonb;
begin
 if p_month<>date_trunc('month',p_month)::date then raise exception '対象月を確認できません';end if;
 perform document_adjustment_private.lock_rollout_gate(p_company);
 perform pg_advisory_xact_lock(hashtextextended(
  case p_kind when 'invoice' then 'invoice:' else 'payment-certificate:' end
   ||p_company::text||p_party::text||p_month::text,0));
 if p_kind='invoice' then
  if (select count(*) from public.invoices where company_id=p_company and customer_id=p_party and billing_period_start=p_month)>1 then
   raise exception '同じ月に複数の請求書があるため対象を確認してください';end if;
  perform 1 from public.invoices where company_id=p_company and customer_id=p_party and billing_period_start=p_month for update;
  if exists(select 1 from public.invoices i where i.company_id=p_company and i.customer_id=p_party and i.billing_period_start=p_month
   and (i.status<>'draft' or i.finalized_at is not null or i.approval_finalized_at is not null or coalesce(i.invoice_seal_frozen,false)
    or not i.automatic_calculation or exists(select 1 from public.invoice_approvals a where a.invoice_id=i.id and a.status='approved'))) then
   raise exception '確定・承認済みの請求書は変更できません';end if;
  perform private.refresh_automatic_invoice(p_company,p_party,p_month);
  select jsonb_build_object('id',id,'snapshot',snapshot,'total',grand_total,'updated_at',updated_at)
   into d from public.invoices where company_id=p_company and customer_id=p_party and billing_period_start=p_month;
 else
  perform 1 from public.payment_certificates where company_id=p_company and partner_company_id=p_party and period_start=p_month for update;
  if exists(select 1 from public.payment_certificates where company_id=p_company and partner_company_id=p_party and period_start=p_month
   and (status<>'draft' or finalized_at is not null or not automatic_calculation)) then
   raise exception '確定済みの支払証明書は変更できません';end if;
  perform private.refresh_automatic_payment_certificate(p_company,p_party,p_month);
  select jsonb_build_object('id',id,'snapshot',snapshot,'total',net_amount,'updated_at',updated_at)
   into d from public.payment_certificates where company_id=p_company and partner_company_id=p_party and period_start=p_month;
 end if;
 if d is null then
  if p_kind='invoice' then
   select jsonb_build_object('tax_rate_bps',coalesce(c.tax_rate,0)*100,
    'sites',coalesce((select jsonb_agg(jsonb_build_object('site_id',s.id,'site_name',s.name,
      'subtotal',0,'tax',0,'welfare_rate_bps',case when fs.welfare_rate between 0 and 100 then fs.welfare_rate*100 else 0 end,'lines','[]'::jsonb) order by s.created_at,s.id)
     from public.sites s left join public.site_financial_settings fs on fs.company_id=p_company and fs.site_id=s.id
     where s.company_id=p_company and s.customer_id=p_party),'[]'::jsonb)) into snap from public.companies c where c.id=p_company;
  else
   select jsonb_build_object('welfare_rate',coalesce(s.welfare_rate,0),'tax_rate',coalesce(s.tax_rate,10),'calculation_rows','[]'::jsonb)
    into snap from public.partner_payment_settings s where s.company_id=p_company and s.partner_company_id=p_party;
   if snap is null then snap:=jsonb_build_object('welfare_rate',0,'tax_rate',10,'calculation_rows','[]'::jsonb);end if;
  end if;
  d:=jsonb_build_object('id',null,'snapshot',snap,'total',0,'updated_at',null);
 end if;
 return d;
end $body$;
revoke all on function document_adjustment_private.source(uuid,text,uuid,date) from public,anon,authenticated,service_role;

create function public.read_trade_document_adjustments(p_company_id uuid,p_kind text,p_month date,p_party_id uuid default null)
returns jsonb language plpgsql security definer set search_path='' as $body$
declare parties jsonb;entries jsonb:='[]';sites jsonb:='[]';items jsonb;src jsonb;
 ready boolean;locked boolean:=false;v bigint:=0;
begin
 perform document_adjustment_private.authorize(p_company_id,p_kind,p_party_id);
 perform document_adjustment_private.lock_rollout_gate(p_company_id);
 if p_month is null or p_month<>date_trunc('month',p_month)::date then raise exception '対象月を確認できません';end if;
 select coalesce(enabled,false) into ready from document_adjustment_private.rollout where company_id=p_company_id;
 ready:=coalesce(ready,false);
 if p_kind='invoice' then
  select coalesce(jsonb_agg(jsonb_build_object('id',id,'company_id',company_id,'kind',p_kind,'name',name) order by name,id),'[]') into parties
   from public.customers where company_id=p_company_id;
  if p_party_id is not null then
   select coalesce(bool_or(status<>'draft' or finalized_at is not null or approval_finalized_at is not null or coalesce(invoice_seal_frozen,false) or not automatic_calculation),false)
    into locked from public.invoices where company_id=p_company_id and customer_id=p_party_id and billing_period_start=p_month;
   locked:=locked or exists(select 1 from public.invoice_approvals a join public.invoices i on i.id=a.invoice_id
    where i.company_id=p_company_id and i.customer_id=p_party_id and i.billing_period_start=p_month and a.status='approved');
  end if;
 else
  select coalesce(jsonb_agg(jsonb_build_object('id',id,'company_id',company_id,'kind',p_kind,'name',name) order by name,id),'[]') into parties
   from public.partner_companies where company_id=p_company_id;
  if p_party_id is not null then
   select coalesce(bool_or(status<>'draft' or finalized_at is not null or not automatic_calculation),false) into locked
    from public.payment_certificates where company_id=p_company_id and partner_company_id=p_party_id and period_start=p_month;
  end if;
 end if;
 if p_party_id is not null and ready and not locked then
  perform pg_advisory_xact_lock(hashtextextended(case p_kind when 'invoice' then 'invoice:' else 'payment-certificate:' end||p_company_id::text||p_party_id::text||p_month::text,0));
  -- Materialize one occurrence per template/month before source refresh. A
  -- retry cannot create a second occurrence or modify any finalized snapshot.
  items:=document_adjustment_private.active_items(p_company_id,p_kind,p_party_id,p_month);
  insert into document_adjustment_private.occurrences(template_id,month,template_version)
   select (x->>'template_id')::uuid,p_month,(x->>'template_version')::bigint from jsonb_array_elements(items) x
   on conflict(template_id,month) do nothing;
  src:=document_adjustment_private.source(p_company_id,p_kind,p_party_id,p_month);
  update document_adjustment_private.occurrences o set document_id=(src->>'id')::uuid
   from document_adjustment_private.templates t where t.id=o.template_id and t.company_id=p_company_id and t.kind=p_kind
    and t.party_id=p_party_id and o.month=p_month and o.document_id is null;
  items:=document_adjustment_private.active_items(p_company_id,p_kind,p_party_id,p_month);
  select coalesce(jsonb_agg(x||jsonb_build_object('id',x->'entry_id','editable',true,
   'can_stop',x->>'recurrence'='monthly','canceled',false,'template_stopped',false,'version',1)),'[]') into entries
   from jsonb_array_elements(items) x;
  if p_kind='invoice' then
   select coalesce(jsonb_agg(jsonb_build_object('id',x->'site_id','label',x->>'site_name')),'[]') into sites
    from jsonb_array_elements(src->'snapshot'->'sites') x where x->>'site_id' is not null;
  end if;
  select coalesce((select version from document_adjustment_private.scope_versions where company_id=p_company_id and kind=p_kind and party_id=p_party_id and month=p_month),0) into v;
 end if;
 return jsonb_build_object('company_id',p_company_id,'kind',p_kind,'month',p_month,'party_id',p_party_id,
  'parties',parties,'entries',entries,'version',v,'ready',ready,'can_edit',true,'locked',locked,
  'tax_mode','per_item','supported_modes',jsonb_build_array('before_charges','settlement_yen'),'charge_sites',sites);
end $body$;
revoke all on function public.read_trade_document_adjustments(uuid,text,date,uuid) from public,anon,service_role;
grant execute on function public.read_trade_document_adjustments(uuid,text,date,uuid) to authenticated;

create function document_adjustment_private.plan(p_request jsonb)
returns jsonb language plpgsql security definer set search_path='' as $body$
declare cid uuid:=(p_request->>'company_id')::uuid;k text:=p_request->>'kind';
 party uuid:=(p_request->>'party_id')::uuid;m date:=(p_request->>'month')::date;
 a text:=p_request->>'action';scope text:=p_request->>'update_scope';
 items jsonb;next_items jsonb;entry jsonb;oid uuid;tid uuid;ver bigint;sv bigint;
begin
 if jsonb_typeof(p_request)<>'object' or not p_request ?& array['command_id','company_id','kind','party_id','month','expected_version','action','entry_id','sign','title','amount_yen','recurrence','effective_month','calculation_mode','site_id','expected_template_version','update_scope']
  or p_request->>'command_id' is null or p_request->>'company_id' is null or p_request->>'kind' is null
  or p_request->>'party_id' is null or p_request->>'month' is null or p_request->>'expected_version' is null
  or p_request->>'action' is null or p_request->>'effective_month' is null or p_request->>'calculation_mode' is null
  or p_request->>'update_scope' is null then raise exception '変更内容を確認できません';end if;
 perform document_adjustment_private.authorize(cid,k,party);
 if not exists(select 1 from document_adjustment_private.rollout where company_id=cid and enabled) then
  raise exception '項目の加減算は準備中です';end if;
 if a not in ('add','edit','cancel','stop') or scope not in ('current_month','from_month')
  or (p_request->>'effective_month')::date<>m or m<>date_trunc('month',m)::date
  or p_request->>'calculation_mode' not in ('before_charges','settlement_yen') then
  raise exception '変更内容と対象月を確認できません';end if;
 select coalesce((select version from document_adjustment_private.scope_versions where company_id=cid and kind=k and party_id=party and month=m),0) into sv;
 if sv is distinct from (p_request->>'expected_version')::bigint then raise exception '他の変更がありました。最新の内容を確認してください';end if;
 items:=document_adjustment_private.active_items(cid,k,party,m);
 if a='add' then
  if scope<>'current_month' then raise exception '追加の対象月を確認してください';end if;
  oid:=gen_random_uuid();tid:=gen_random_uuid();ver:=1;
 else
  oid:=(p_request->>'entry_id')::uuid;
  select x into entry from jsonb_array_elements(items) x where x->>'entry_id'=oid::text;
  if entry is null then raise exception '変更対象を確認できません';end if;
  tid:=(entry->>'template_id')::uuid;ver:=(entry->>'template_version')::bigint;
  if scope='from_month' and ver is distinct from (p_request->>'expected_template_version')::bigint then
   raise exception '毎月設定が変更されています';end if;
  if scope='from_month' and entry->>'recurrence'<>'monthly' then raise exception '毎月の項目ではありません';end if;
 end if;
 if a in ('add','edit') then
  if p_request->>'title' is null or p_request->>'amount_yen' is null or p_request->>'sign' is null or p_request->>'recurrence' is null
   or p_request->>'sign' not in ('plus','minus') or p_request->>'recurrence' not in ('once','monthly')
   or length(btrim(p_request->>'title')) not between 1 and 120
   or (p_request->>'amount_yen')::numeric<>trunc((p_request->>'amount_yen')::numeric)
   or (p_request->>'amount_yen')::numeric not between 1 and 2147483647 then
   raise exception '項目名・金額を確認してください';end if;
  if a='edit' and p_request->>'recurrence'<>entry->>'recurrence' then
   raise exception '繰り返し区分は新しい項目で登録してください';end if;
  if k='invoice' and p_request->>'calculation_mode'='before_charges' and not exists(
   select 1 from public.sites where id=(p_request->>'site_id')::uuid and company_id=cid and customer_id=party
  ) then raise exception '対象現場を確認してください';end if;
  if k='payment_certificate' and p_request->>'calculation_mode'='before_charges' and not exists(
   select 1 from public.partner_payment_settings where company_id=cid and partner_company_id=party
    and welfare_rate is not null and tax_rate is not null
  ) then raise exception '協力会社の福利厚生費・税率設定を確認してください';end if;
 end if;
 if (a='cancel' and scope<>'current_month') or (a='stop' and scope<>'from_month') then
  raise exception '削除・停止する範囲を確認してください';end if;
 select coalesce(jsonb_agg(x),'[]'::jsonb) into next_items from jsonb_array_elements(items) x where x->>'entry_id' is distinct from oid::text;
 if a in ('add','edit') then
  entry:=jsonb_build_object('entry_id',oid,'template_id',tid,'template_version',ver,
   'title',btrim(p_request->>'title'),'sign',p_request->>'sign','amount_yen',(p_request->>'amount_yen')::bigint,
   'recurrence',p_request->>'recurrence','calculation_mode',p_request->>'calculation_mode',
   'site_id',p_request->>'site_id','month',m);
  next_items:=next_items||jsonb_build_array(entry);
 end if;
 return jsonb_build_object('old_items',items,'new_items',next_items,'entry',entry,'entry_id',oid,'template_id',tid,'template_version',ver,'version',sv);
end $body$;
revoke all on function document_adjustment_private.plan(jsonb) from public,anon,authenticated,service_role;

create function public.preview_trade_document_adjustment(p_command jsonb)
returns jsonb language plpgsql security definer set search_path='' as $body$
declare actor uuid;plan jsonb;src jsonb;d jsonb;token uuid;result jsonb;
begin
 actor:=document_adjustment_private.authorize((p_command->>'company_id')::uuid,p_command->>'kind',(p_command->>'party_id')::uuid);
 src:=document_adjustment_private.source((p_command->>'company_id')::uuid,p_command->>'kind',(p_command->>'party_id')::uuid,(p_command->>'month')::date);
 plan:=document_adjustment_private.plan(p_command);
 d:=document_adjustment_private.preview_delta(p_command->>'kind',src->'snapshot',plan->'old_items',plan->'new_items');
 if (src->>'total')::bigint+(d->>'total_delta_yen')::bigint not between -2147483648 and 2147483647 then
  raise exception '帳票の合計金額が保存可能な範囲を超えています';end if;
 token:=gen_random_uuid();
 result:=jsonb_build_object('request',p_command,'token',token,'base_total_yen',(src->>'total')::bigint,
  'result_total_yen',(src->>'total')::bigint+(d->>'total_delta_yen')::bigint,
  'welfare_yen',d->'welfare_delta_yen','tax_yen',d->'tax_delta_yen','adjustment_yen',d->'settlement_delta_yen');
 insert into document_adjustment_private.previews(token,company_id,actor_id,request,source_snapshot,source_total,result_total,result)
 values(token,(p_command->>'company_id')::uuid,actor,p_command,src,(src->>'total')::bigint,(result->>'result_total_yen')::bigint,result||jsonb_build_object('plan',plan));
 perform document_adjustment_private.cleanup_previews((p_command->>'company_id')::uuid,actor,100,'期限切れ未使用プレビューの自動整理');
 return result;
end $body$;
revoke all on function public.preview_trade_document_adjustment(jsonb) from public,anon,service_role;
grant execute on function public.preview_trade_document_adjustment(jsonb) to authenticated;

create function public.apply_trade_document_adjustment(p_command jsonb,p_preview_token uuid)
returns jsonb language plpgsql security definer set search_path='' as $body$
declare actor uuid;cid uuid:=(p_command->>'company_id')::uuid;k text:=p_command->>'kind';
 party uuid:=(p_command->>'party_id')::uuid;m date:=(p_command->>'month')::date;
 prev document_adjustment_private.previews%rowtype;c document_adjustment_private.commands%rowtype;
 src jsonb;after_source jsonb;plan jsonb;entry jsonb;tid uuid;oid uuid;v bigint;
 receipt jsonb;entry_data jsonb;current_version bigint;future record;
 future_states jsonb:='[]'::jsonb;future_after jsonb;
begin
 actor:=document_adjustment_private.authorize(cid,k,party);
 perform document_adjustment_private.lock_rollout_gate(cid);
 -- Serialize retries before checking the durable receipt.
 perform pg_advisory_xact_lock(hashtextextended('document-adjustment-command:'||(p_command->>'command_id'),0));
 select * into c from document_adjustment_private.commands where command_id=(p_command->>'command_id')::uuid;
 if found then
  if c.actor_id<>actor or c.company_id<>cid or c.request is distinct from p_command then
   raise exception '同じ保存番号で異なる操作はできません';end if;
  return c.receipt;
 end if;
 select * into prev from document_adjustment_private.previews where token=p_preview_token and actor_id=actor for update;
 if not found or prev.request is distinct from p_command or prev.created_at<clock_timestamp()-interval '10 minutes' then
  raise exception '計算結果をもう一度確認してください';end if;
 plan:=prev.result->'plan';tid:=(plan->>'template_id')::uuid;oid:=(plan->>'entry_id')::uuid;
 if p_command->>'update_scope'='from_month' then
  perform 1 from document_adjustment_private.templates where id=tid for update;
  select max(version) into current_version from document_adjustment_private.template_versions where template_id=tid;
  if current_version is distinct from (p_command->>'expected_template_version')::bigint then
   raise exception '毎月設定が変更されています';end if;
 end if;
 src:=document_adjustment_private.source(cid,k,party,m);
 if src is distinct from prev.source_snapshot then raise exception '帳票が変更されています。計算結果を確認してください';end if;
 -- Revalidate current permissions, scope CAS and item bindings under source lock.
 perform document_adjustment_private.plan(p_command);
 entry:=plan->'entry';v:=(plan->>'template_version')::bigint;
 entry_data:=jsonb_build_object('title',entry->>'title','sign',entry->>'sign','amount_yen',entry->'amount_yen',
  'calculation_mode',entry->>'calculation_mode','site_id',entry->>'site_id');
 if p_command->>'action'='add' then
  insert into document_adjustment_private.templates(id,company_id,kind,party_id,recurrence,created_by)
   values(tid,cid,k,party,p_command->>'recurrence',actor);
  insert into document_adjustment_private.template_versions(template_id,version,effective_month,title,sign,amount_yen,calculation_mode,site_id,actor_id)
   values(tid,1,m,entry->>'title',entry->>'sign',(entry->>'amount_yen')::bigint,entry->>'calculation_mode',(entry->>'site_id')::uuid,actor);
  insert into document_adjustment_private.occurrences(id,template_id,month,document_id,template_version)
   values(oid,tid,m,(src->>'id')::uuid,1);
 elsif p_command->>'action'='cancel' then
  update document_adjustment_private.occurrences set canceled=true where id=oid and template_id=tid and month=m;
 elsif p_command->>'update_scope'='from_month' then
  insert into document_adjustment_private.template_versions(template_id,version,effective_month,title,sign,amount_yen,calculation_mode,site_id,actor_id,stopped)
   values(tid,v+1,m,entry->>'title',entry->>'sign',(entry->>'amount_yen')::bigint,entry->>'calculation_mode',(entry->>'site_id')::uuid,actor,p_command->>'action'='stop');
  update document_adjustment_private.occurrences set template_version=v+1,override=null where id=oid;
 else
  update document_adjustment_private.occurrences set override=entry_data where id=oid and template_id=tid and month=m;
 end if;
 insert into document_adjustment_private.scope_versions(company_id,kind,party_id,month,version)
  values(cid,k,party,m,1) on conflict(company_id,kind,party_id,month) do update set version=document_adjustment_private.scope_versions.version+1
  returning version into current_version;
 after_source:=document_adjustment_private.source(cid,k,party,m);
 if (after_source->>'total')::bigint is distinct from prev.result_total then
  raise exception '登録後の合計と確認した計算結果が一致しません。保存を取り消しました';end if;
 if p_command->>'update_scope'='from_month' or (p_command->>'action'='add' and p_command->>'recurrence'='monthly') then
  -- Refresh already-created future drafts in chronological lock order. Frozen
  -- documents retain their saved snapshot and never enter this projection.
  for future in
   select billing_period_start as month,jsonb_build_object('id',id,'snapshot',snapshot,'total',grand_total) as before_state
   from public.invoices i where k='invoice' and company_id=cid and customer_id=party and billing_period_start>m
    and status='draft' and automatic_calculation and finalized_at is null and approval_finalized_at is null and not coalesce(invoice_seal_frozen,false)
    and not exists(select 1 from public.invoice_approvals a where a.invoice_id=i.id and a.status='approved')
   union all
   select period_start,jsonb_build_object('id',id,'snapshot',snapshot,'total',net_amount)
   from public.payment_certificates where k='payment_certificate' and company_id=cid and partner_company_id=party and period_start>m
    and status='draft' and automatic_calculation and finalized_at is null
   order by 1
  loop
   future_after:=document_adjustment_private.source(cid,k,party,future.month);
   insert into document_adjustment_private.scope_versions(company_id,kind,party_id,month,version)
    values(cid,k,party,future.month,1) on conflict(company_id,kind,party_id,month)
    do update set version=document_adjustment_private.scope_versions.version+1;
   future_states:=future_states||jsonb_build_array(jsonb_build_object('month',future.month,'before',future.before_state,'after',future_after));
  end loop;
 end if;
 receipt:=jsonb_build_object('request',p_command,'applied',true,'version',current_version,'entry_id',oid,
  'preview_token',p_preview_token,'result_total_yen',prev.result_total);
 insert into document_adjustment_private.commands(command_id,actor_id,company_id,request,receipt)
  values((p_command->>'command_id')::uuid,actor,cid,p_command,receipt);
 insert into document_adjustment_private.audit(command_id,actor_id,company_id,before_state,after_state)
  values((p_command->>'command_id')::uuid,actor,cid,src,after_source||jsonb_build_object('receipt',receipt,'entry',entry,'future_drafts',future_states));
 return receipt;
end $body$;
revoke all on function public.apply_trade_document_adjustment(jsonb,uuid) from public,anon,service_role;
grant execute on function public.apply_trade_document_adjustment(jsonb,uuid) to authenticated;

-- Retrying lookup rechecks current company permissions; revoked users do not
-- regain access through an old command receipt. Never treat null as saved.
create function public.lookup_trade_document_adjustment(p_company_id uuid,p_command_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $body$
declare c document_adjustment_private.commands%rowtype;
begin
 perform private.require_reauthentication_session();
 select * into c from document_adjustment_private.commands where command_id=p_command_id
  and company_id=p_company_id and actor_id=auth.uid();
 if not found then return null;end if;
 perform document_adjustment_private.authorize(p_company_id,c.request->>'kind',(c.request->>'party_id')::uuid);
 return c.receipt;
end $body$;
revoke all on function public.lookup_trade_document_adjustment(uuid,uuid) from public,anon,service_role;
grant execute on function public.lookup_trade_document_adjustment(uuid,uuid) to authenticated;

create function public.read_trade_document_adjustment_history(p_company_id uuid,p_kind text,p_party_id uuid,p_month date,p_before_id bigint default null)
returns jsonb language plpgsql security definer set search_path='' as $body$
declare rows jsonb;oldest bigint;more boolean;
begin
 perform document_adjustment_private.authorize(p_company_id,p_kind,p_party_id);
 if p_party_id is null or p_month is null or p_month<>date_trunc('month',p_month)::date or (p_before_id is not null and p_before_id<1) then
  raise exception '変更履歴の対象を確認できません';end if;
 select coalesce(jsonb_agg(e.value order by e.id desc),'[]'::jsonb),min(e.id) into rows,oldest from (
  select a.id,jsonb_build_object('id',a.id,'command_id',c.command_id,'actor_id',a.actor_id,'created_at',a.created_at,
   'action',c.request->>'action','title',coalesce(a.after_state->'entry'->>'title',nullif(c.request->>'title',''),'登録項目'),
   'sign',coalesce(a.after_state->'entry'->>'sign',c.request->>'sign'),
   'amount_yen',coalesce(a.after_state->'entry'->'amount_yen',nullif(c.request->'amount_yen','null'::jsonb)),
   'recurrence',coalesce(a.after_state->'entry'->>'recurrence',c.request->>'recurrence'),
   'calculation_mode',coalesce(a.after_state->'entry'->>'calculation_mode',c.request->>'calculation_mode'),
   'before_total_yen',(a.before_state->>'total')::bigint,'after_total_yen',(a.after_state->>'total')::bigint,
   'changed_months',jsonb_build_array(c.request->>'month')||coalesce((select jsonb_agg(x->'month') from jsonb_array_elements(coalesce(a.after_state->'future_drafts','[]')) x),'[]')) value
  from document_adjustment_private.audit a join document_adjustment_private.commands c on c.command_id=a.command_id and c.company_id=a.company_id
  where a.company_id=p_company_id and c.request->>'kind'=p_kind and c.request->>'party_id'=p_party_id::text
   and c.request->>'month'=p_month::text and (p_before_id is null or a.id<p_before_id)
  order by a.id desc limit 100
 ) e;
 select exists(select 1 from document_adjustment_private.audit a join document_adjustment_private.commands c on c.command_id=a.command_id and c.company_id=a.company_id
  where a.company_id=p_company_id and c.request->>'kind'=p_kind and c.request->>'party_id'=p_party_id::text
   and c.request->>'month'=p_month::text and a.id<oldest) into more;
 return jsonb_build_object('company_id',p_company_id,'kind',p_kind,'party_id',p_party_id,'month',p_month,'entries',rows,'has_more',more);
end $body$;
revoke all on function public.read_trade_document_adjustment_history(uuid,text,uuid,date,bigint) from public,anon,service_role;
grant execute on function public.read_trade_document_adjustment_history(uuid,text,uuid,date,bigint) to authenticated;

commit;
