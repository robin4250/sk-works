-- LINE stage two is isolated from payroll, existing approval code and chat RLS.
begin;
set local lock_timeout='5s';
create table private.line_import_feature_settings (
 target text primary key check(target in ('attendance','invoice')),
 enabled boolean not null default false,
 updated_at timestamptz not null default now(),
 updated_by uuid references auth.users(id) on delete set null
);
insert into private.line_import_feature_settings(target) values('attendance'),('invoice');
alter table private.line_import_feature_settings enable row level security;
revoke all on private.line_import_feature_settings from public,anon,authenticated;
create table private.line_import_drafts (
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null references public.companies(id) on delete cascade,
 group_id uuid not null references public.communication_groups(id) on delete cascade,
 target text not null check(target in ('attendance','invoice')),
 work_month date not null check(extract(day from work_month)=1),
 revision integer not null default 1 check(revision>0),
 source_kind text not null check(source_kind in ('received','history','mixed')),
 source_messages jsonb not null check(jsonb_typeof(source_messages)='array'),
 candidate_rows jsonb not null check(jsonb_typeof(candidate_rows)='array'),
 note_comparison text not null default '',
 confirmed boolean not null default false,
 updated_at timestamptz not null default now(),
 updated_by uuid not null references auth.users(id),
 unique(company_id,group_id,target,work_month)
);
create table private.line_import_commands (
 company_id uuid not null references public.companies(id) on delete cascade,
 actor_id uuid not null references auth.users(id),
 command_id uuid not null,
 payload jsonb not null,
 result jsonb not null,
 primary key(company_id,actor_id,command_id)
);
alter table private.line_import_drafts enable row level security;
alter table private.line_import_commands enable row level security;
revoke all on private.line_import_drafts,private.line_import_commands from public,anon,authenticated;

create function private.line_import_features() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null or not private.account_access_allowed() then raise exception 'authentication required' using errcode='42501';end if;
 return jsonb_build_object('attendance',coalesce((select enabled from private.line_import_feature_settings where target='attendance'),false),
 'invoice',coalesce((select enabled from private.line_import_feature_settings where target='invoice'),false));
end $$;
create function private.set_line_import_feature(p_target text,p_enabled boolean) returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or not private.account_access_allowed() or not public.is_current_user_master_admin() then raise exception 'master administrator required' using errcode='42501';end if;
 if p_target is null or p_target is null or p_target not in ('attendance','invoice') or p_enabled is null then raise exception 'invalid LINE feature' using errcode='22023';end if;
 update private.line_import_feature_settings set enabled=p_enabled,updated_at=now(),updated_by=auth.uid() where target=p_target;
 return private.line_import_features();
end $$;
create function private.line_import_access(p_group_id uuid,p_target text) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare cid uuid; uid uuid:=auth.uid(); can_edit boolean; management boolean;
begin
 if uid is null or not private.account_access_allowed() or p_target is null or p_target not in ('attendance','invoice') or not private.can_access_communication_group(p_group_id) then raise exception 'LINE workspace unavailable' using errcode='42501';end if;
 select company_id into cid from public.communication_groups where id=p_group_id;
 if cid is null or not exists(select 1 from public.company_members where company_id=cid and user_id=uid) then raise exception 'company membership required' using errcode='42501';end if;
 management:=exists(select 1 from public.company_members where company_id=cid and user_id=uid and role::text in ('owner','admin','manager'));
 if p_target='invoice' and (not management or not private.has_company_feature(cid,'can_view_invoices')) then raise exception 'invoice management access required' using errcode='42501';end if;
 can_edit:=case when p_target='attendance' then public.can_manage_attendance_corrections(cid) else management and private.has_company_feature(cid,'can_manage_invoices') end;
 return jsonb_build_object('company_id',cid,'can_edit',can_edit,'management',management);
end $$;
create function private.line_import_workspace(p_group_id uuid,p_target text,p_month date) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare access jsonb; draft private.line_import_drafts; visible_rows jsonb;
begin
 access:=private.line_import_access(p_group_id,p_target);
 if p_month is null or extract(day from p_month)<>1 then raise exception 'month must start on day one' using errcode='22023';end if;
 select * into draft from private.line_import_drafts where company_id=(access->>'company_id')::uuid and group_id=p_group_id and target=p_target and work_month=p_month;
 visible_rows:=coalesce(draft.candidate_rows,'[]');
 if not (access->>'can_edit')::boolean then
   select coalesce(jsonb_agg(row),'[]') into visible_rows from jsonb_array_elements(visible_rows) row
   where row->>'confirmed'='true' and coalesce(row->>'excluded','false')<>'true' and exists(select 1 from public.workers w where w.id=nullif(row->>'worker_id','')::uuid and w.company_id=(access->>'company_id')::uuid and w.user_id=auth.uid());
 end if;
 return jsonb_build_object('features',private.line_import_features(),'can_edit',(access->>'can_edit')::boolean,'draft_id',draft.id,'revision',coalesce(draft.revision,0),
 'source_kind',coalesce(draft.source_kind,'received'),'source_messages',case when (access->>'can_edit')::boolean then coalesce(draft.source_messages,'[]') else '[]'::jsonb end,
 'candidate_rows',visible_rows,'note_comparison',case when (access->>'can_edit')::boolean then coalesce(draft.note_comparison,'') else '' end,'confirmed',coalesce(draft.confirmed,false));
