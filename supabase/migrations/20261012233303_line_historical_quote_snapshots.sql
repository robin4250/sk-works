begin;
set local lock_timeout='5s';
-- Historical review snapshots are separate from live invoice/payroll settings.
create table private.line_historical_quote_snapshots (
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null, group_id uuid not null,
 work_month date not null check(extract(day from work_month)=1),
 draft_id uuid not null references private.line_import_drafts(id),
 draft_revision integer not null, source_fingerprint text not null,
 actor_id uuid not null references auth.users(id), command_id uuid not null,
 input_rates jsonb not null, snapshot jsonb not null,
 created_at timestamptz not null default now(),
 unique(company_id,actor_id,command_id)
);
alter table private.line_historical_quote_snapshots enable row level security;
revoke all on private.line_historical_quote_snapshots from public,anon,authenticated;

create function private.line_historical_quote_access(p_group_id uuid) returns uuid
language plpgsql stable security definer set search_path='' as $$
declare access jsonb;
begin
 if auth.uid() is null or not private.account_access_allowed() or not public.is_current_user_master_admin() then
  raise exception 'Master access required' using errcode='42501';
 end if;
 access:=private.line_import_access(p_group_id,'invoice');
 if not (access->>'can_edit')::boolean then raise exception 'Invoice management required' using errcode='42501';end if;
 return (access->>'company_id')::uuid;
end $$;
revoke all on function private.line_historical_quote_access(uuid) from public,anon,authenticated,service_role;

create function private.line_historical_quote_workspace(p_group_id uuid,p_month date) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare cid uuid; d private.line_import_drafts; saved jsonb;
begin
 cid:=private.line_historical_quote_access(p_group_id);
 if p_month is null or extract(day from p_month)<>1 or p_month>=date_trunc('month',now() at time zone 'Asia/Tokyo')::date then
  raise exception 'Select a past month' using errcode='22023';end if;
 select * into d from private.line_import_drafts where company_id=cid and group_id=p_group_id and target='invoice' and work_month=p_month and confirmed;
 select coalesce(jsonb_agg(jsonb_build_object('id',q.id,'created_at',q.created_at,'snapshot',q.snapshot) order by q.created_at desc,q.id),'[]') into saved
 from private.line_historical_quote_snapshots q where q.company_id=cid and q.group_id=p_group_id and q.work_month=p_month;
 return jsonb_build_object('draft_id',d.id,'revision',d.revision,'month',p_month,
 'fingerprint',case when d.id is not null then md5(jsonb_build_object('rows',d.candidate_rows,'sources',d.source_messages,'revision',d.revision)::text) end,
 'rows',coalesce(d.candidate_rows,'[]'),'saved',saved,'is_historical_review',true);
end $$;

create function private.save_line_historical_quote(p_command_id uuid,p_group_id uuid,p_month date,p_draft_id uuid,p_revision integer,p_fingerprint text,p_rates jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare cid uuid; d private.line_import_drafts; old private.line_historical_quote_snapshots;
 r record; source jsonb; rates jsonb; allowance record; amount numeric; subtotal numeric:=0; lines jsonb:='[]'; fingerprint text; result jsonb; saved_id uuid;
begin
 cid:=private.line_historical_quote_access(p_group_id);
 if p_command_id is null or p_draft_id is null or p_revision is null or nullif(p_fingerprint,'') is null or p_month is null or extract(day from p_month)<>1 or p_month>=date_trunc('month',now() at time zone 'Asia/Tokyo')::date then raise exception 'Invalid historical scope' using errcode='22023';end if;
 perform pg_advisory_xact_lock(hashtextextended('line-historical-command:'||cid::text||auth.uid()::text||p_command_id::text,0));
 select * into old from private.line_historical_quote_snapshots where company_id=cid and actor_id=auth.uid() and command_id=p_command_id;
 if found then
  if (old.group_id,old.work_month,old.draft_id,old.draft_revision,old.source_fingerprint,old.input_rates) is distinct from (p_group_id,p_month,p_draft_id,p_revision,p_fingerprint,p_rates) then raise exception 'Command content changed' using errcode='22023';end if;
  return jsonb_build_object('id',old.id,'snapshot',old.snapshot);
 end if;
 select * into d from private.line_import_drafts where id=p_draft_id and company_id=cid and group_id=p_group_id and target='invoice' and work_month=p_month for share;
 if d.id is null or not d.confirmed or nullif(trim(d.note_comparison),'') is null or d.revision<>p_revision then raise exception 'Reconfirm saved invoice candidates' using errcode='40001';end if;
 fingerprint:=md5(jsonb_build_object('rows',d.candidate_rows,'sources',d.source_messages,'revision',d.revision)::text);
 if fingerprint is distinct from p_fingerprint then raise exception 'Source changed' using errcode='40001';end if;
 for source in select value from jsonb_array_elements(d.source_messages) loop
  if (d.source_kind='received' or source->>'source_type'='received') and not exists(select 1 from public.chat_messages m where m.id::text=source->>'id' and m.company_id=cid and m.communication_group_id=p_group_id and m.origin='line' and m.body=source->>'body' and m.sent_at=(source->>'sent_at')::timestamptz for share) then raise exception 'Received source changed' using errcode='40001';end if;
 end loop;
 if exists(select 1 from jsonb_array_elements(d.candidate_rows) x where coalesce(x->>'excluded','false')<>'true' group by x->>'row_id' having count(*)>1) then raise exception 'Duplicate candidate row' using errcode='22023';end if;
 if p_rates is null or jsonb_typeof(p_rates)<>'array' or jsonb_array_length(p_rates)>1000 then raise exception 'Rates required' using errcode='22023';end if;
 if not exists(select 1 from jsonb_array_elements(d.candidate_rows) x where coalesce(x->>'excluded','false')<>'true') or exists(select 1 from jsonb_array_elements(d.candidate_rows) x where coalesce(x->>'excluded','false')<>'true' and (x->>'confirmed' is distinct from 'true' or nullif(x->>'worker_id','') is null or nullif(x->>'site_id','') is null or x->>'work_date' is null or (x->>'work_date')::date< p_month or (x->>'work_date')::date>=p_month+interval '1 month' or x->>'man_days' is null or x->>'overtime_hours' is null or x->>'early_hours' is null or jsonb_typeof(x->'allowance_names') is distinct from 'array' or nullif(x->>'row_id','') is null or x->>'work_category' is null or x->>'work_category' not in ('day','night','holiday','holiday_night') or jsonb_typeof(x->'man_days') is distinct from 'number' or jsonb_typeof(x->'overtime_hours') is distinct from 'number' or jsonb_typeof(x->'early_hours') is distinct from 'number' or (x->>'man_days')::numeric not in (0.5,1) or (x->>'overtime_hours')::numeric not between 0 and 24 or (x->>'early_hours')::numeric not between 0 and 24)) then raise exception 'Confirmed quantities required' using errcode='22023';end if;
 for r in select x->>'site_id' site_id,coalesce(x->>'work_category','day') category,count(distinct x->>'worker_id') people,sum((x->>'man_days')::numeric) man_days,sum((x->>'overtime_hours')::numeric) overtime,sum((x->>'early_hours')::numeric) early from jsonb_array_elements(d.candidate_rows) x where coalesce(x->>'excluded','false')<>'true' group by 1,2 order by 1,2 loop
  if r.man_days<0 or r.overtime<0 or r.early<0 then raise exception 'Invalid quantities' using errcode='22023';end if;
  if (select count(*) from jsonb_array_elements(p_rates) x where x->>'site_id'=r.site_id and x->>'work_category'=r.category)<>1 then raise exception 'One explicit rate per site and category required' using errcode='22023';end if;
  select x into rates from jsonb_array_elements(p_rates) x where x->>'site_id'=r.site_id and x->>'work_category'=r.category;
  if rates->>'day' is null or (r.overtime>0 and rates->>'overtime' is null) or (r.early>0 and rates->>'early' is null) then raise exception 'Missing unit rate' using errcode='22023';end if;
  if exists(select 1 from jsonb_each(rates) x where x.key in ('day','overtime','early') and x.value<>'null'::jsonb and (jsonb_typeof(x.value)<>'number' or x.value::text::numeric<0 or x.value::text::numeric>100000000 or x.value::text::numeric<>trunc(x.value::text::numeric))) then raise exception 'Invalid unit rate' using errcode='22023';end if;
  amount:=round(r.man_days*(rates->>'day')::numeric)+round(r.overtime*coalesce((rates->>'overtime')::numeric,0))+round(r.early*coalesce((rates->>'early')::numeric,0));
  for allowance in select name,count(*) quantity from (select distinct x->>'row_id' row_id,n.name from jsonb_array_elements(d.candidate_rows) x cross join lateral jsonb_array_elements_text(x->'allowance_names') n(name) where coalesce(x->>'excluded','false')<>'true' and x->>'site_id'=r.site_id and coalesce(x->>'work_category','day')=r.category) names group by name loop
   if jsonb_typeof(rates->'allowances'->allowance.name) is distinct from 'number' or (rates->'allowances'->>allowance.name)::numeric<0 or (rates->'allowances'->>allowance.name)::numeric>100000000 or (rates->'allowances'->>allowance.name)::numeric<>trunc((rates->'allowances'->>allowance.name)::numeric) then raise exception 'Explicit allowance rate required' using errcode='22023';end if;
   amount:=amount+allowance.quantity*(rates->'allowances'->>allowance.name)::numeric;
  end loop;
  subtotal:=subtotal+amount;
  lines:=lines||jsonb_build_array(jsonb_build_object('site_id',r.site_id,'work_category',r.category,'people',r.people,'man_days',r.man_days,'overtime_hours',r.overtime,'early_hours',r.early,'rates',rates,'subtotal',amount));
 end loop;
 result:=jsonb_build_object('month',p_month,'source_draft_id',d.id,'source_revision',d.revision,'source_fingerprint',fingerprint,'rows',d.candidate_rows,'source_messages',d.source_messages,'lines',lines,'subtotal',subtotal,'people',(select count(distinct x->>'worker_id') from jsonb_array_elements(d.candidate_rows) x where coalesce(x->>'excluded','false')<>'true'),'man_days',(select sum((x->>'man_days')::numeric) from jsonb_array_elements(d.candidate_rows) x where coalesce(x->>'excluded','false')<>'true'),'is_historical_review',true,'invoice_created',false,'tax_and_welfare_applied',false);
 insert into private.line_historical_quote_snapshots(company_id,group_id,work_month,draft_id,draft_revision,source_fingerprint,actor_id,command_id,input_rates,snapshot) values(cid,p_group_id,p_month,d.id,d.revision,fingerprint,auth.uid(),p_command_id,p_rates,result) returning id into saved_id;
 return jsonb_build_object('id',saved_id,'snapshot',result);
end $$;
create function public.line_historical_quote_workspace(p_group_id uuid,p_month date) returns jsonb language sql stable security invoker set search_path='' as $$select private.line_historical_quote_workspace(p_group_id,p_month)$$;
create function public.save_line_historical_quote(p_command_id uuid,p_group_id uuid,p_month date,p_draft_id uuid,p_revision integer,p_fingerprint text,p_rates jsonb) returns jsonb language sql security invoker set search_path='' as $$select private.save_line_historical_quote(p_command_id,p_group_id,p_month,p_draft_id,p_revision,p_fingerprint,p_rates)$$;
revoke all on function private.line_historical_quote_workspace(uuid,date),private.save_line_historical_quote(uuid,uuid,date,uuid,integer,text,jsonb),public.line_historical_quote_workspace(uuid,date),public.save_line_historical_quote(uuid,uuid,date,uuid,integer,text,jsonb) from public,anon;
grant execute on function private.line_historical_quote_workspace(uuid,date),private.save_line_historical_quote(uuid,uuid,date,uuid,integer,text,jsonb),public.line_historical_quote_workspace(uuid,date),public.save_line_historical_quote(uuid,uuid,date,uuid,integer,text,jsonb) to authenticated;
commit;