end $$;
create function private.save_line_import_draft(p_command_id uuid,p_group_id uuid,p_target text,p_month date,p_expected_revision integer,p_source_kind text,p_sources jsonb,p_rows jsonb,p_note text,p_confirmed boolean)
returns jsonb language plpgsql security definer set search_path='' as $$
declare access jsonb; cid uuid; uid uuid:=auth.uid(); payload jsonb; receipt private.line_import_commands; draft private.line_import_drafts; row jsonb; source jsonb; wid uuid; sid uuid; d date; answer jsonb;
begin
 access:=private.line_import_access(p_group_id,p_target);cid:=(access->>'company_id')::uuid;
 if not (access->>'can_edit')::boolean then raise exception 'LINE import edit access required' using errcode='42501';end if;
 payload:=jsonb_build_object('group',p_group_id,'target',p_target,'month',p_month,'revision',p_expected_revision,'kind',p_source_kind,'sources',p_sources,'rows',p_rows,'note',p_note,'confirmed',p_confirmed);
 if p_command_id is null then raise exception 'command id required' using errcode='22023';end if;
 perform pg_advisory_xact_lock(hashtextextended('line-import-command:'||cid::text||uid::text||p_command_id::text,0));
 select * into receipt from private.line_import_commands where company_id=cid and actor_id=uid and command_id=p_command_id;
 if found then if receipt.payload is distinct from payload then raise exception 'command reused with different content' using errcode='22023';end if;return receipt.result;end if;
 perform 1 from private.line_import_feature_settings where target=p_target for share;
 if not coalesce((select enabled from private.line_import_feature_settings where target=p_target),false) then raise exception 'LINE import feature disabled' using errcode='42501';end if;
 if p_month is null or extract(day from p_month)<>1 or p_source_kind is null or p_source_kind not in ('received','history','mixed') or p_expected_revision is null or p_expected_revision<0 or p_confirmed is null
  or p_sources is null or jsonb_typeof(p_sources)<>'array' or jsonb_array_length(p_sources)>10000 or p_rows is null or jsonb_typeof(p_rows)<>'array' or jsonb_array_length(p_rows)>10000 or length(coalesce(p_note,''))>100000 then raise exception 'invalid LINE import draft' using errcode='22023';end if;
 if exists(select 1 from jsonb_array_elements(p_sources) s group by s->>'id' having count(*)>1) then raise exception 'duplicate source id' using errcode='22023';end if;
 if p_confirmed and nullif(trim(p_note),'') is null then raise exception 'LINE note comparison required' using errcode='22023';end if;
 if p_confirmed and not exists(select 1 from jsonb_array_elements(p_rows) r where coalesce(r->>'excluded','false')<>'true') then raise exception 'no included candidates' using errcode='22023';end if;
 if exists(select 1 from jsonb_array_elements(p_rows) r group by r->>'row_id' having count(*)>1) then raise exception 'duplicate candidate row id' using errcode='22023';end if;
 for source in select value from jsonb_array_elements(p_sources) loop
  if jsonb_typeof(source)<>'object' or nullif(source->>'id','') is null or jsonb_typeof(source->'body') is distinct from 'string' or length(source->>'body')>100000 then raise exception 'invalid source message' using errcode='22023';end if;
  if coalesce(source->>'source_type',case when p_source_kind='received' then 'received' else 'history' end) not in ('received','history') then raise exception 'invalid source kind' using errcode='22023';end if;
  if (p_source_kind='received' or source->>'source_type'='received') and not exists(select 1 from public.chat_messages m where m.id::text=source->>'id' and m.company_id=cid and m.communication_group_id=p_group_id and m.origin='line' and m.body=source->>'body' and m.sent_at=(source->>'sent_at')::timestamptz) then raise exception 'source message changed; reread LINE talk' using errcode='40001';end if;
 end loop;
 for row in select value from jsonb_array_elements(p_rows) loop
  if jsonb_typeof(row)<>'object' or nullif(row->>'row_id','') is null or not exists(select 1 from jsonb_array_elements(p_sources) s where s->>'id'=row->>'source_message_id') then raise exception 'candidate source missing' using errcode='22023';end if;
  d:=(row->>'work_date')::date;
  if d is null or date_trunc('month',d)::date<>p_month then raise exception 'candidate outside requested month' using errcode='22023';end if;
  if row->>'confirmed'='true' and coalesce(row->>'excluded','false')<>'true' then
   if coalesce(row->>'work_category',case when row->>'night_work'='true' then 'night' else 'day' end) not in ('day','night','holiday','holiday_night') or jsonb_typeof(coalesce(row->'allowance_names','[]'))<>'array' or exists(select 1 from jsonb_array_elements(coalesce(row->'allowance_names','[]')) a where jsonb_typeof(a)<>'string' or nullif(trim(a#>>'{}'),'') is null) then raise exception 'confirm work category and allowance names' using errcode='22023';end if;
   wid:=nullif(row->>'worker_id','')::uuid;sid:=nullif(row->>'site_id','')::uuid;
   if not exists(select 1 from public.workers where id=wid and company_id=cid and status='active' and name=row->>'worker_name') or not exists(select 1 from public.sites where id=sid and company_id=cid and name=row->>'site_name') then raise exception 'worker or site identity changed' using errcode='40001';end if;
   if jsonb_typeof(row->'man_days') is distinct from 'number' or (row->>'man_days')::numeric not in (0.5,1) or jsonb_typeof(row->'overtime_hours') is distinct from 'number' or (row->>'overtime_hours')::numeric not between 0 and 24 or jsonb_typeof(row->'early_hours') is distinct from 'number' or (row->>'early_hours')::numeric not between 0 and 24 then raise exception 'confirm work quantities' using errcode='22023';end if;
  elsif p_confirmed and coalesce(row->>'excluded','false')<>'true' then raise exception 'unreviewed candidate remains' using errcode='22023';end if;
 end loop;
 if p_confirmed and exists(select 1 from jsonb_array_elements(p_rows) r where coalesce(r->>'excluded','false')<>'true' group by r->>'work_date',r->>'worker_id',case when p_target='invoice' then r->>'site_id' else '' end having count(*)>1) then raise exception 'resolve duplicate worker day before confirming' using errcode='22023';end if;
 perform pg_advisory_xact_lock(hashtextextended('line-import-draft:'||cid::text||p_group_id::text||p_target||p_month::text,0));
 select * into draft from private.line_import_drafts where company_id=cid and group_id=p_group_id and target=p_target and work_month=p_month for update;
 if coalesce(draft.revision,0)<>p_expected_revision then raise exception 'LINE draft changed; reload before editing' using errcode='40001';end if;
 insert into private.line_import_drafts(company_id,group_id,target,work_month,source_kind,source_messages,candidate_rows,note_comparison,confirmed,updated_by)
 values(cid,p_group_id,p_target,p_month,p_source_kind,p_sources,p_rows,coalesce(p_note,''),p_confirmed,uid)
 on conflict(company_id,group_id,target,work_month) do update set revision=private.line_import_drafts.revision+1,source_kind=excluded.source_kind,source_messages=excluded.source_messages,candidate_rows=excluded.candidate_rows,note_comparison=excluded.note_comparison,confirmed=excluded.confirmed,updated_by=uid,updated_at=now();
 answer:=private.line_import_workspace(p_group_id,p_target,p_month);
 insert into private.line_import_commands values(cid,uid,p_command_id,payload,answer);
 return answer;
end $$;
do $line_rate_preflight$ begin
 if md5(split_part(split_part((select prosrc from pg_proc where oid='private.refresh_automatic_invoice(uuid,uuid,date)'::regprocedure),'  select greatest(coalesce(c.tax_rate,0),0)',2),'  route_parts:=',1)) is distinct from 'fdd3b8665142acd2d8c44c20420efe4a' then
  raise exception 'General invoice rate calculation changed; review LINE quote alignment before applying';
 end if;
end $line_rate_preflight$;
-- Use the current general invoice calculation contract and common rate helpers.
-- Inputs are confirmed LINE evidence, never fabricated attendance/route reports.
create function private.line_confirmed_invoice_components(cid uuid,customer uuid,day date,p_rows jsonb)
returns jsonb language plpgsql security definer set search_path='' as $line_components$
declare
  first_day date:=date_trunc('month',day)::date;
  last_day date:=(date_trunc('month',day)+interval '1 month - 1 day')::date;
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
      and exists(
        select 1
        from jsonb_to_recordset(p_rows) as e(company_id uuid,site_id uuid,work_date date,work_category text,base_man_days numeric,overtime_hours numeric,early_hours numeric,allowance_names text[])
        where e.site_id=st.id
          and e.company_id=cid
          and e.work_date between first_day and last_day
      )
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
    from jsonb_to_recordset(p_rows) as e(company_id uuid,site_id uuid,work_date date,work_category text,base_man_days numeric,overtime_hours numeric,early_hours numeric,allowance_names text[])
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

    if unit_rate<=0 and coalesce((s.billing_rate_overrides->>'daily')::numeric,0)<=0 then raise exception '現場の請求単価を確認してください。' using errcode='22023';end if;
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
      from jsonb_to_recordset(p_rows) as e(company_id uuid,site_id uuid,work_date date,work_category text,base_man_days numeric,overtime_hours numeric,early_hours numeric,allowance_names text[])
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
      from jsonb_to_recordset(p_rows) as e(company_id uuid,site_id uuid,work_date date,work_category text,base_man_days numeric,overtime_hours numeric,early_hours numeric,allowance_names text[]),
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

 return jsonb_build_object('sites',sites_json,'subtotal',total_pre_tax,'tax',total_tax,'welfare',total_welfare,'grand_total',total_pre_tax+total_tax,'tax_rate_bps',v_tax_rate*100);
end $line_components$;
revoke all on function private.line_confirmed_invoice_components(uuid,uuid,date,jsonb) from public,anon,authenticated,service_role;

create table private.line_attendance_submissions (
 company_id uuid not null,worker_id uuid not null,work_date date not null,
 draft_id uuid not null references private.line_import_drafts(id),revision integer not null,
 request_id uuid not null references public.attendance_correction_requests(id),
 active boolean not null default true,
 primary key(company_id,worker_id,work_date,request_id)
);
create unique index line_attendance_one_active_day on private.line_attendance_submissions(company_id,worker_id,work_date) where active;
create table private.line_invoice_submissions (
 company_id uuid not null,customer_id uuid not null,work_month date not null,
 draft_id uuid not null references private.line_import_drafts(id),revision integer not null,
 invoice_id uuid not null references public.invoices(id),
 primary key(company_id,customer_id,work_month)
);
alter table private.line_attendance_submissions enable row level security;
alter table private.line_invoice_submissions enable row level security;
revoke all on private.line_attendance_submissions,private.line_invoice_submissions from public,anon,authenticated;
-- Scope these input guards only to days already enrolled by LINE. Ordinary
-- payroll, correction amounts and all non-LINE worker days keep their contract.
create function private.guard_line_enrolled_attendance_day() returns trigger language plpgsql security definer set search_path='' as $$
declare cid uuid;wid uuid;day date;request public.attendance_correction_requests;
begin
 if tg_table_name='attendance_correction_items' then
  select * into request from public.attendance_correction_requests where id=new.request_id;
  if request.request_kind<>'past_attendance' then return new;end if;
  cid:=request.company_id;wid:=nullif(new.proposed_snapshot->>'workerId','')::uuid;day:=replace(new.proposed_snapshot->>'date','/','-')::date;
  if exists(select 1 from private.line_attendance_submissions sub join public.attendance_correction_requests req on req.id=sub.request_id
   where sub.company_id=cid and sub.worker_id=wid and sub.work_date=day and sub.active and req.status in ('submitted','approved') and sub.request_id<>request.id) then
   raise exception 'LINEから同日の出勤を申請済みです。既存の申請または勤務修正を確認してください。' using errcode='22023';
  end if;
  return new;
 end if;
 cid:=new.company_id;wid:=new.worker_id;day:=new.work_date;
 if tg_op='UPDATE' and (new.company_id,new.worker_id,new.work_date) is not distinct from (old.company_id,old.worker_id,old.work_date) then return new;end if;
 if not exists(select 1 from private.line_attendance_submissions sub join public.attendance_correction_requests req on req.id=sub.request_id
   where sub.company_id=cid and sub.worker_id=wid and sub.work_date=day and sub.active and req.status in ('submitted','approved')) then return new;end if;
 if not pg_try_advisory_xact_lock(hashtextextended('line-attendance-day:'||cid::text||wid::text||day::text,0)) then raise exception '同日の出勤登録を処理中です。再確認してください。' using errcode='40001';end if;
 if exists(select 1 from public.attendance_entries where company_id=cid and worker_id=wid and work_date=day and id is distinct from new.id) then
  raise exception 'LINE取込日の出勤は登録済みです。勤務修正から確認してください。' using errcode='22023';
 end if;
 return new;
end $$;
revoke all on function private.guard_line_enrolled_attendance_day() from public,anon,authenticated,service_role;
create trigger line_enrolled_past_request_guard before insert on public.attendance_correction_items for each row execute function private.guard_line_enrolled_attendance_day();
create trigger line_enrolled_attendance_day_guard before insert or update of company_id,worker_id,work_date on public.attendance_entries for each row execute function private.guard_line_enrolled_attendance_day();

create function private.require_current_line_import_draft(p_draft_id uuid,p_revision integer,p_target text) returns private.line_import_drafts
language plpgsql security definer set search_path='' as $$
declare draft private.line_import_drafts; access jsonb; source jsonb; r jsonb;
begin
 select * into draft from private.line_import_drafts where id=p_draft_id for update;
 if draft.id is null or draft.target<>p_target then raise exception 'LINE確認データが見つかりません。' using errcode='22023';end if;
 access:=private.line_import_access(draft.group_id,p_target);
 if not (access->>'can_edit')::boolean then raise exception 'LINE登録権限がありません。' using errcode='42501';end if;
 perform 1 from private.line_import_feature_settings where target=p_target for share;
 if not coalesce((select enabled from private.line_import_feature_settings where target=p_target),false) then raise exception 'LINE追加機能はOFFです。' using errcode='42501';end if;
 if draft.revision<>p_revision or not draft.confirmed or nullif(trim(draft.note_comparison),'') is null then raise exception 'LINE確認データを保存し直してください。' using errcode='40001';end if;
 if draft.source_kind in ('received','mixed') then
  for source in select value from jsonb_array_elements(draft.source_messages) loop
   if (draft.source_kind='received' or source->>'source_type'='received') and not exists(select 1 from public.chat_messages m where m.id::text=source->>'id' and m.company_id=draft.company_id and m.communication_group_id=draft.group_id and m.origin='line' and m.body=source->>'body' and m.sent_at=(source->>'sent_at')::timestamptz) then raise exception '元のLINE投稿が変わりました。再取込してください。' using errcode='40001';end if;
  end loop;
 end if;
 for r in select value from jsonb_array_elements(draft.candidate_rows) where coalesce(value->>'excluded','false')<>'true' loop
  if (r->>'work_date')::date > (now() at time zone 'Asia/Tokyo')::date then raise exception '未来の作業は確認して登録できません。' using errcode='22023';end if;
  if not exists(select 1 from public.workers w where w.id=(r->>'worker_id')::uuid and w.company_id=draft.company_id and w.name=r->>'worker_name' and w.status='active')
  or not exists(select 1 from public.sites s where s.id=(r->>'site_id')::uuid and s.company_id=draft.company_id and s.name=r->>'site_name') then raise exception '作業員・現場の登録情報を確認してください。' using errcode='40001';end if;
 end loop;
 return draft;
end $$;
revoke all on function private.require_current_line_import_draft(uuid,integer,text) from public,anon,authenticated,service_role;

create function private.line_invoice_preview(p_draft_id uuid,p_revision integer) returns jsonb language plpgsql security definer set search_path='' as $$
declare draft private.line_import_drafts; rows jsonb; customer record; quote jsonb; quotes jsonb:='[]'; data jsonb;
begin
 draft:=private.require_current_line_import_draft(p_draft_id,p_revision,'invoice');
 begin lock table public.companies,public.site_financial_settings,public.site_calculation_source_preferences,public.trade_companies,public.trade_company_contracts in share mode nowait;
 exception when lock_not_available then raise exception '請求設定を変更中です。再確認してお試しください。' using errcode='40001';end;
 select jsonb_agg(jsonb_build_object('company_id',draft.company_id,'site_id',(r->>'site_id')::uuid,'work_date',(r->>'work_date')::date,
 'work_category',coalesce(r->>'work_category',case when r->>'night_work'='true' then 'night' else 'day' end),
 'base_man_days',(r->>'man_days')::numeric,'overtime_hours',(r->>'overtime_hours')::numeric,'early_hours',(r->>'early_hours')::numeric,
 'allowance_names',coalesce(r->'allowance_names','[]'::jsonb))) into rows
 from jsonb_array_elements(draft.candidate_rows) r where coalesce(r->>'excluded','false')<>'true';
 if rows is null or not exists(select 1 from jsonb_array_elements(rows)) then raise exception '請求の対象がありません。' using errcode='22023';end if;
 if exists(select 1 from jsonb_array_elements(rows) r join public.sites s on s.id=(r->>'site_id')::uuid where s.customer_id is null or not exists(select 1 from public.customers c where c.id=s.customer_id and c.company_id=draft.company_id)) then raise exception '現場の取引会社を設定してください。' using errcode='22023';end if;
 if exists(select 1 from jsonb_array_elements(draft.candidate_rows) r where coalesce(r->>'excluded','false')<>'true' and r->>'steel_allowance'='true' and jsonb_array_length(coalesce(r->'allowance_names','[]'))=0) then raise exception 'PC・鉄骨手当の登録名称を確認してください。' using errcode='22023';end if;
 if exists(select 1 from jsonb_array_elements(draft.candidate_rows) r
  cross join lateral jsonb_array_elements_text(coalesce(r->'allowance_names','[]')) allowance(name)
  left join public.site_financial_settings fs on fs.site_id=(r->>'site_id')::uuid and fs.company_id=draft.company_id
  where coalesce(r->>'excluded','false')<>'true' and (
   (allowance.name=fs.billing_allowance_1_name and fs.billing_allowance_1_amount_yen>0) or
   (allowance.name=fs.billing_allowance_2_name and fs.billing_allowance_2_amount_yen>0) or
   (allowance.name=fs.billing_allowance_3_name and fs.billing_allowance_3_amount_yen>0)
  ) is not true) then raise exception '現場に登録した手当の名称・単価を確認してください。' using errcode='22023';end if;
 for customer in select distinct c.id,c.name,c.billing_address from public.customers c join public.sites s on s.customer_id=c.id and s.company_id=c.company_id
 where c.company_id=draft.company_id and exists(select 1 from jsonb_array_elements(rows) r where (r->>'site_id')::uuid=s.id) order by c.id loop
  quote:=private.line_confirmed_invoice_components(draft.company_id,customer.id,draft.work_month,rows);
  if jsonb_array_length(quote->'sites')=0 then raise exception '請求明細を確認してください。' using errcode='22023';end if;
  quotes:=quotes||jsonb_build_array(quote||jsonb_build_object('customer_id',customer.id,'customer_name',customer.name,'customer_address',coalesce(customer.billing_address,'')));
 end loop;
 data:=jsonb_build_object('draft_id',draft.id,'revision',draft.revision,'work_month',draft.work_month,'quotes',quotes);
 return data||jsonb_build_object('fingerprint',md5(data::text));
end $$;
create function private.create_line_invoices(p_command_id uuid,p_draft_id uuid,p_revision integer,p_expected_fingerprint text) returns jsonb language plpgsql security definer set search_path='' as $$
declare draft private.line_import_drafts; cid uuid; payload jsonb; receipt private.line_import_commands; preview jsonb; quote jsonb; iid uuid; ids jsonb:='[]'; result jsonb; snapshot jsonb;
begin
 select company_id into cid from private.line_import_drafts where id=p_draft_id;
 if cid is null or p_command_id is null then raise exception 'LINE請求データがありません。' using errcode='22023';end if;
 perform private.line_import_access((select group_id from private.line_import_drafts where id=p_draft_id),'invoice');
 payload:=jsonb_build_object('action','invoice','draft',p_draft_id,'revision',p_revision,'fingerprint',p_expected_fingerprint);
 perform pg_advisory_xact_lock(hashtextextended('line-import-command:'||cid::text||auth.uid()::text||p_command_id::text,0));
 select * into receipt from private.line_import_commands where company_id=cid and actor_id=auth.uid() and command_id=p_command_id;
 if found then if receipt.payload is distinct from payload then raise exception 'command reused with different content' using errcode='22023';end if;return receipt.result;end if;
 draft:=private.require_current_line_import_draft(p_draft_id,p_revision,'invoice');
 preview:=private.line_invoice_preview(p_draft_id,p_revision);
 if preview->>'fingerprint' is distinct from p_expected_fingerprint then raise exception '請求単価・税率・確認データが変わりました。金額を再確認してください。' using errcode='40001';end if;
 -- Serialize with every invoice INSERT/UPDATE, including existing manual and automatic inputs.
 -- No existing invoice is ever overwritten by a LINE import.
 for quote in select value from jsonb_array_elements(preview->'quotes') order by value->>'customer_id' loop
  if not pg_try_advisory_xact_lock(hashtextextended('invoice:'||cid::text||(quote->>'customer_id')||draft.work_month::text,0)) then raise exception '別の請求処理中です。再確認してお試しください。' using errcode='40001';end if;
 end loop;
 begin lock table public.invoices in share row exclusive mode nowait;
 exception when lock_not_available then raise exception '別の請求処理中です。再確認してお試しください。' using errcode='40001';end;
 for quote in select value from jsonb_array_elements(preview->'quotes') loop
  if exists(select 1 from public.invoices where company_id=cid and customer_id=(quote->>'customer_id')::uuid and billing_period_start<=((draft.work_month+interval '1 month - 1 day')::date) and billing_period_end>=draft.work_month)
    or exists(select 1 from private.line_invoice_submissions where company_id=cid and customer_id=(quote->>'customer_id')::uuid and work_month=draft.work_month) then raise exception '同じ取引会社・月の請求書があります。既存の請求書を確認してください。' using errcode='22023';end if;
  snapshot:=jsonb_build_object('customer_name',quote->>'customer_name','customer_address',quote->>'customer_address','billing_period',to_char(draft.work_month,'YYYY年MM月'),
   'tax_rate_bps',quote->'tax_rate_bps','subtotal',quote->'subtotal','tax',quote->'tax','grand_total',quote->'grand_total','sites',quote->'sites','detail_mode','consolidated_only',
   'line_import_evidence',jsonb_build_object('draft_id',draft.id,'revision',draft.revision,'source_kind',draft.source_kind,'source_ids',(select jsonb_agg(s->>'id') from jsonb_array_elements(draft.source_messages) s)));
  insert into public.invoices(company_id,customer_id,billing_period_start,billing_period_end,status,subtotal,tax,welfare_amount,adjustments,grand_total,snapshot,detail_mode,automatic_calculation)
  values(cid,(quote->>'customer_id')::uuid,draft.work_month,(draft.work_month+interval '1 month - 1 day')::date,'draft',(quote->>'subtotal')::numeric,(quote->>'tax')::numeric,(quote->>'welfare')::numeric,0,(quote->>'grand_total')::numeric,snapshot,'consolidated_only',false) returning id into iid;
  insert into private.line_invoice_submissions values(cid,(quote->>'customer_id')::uuid,draft.work_month,draft.id,draft.revision,iid);
  ids:=ids||jsonb_build_array(jsonb_build_object('invoice_id',iid,'customer_id',quote->>'customer_id','grand_total',quote->'grand_total'));
 end loop;
 result:=jsonb_build_object('invoices',ids);
 insert into private.line_import_commands values(cid,auth.uid(),p_command_id,payload,result);
 return result;
end $$;
create function private.submit_line_attendance(p_command_id uuid,p_draft_id uuid,p_revision integer,p_signer_name text,p_signature_json jsonb,p_worker_ids uuid[]) returns jsonb language plpgsql security definer set search_path='' as $$
declare draft private.line_import_drafts; cid uuid; payload jsonb; receipt private.line_import_commands; r jsonb; items jsonb:='[]'; request_id uuid; result jsonb;
begin
 select company_id into cid from private.line_import_drafts where id=p_draft_id;
 if cid is null or p_command_id is null then raise exception 'LINE出勤データがありません。' using errcode='22023';end if;
 perform private.line_import_access((select group_id from private.line_import_drafts where id=p_draft_id),'attendance');
 payload:=jsonb_build_object('action','attendance','draft',p_draft_id,'revision',p_revision,'signer',p_signer_name,'signature',p_signature_json,'workers',to_jsonb(p_worker_ids));
 perform pg_advisory_xact_lock(hashtextextended('line-import-command:'||cid::text||auth.uid()::text||p_command_id::text,0));
 select * into receipt from private.line_import_commands where company_id=cid and actor_id=auth.uid() and command_id=p_command_id;
 if found then if receipt.payload is distinct from payload then raise exception 'command reused with different content' using errcode='22023';end if;return receipt.result;end if;
 draft:=private.require_current_line_import_draft(p_draft_id,p_revision,'attendance');
 if p_worker_ids is not null and (cardinality(p_worker_ids)=0 or exists(select 1 from unnest(p_worker_ids) wid where wid is null or not exists(select 1 from jsonb_array_elements(draft.candidate_rows) rr where rr->>'worker_id'=wid::text and coalesce(rr->>'excluded','false')<>'true'))) then raise exception '申請する作業員を確認してください。' using errcode='22023';end if;
 if nullif(trim(p_signer_name),'') is null or p_signature_json is null then raise exception '申請の署名を入力してください。' using errcode='22023';end if;
 -- Existing manual submissions do not take a LINE lock; table locks close the
 -- gap while this wrapper checks duplicates and creates its ordinary request.
 begin lock table public.attendance_correction_requests,public.attendance_entries in share row exclusive mode nowait;
 exception when lock_not_available then raise exception '別の出勤処理中です。再確認してお試しください。' using errcode='40001';end;
 for r in select value from jsonb_array_elements(draft.candidate_rows) where coalesce(value->>'excluded','false')<>'true' and (p_worker_ids is null or (value->>'worker_id')::uuid=any(p_worker_ids)) order by value->>'worker_id',value->>'work_date' loop
  if (r->>'work_date')::date >= (now() at time zone 'Asia/Tokyo')::date then raise exception '過去の日付だけをまとめて申請できます。' using errcode='22023';end if;
  update private.line_attendance_submissions sub set active=false where sub.company_id=cid and sub.worker_id=(r->>'worker_id')::uuid and sub.work_date=(r->>'work_date')::date and sub.active
   and exists(select 1 from public.attendance_correction_requests req where req.id=sub.request_id and req.status='rejected');
  if exists(select 1 from public.attendance_entries where company_id=cid and worker_id=(r->>'worker_id')::uuid and work_date=(r->>'work_date')::date)
   or exists(select 1 from private.line_attendance_submissions where company_id=cid and worker_id=(r->>'worker_id')::uuid and work_date=(r->>'work_date')::date and active)
   or exists(select 1 from public.attendance_correction_items i join public.attendance_correction_requests req on req.id=i.request_id
    where req.company_id=cid and req.request_kind='past_attendance' and req.status in ('draft','submitted') and (i.proposed_snapshot->>'workerId')=(r->>'worker_id') and replace(i.proposed_snapshot->>'date','/','-')=r->>'work_date') then raise exception '同日の出勤または申請があります。勤務修正から確認してください。' using errcode='22023';end if;
  if r->>'steel_allowance'='true' and jsonb_array_length(coalesce(r->'allowance_names','[]'))=0 then raise exception 'PC・鉄骨手当の登録名称を確認してください。' using errcode='22023';end if;
  items:=items||jsonb_build_array(jsonb_build_object('date',r->>'work_date','workerName',r->>'worker_name','siteName',r->>'site_name','manDays',r->'man_days','overtimeHours',r->'overtime_hours','earlyHours',r->'early_hours',
   'workCategory',coalesce(r->>'work_category',case when r->>'night_work'='true' then 'night' else 'day' end),'nightHours',0,'allowanceYen',0,'allowanceNames',coalesce(r->'allowance_names','[]'),
   'notes','LINE確認取込 '||draft.id::text||' / v'||draft.revision::text||' / '||(r->>'source_message_id')));
 end loop;
 if jsonb_array_length(items)<1 or jsonb_array_length(items)>100 then raise exception '1～100件をまとめて申請してください。' using errcode='22023';end if;
 request_id:=public.submit_past_attendance_request(items,p_signer_name,p_signature_json);
 insert into private.line_attendance_submissions(company_id,worker_id,work_date,draft_id,revision,request_id)
 select cid,(item.value->>'worker_id')::uuid,(item.value->>'work_date')::date,draft.id,draft.revision,request_id from jsonb_array_elements(draft.candidate_rows) item where coalesce(item.value->>'excluded','false')<>'true' and (p_worker_ids is null or (item.value->>'worker_id')::uuid=any(p_worker_ids));
 result:=jsonb_build_object('request_id',request_id,'status','submitted','item_count',jsonb_array_length(items));
 insert into private.line_import_commands values(cid,auth.uid(),p_command_id,payload,result);
 return result;
end $$;
create function public.line_invoice_preview(p_draft_id uuid,p_revision integer) returns jsonb language sql security invoker set search_path='' as $$select private.line_invoice_preview(p_draft_id,p_revision)$$;
create function public.create_line_invoices(p_command_id uuid,p_draft_id uuid,p_revision integer,p_expected_fingerprint text) returns jsonb language sql security invoker set search_path='' as $$select private.create_line_invoices(p_command_id,p_draft_id,p_revision,p_expected_fingerprint)$$;
create function public.submit_line_attendance(p_command_id uuid,p_draft_id uuid,p_revision integer,p_signer_name text,p_signature_json jsonb,p_worker_ids uuid[]) returns jsonb language sql security invoker set search_path='' as $$select private.submit_line_attendance(p_command_id,p_draft_id,p_revision,p_signer_name,p_signature_json,p_worker_ids)$$;
revoke all on function private.line_invoice_preview(uuid,integer),private.create_line_invoices(uuid,uuid,integer,text),private.submit_line_attendance(uuid,uuid,integer,text,jsonb,uuid[]) from public,anon;
revoke all on function public.line_invoice_preview(uuid,integer),public.create_line_invoices(uuid,uuid,integer,text),public.submit_line_attendance(uuid,uuid,integer,text,jsonb,uuid[]) from public,anon;
grant execute on function private.line_invoice_preview(uuid,integer),private.create_line_invoices(uuid,uuid,integer,text),private.submit_line_attendance(uuid,uuid,integer,text,jsonb,uuid[]) to authenticated;
grant execute on function public.line_invoice_preview(uuid,integer),public.create_line_invoices(uuid,uuid,integer,text),public.submit_line_attendance(uuid,uuid,integer,text,jsonb,uuid[]) to authenticated;

-- Thin public wrappers keep the existing auth/feature/group predicates authoritative.
create function public.line_import_features() returns jsonb language sql security invoker set search_path='' as $$select private.line_import_features()$$;
create function public.set_line_import_feature(p_target text,p_enabled boolean) returns jsonb language sql security invoker set search_path='' as $$select private.set_line_import_feature(p_target,p_enabled)$$;
create function public.line_import_workspace(p_group_id uuid,p_target text,p_month date) returns jsonb language sql security invoker set search_path='' as $$select private.line_import_workspace(p_group_id,p_target,p_month)$$;
create function public.save_line_import_draft(p_command_id uuid,p_group_id uuid,p_target text,p_month date,p_expected_revision integer,p_source_kind text,p_sources jsonb,p_rows jsonb,p_note text,p_confirmed boolean) returns jsonb language sql security invoker set search_path='' as $$select private.save_line_import_draft(p_command_id,p_group_id,p_target,p_month,p_expected_revision,p_source_kind,p_sources,p_rows,p_note,p_confirmed)$$;
revoke all on function private.line_import_features(),private.set_line_import_feature(text,boolean),private.line_import_access(uuid,text),private.line_import_workspace(uuid,text,date),private.save_line_import_draft(uuid,uuid,text,date,integer,text,jsonb,jsonb,text,boolean) from public,anon;
revoke all on function public.line_import_features(),public.set_line_import_feature(text,boolean),public.line_import_workspace(uuid,text,date),public.save_line_import_draft(uuid,uuid,text,date,integer,text,jsonb,jsonb,text,boolean) from public,anon;
grant usage on schema private to authenticated;
grant execute on function private.line_import_features(),private.set_line_import_feature(text,boolean),private.line_import_workspace(uuid,text,date),private.save_line_import_draft(uuid,uuid,text,date,integer,text,jsonb,jsonb,text,boolean) to authenticated;
grant execute on function public.line_import_features(),public.set_line_import_feature(text,boolean),public.line_import_workspace(uuid,text,date),public.save_line_import_draft(uuid,uuid,text,date,integer,text,jsonb,jsonb,text,boolean) to authenticated;
revoke all on function private.line_import_access(uuid,text) from authenticated,service_role;
commit;
