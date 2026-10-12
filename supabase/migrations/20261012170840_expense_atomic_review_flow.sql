-- Explicit review/settlement values; never infer paid/advance from cash/payroll.
-- Final confirmation is one transaction; previews do not write approval state.
do $$
begin
 if to_regclass('private.expense_review_confirmations') is not null then
  raise exception 'Expense review confirmations already exist; inspect first';
 end if;
 if (select md5(prosrc) from pg_proc where oid='private.expense_approve_with_settlement(uuid,uuid,integer,text,date)'::regprocedure)
    is distinct from '6897a4a0ccce0a89487af4abb4c50312' then
  raise exception 'Expense application-month prerequisite changed';
 end if;
end $$;
lock table private.expense_claims,private.expense_settlement_choices in share row exclusive mode;
alter table private.expense_claims drop constraint expense_claims_allocation_check,
 drop constraint expense_claims_check,
 add constraint expense_claims_allocation_check check(allocation in ('unallocated','ownCompany','subcontractor','customer','other')),
 add constraint expense_claims_check check(
  (allocation in ('subcontractor','customer') and counterparty_id is not null) or
  (allocation in ('unallocated','ownCompany','other') and counterparty_id is null));
alter table private.expense_settlement_choices drop constraint expense_settlement_choices_method_check,
 add constraint expense_settlement_choices_method_check check(method in ('cash','payroll','paid','advance'));
create table private.expense_review_confirmations (
 command_id uuid primary key,claim_id uuid not null references private.expense_claims(id),
 company_id uuid not null,actor_id uuid not null,command jsonb not null,result jsonb not null,
 created_at timestamptz not null default clock_timestamp()
);
alter table private.expense_review_confirmations enable row level security;
revoke all on private.expense_review_confirmations from public,anon,authenticated;
create index expense_review_confirmations_claim on private.expense_review_confirmations(company_id,claim_id,created_at,command_id);
create function private.expense_confirm_review(p_command_id uuid,p_claim uuid,p_revision integer,
 p_action text,p_allocation text,p_counterparty uuid,p_method text,p_memo text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare claim private.expense_claims%rowtype; old private.expense_review_confirmations%rowtype;
 command jsonb:=jsonb_build_object('claim',p_claim,'revision',p_revision,'action',p_action,
  'allocation',p_allocation,'counterparty',p_counterparty,'method',p_method,'memo',p_memo);
 result jsonb; setting private.expense_approval_settings%rowtype;
 party_name text; month date; scope record; previous_context text; reviewed timestamptz:=clock_timestamp();
begin
 select * into claim from private.expense_claims where id=p_claim;
 if not found then raise exception 'expense unavailable' using errcode='42501';end if;
 perform 1 from public.companies where id=claim.company_id for key share;
 select * into setting from private.expense_approval_settings where company_id=claim.company_id for share;
 if not coalesce((private.expense_review_access(claim.company_id)->>'can_review')::boolean,false) then
  raise exception 'selected expense approver required' using errcode='42501';end if;
 select * into claim from private.expense_claims where id=p_claim for update;
 select * into old from private.expense_review_confirmations where command_id=p_command_id;
 if found then
  if old.actor_id is distinct from auth.uid() or old.command is distinct from command then
   raise exception 'fixed expense confirmation differs' using errcode='23505';end if;
  return old.result;
 end if;
 if p_command_id is null or p_action is null or p_action not in ('approve','reject')
  or p_memo is null or length(p_memo)>1000 then
  raise exception 'invalid expense confirmation' using errcode='22023';end if;
 if exists(select 1 from private.expense_claim_events where command_id=p_command_id)
  or exists(select 1 from private.expense_settlement_events where command_id=p_command_id)
  or exists(select 1 from private.expense_cost_allocation_events where command_id=p_command_id) then
  raise exception 'new expense confirmation command required' using errcode='23505';end if;
 if claim.revision is distinct from p_revision then raise exception 'expense changed; reload' using errcode='40001';end if;
 if claim.withdrawn then raise exception 'withdrawn expense unavailable' using errcode='22023';end if;
 if claim.created_by=auth.uid() and cardinality(setting.approver_ids)>1 then
  raise exception 'another selected approver must review own claim' using errcode='42501';end if;
 if p_action='reject' then
  if p_allocation is not null or p_counterparty is not null or p_method is not null then
   raise exception 'rejection has no allocation or settlement' using errcode='22023';end if;
 else
  if not exists(select 1 from public.company_members where company_id=claim.company_id
   and user_id=auth.uid() and role::text in ('owner','admin','manager')) then
   raise exception '振り分けと精算方法は管理者・サブ管理者が設定してください。' using errcode='42501';end if;
  if p_allocation is null or p_allocation not in ('ownCompany','subcontractor','customer','other')
   or p_method is null or p_method not in ('cash','payroll','paid','advance') then
   raise exception '負担先と精算方法を選択してください。' using errcode='22023';end if;
  if p_allocation in ('ownCompany','other') then
   if p_counterparty is not null then raise exception 'company selection not applicable' using errcode='22023';end if;
  elsif p_allocation='customer' then
   select name into party_name from public.customers where id=p_counterparty and company_id=claim.company_id for key share;
   if not found then raise exception 'company customer required' using errcode='42501';end if;
  else
   select name into party_name from public.partner_companies where id=p_counterparty and company_id=claim.company_id for key share;
   if not found then raise exception 'company subcontractor required' using errcode='42501';end if;
  end if;
 end if;
 for scope in select * from (values(claim.company_id,claim.allocation,claim.counterparty_id,claim.incurred_on),
  (claim.company_id,p_allocation,p_counterparty,claim.incurred_on)) x(cid,category,party,day)
  order by cid,category,party,day loop
  perform private.expense_cost_scope_lock(scope.cid,scope.category,scope.party,scope.day);
 end loop;
 if p_action='approve' and (
  (p_allocation='customer' and exists(select 1 from public.invoices where company_id=claim.company_id and customer_id=p_counterparty
   and billing_period_start=date_trunc('month',claim.incurred_on)::date
   and (status<>'draft' or finalized_at is not null or approval_finalized_at is not null or not automatic_calculation)))
  or (p_allocation='subcontractor' and exists(select 1 from public.payment_certificates where company_id=claim.company_id
   and partner_company_id=p_counterparty and period_start=date_trunc('month',claim.incurred_on)::date
   and (status<>'draft' or not automatic_calculation)))) then
  raise exception '対象帳票は確定済みまたは手動編集です。' using errcode='22023';end if;
 month:=date_trunc('month',claim.submitted_at at time zone 'Asia/Tokyo')::date;
 previous_context:=current_setting('sko.expense_cost_allocation',true);
 perform set_config('sko.expense_cost_allocation','1',true);
 if p_action='approve' then
  update private.expense_claims set approval='approved',allocation=p_allocation,
   counterparty_id=p_counterparty,counterparty_name=party_name,revision=revision+1 where id=p_claim;
  insert into private.expense_settlement_choices(claim_id,company_id,method,settlement_month,revision,chosen_by,approval_current,cost_allocation_current)
  values(p_claim,claim.company_id,p_method,month,p_revision+1,auth.uid(),true,p_allocation in ('customer','subcontractor'))
  on conflict(claim_id) do update set method=excluded.method,settlement_month=excluded.settlement_month,
   revision=excluded.revision,chosen_by=excluded.chosen_by,chosen_at=reviewed,approval_current=true,
   cost_allocation_current=excluded.cost_allocation_current;
 else
  update private.expense_claims set approval='rejected',revision=revision+1 where id=p_claim;
 end if;
 perform set_config('sko.expense_cost_allocation',coalesce(previous_context,''),true);
 select to_jsonb(e) into result from private.expense_claims e where id=p_claim;
 result:=result||jsonb_build_object('review_action',p_action,'reviewed_at',reviewed,'reviewed_by',auth.uid(),'reviewed_by_name',(select min(name) from public.workers where company_id=claim.company_id and user_id=auth.uid()),'review_memo',p_memo,
  'settlement_method',case when p_action='approve' then p_method end,
  'settlement_month',case when p_action='approve' then month end,
  'cost_allocation_current',p_action='approve' and p_allocation in ('customer','subcontractor'));
 insert into private.expense_review_confirmations(command_id,claim_id,company_id,actor_id,command,result)
 values(p_command_id,p_claim,claim.company_id,auth.uid(),command,result);
 return result;
end $$;
create function public.expense_confirm_review(p_command_id uuid,p_claim uuid,p_revision integer,
 p_action text,p_allocation text,p_counterparty uuid,p_method text,p_memo text) returns jsonb
language sql security invoker set search_path='' as $$
 select private.expense_confirm_review(p_command_id,p_claim,p_revision,p_action,p_allocation,p_counterparty,p_method,p_memo)
$$;
revoke all on function private.expense_confirm_review(uuid,uuid,integer,text,text,uuid,text,text),
 public.expense_confirm_review(uuid,uuid,integer,text,text,uuid,text,text) from public,anon;
grant execute on function private.expense_confirm_review(uuid,uuid,integer,text,text,uuid,text,text),
 public.expense_confirm_review(uuid,uuid,integer,text,text,uuid,text,text) to authenticated;
create function private.expense_review_flow_workspace(p_company uuid,p_month date) returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb; claims jsonb;
begin
 result:=private.expense_settlement_workspace(p_company,p_month);
 select coalesce(jsonb_agg(x.claim||coalesce((select jsonb_build_object(
  'reviewed_at',r.result->'reviewed_at','reviewed_by',r.actor_id,'reviewed_by_name',r.result->'reviewed_by_name','review_memo',r.result->'review_memo')
  from private.expense_review_confirmations r where r.claim_id=(x.claim->>'id')::uuid and r.company_id=p_company
   and (r.result->>'revision')::integer=(x.claim->>'revision')::integer
  order by r.created_at desc,r.command_id desc limit 1),'{}'::jsonb) order by x.ordinality),'[]') into claims
 from jsonb_array_elements(result->'claims') with ordinality x(claim,ordinality);
 return result||jsonb_build_object('review_flow_enabled',true,'claims',claims);
end $$;
create function public.expense_review_flow_workspace(p_company uuid,p_month date) returns jsonb
language sql security invoker set search_path='' as $$select private.expense_review_flow_workspace(p_company,p_month)$$;
create function private.expense_review_flow_history(p_claim uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare claim private.expense_claims%rowtype;
begin
 select * into claim from private.expense_claims where id=p_claim;
 if not found then raise exception 'expense unavailable' using errcode='42501';end if;
 if not private.account_access_allowed() or auth.uid() is null or not exists(
  select 1 from public.company_members where company_id=claim.company_id and user_id=auth.uid())
  or (claim.created_by is distinct from auth.uid() and not coalesce(
   (private.expense_review_access(claim.company_id)->>'can_review')::boolean,false)) then
  raise exception 'expense history unavailable' using errcode='42501';end if;
 return jsonb_build_object('claim_id',claim.id,'company_id',claim.company_id,'events',(
  select coalesce(jsonb_agg(v order by occurred_at,command_id),'[]') from (
   select jsonb_build_object('command_id',command_id,'actor_id',actor_id,'occurred_at',created_at,
    'command',command,'result',result,'kind','confirmation') v,created_at occurred_at,command_id
    from private.expense_review_confirmations where claim_id=p_claim
   union all select jsonb_build_object('command_id',command_id,'actor_id',actor_id,'occurred_at',created_at,
    'command',command,'result',result,'kind','review'),created_at,command_id from private.expense_claim_events where claim_id=p_claim
   union all select jsonb_build_object('command_id',command_id,'actor_id',actor_id,'occurred_at',created_at,
    'command',command,'result',result,'kind','personal'),created_at,command_id from private.expense_personal_changes where claim_id=p_claim
  ) x));
end $$;
create function public.expense_review_flow_history(p_claim uuid) returns jsonb
language sql security invoker set search_path='' as $$select private.expense_review_flow_history(p_claim)$$;
revoke all on function private.expense_review_flow_workspace(uuid,date),public.expense_review_flow_workspace(uuid,date),
 private.expense_review_flow_history(uuid),public.expense_review_flow_history(uuid) from public,anon;
grant execute on function private.expense_review_flow_workspace(uuid,date),public.expense_review_flow_workspace(uuid,date),
 private.expense_review_flow_history(uuid),public.expense_review_flow_history(uuid) to authenticated;
create function private.expense_review_edit(p_command_id uuid,p_claim uuid,p_revision integer,p_date date,p_description text,p_amount integer)
returns jsonb language plpgsql security definer set search_path='' as $$
declare claim private.expense_claims%rowtype; old private.expense_review_confirmations%rowtype; result jsonb;
 command jsonb:=jsonb_build_object('claim',p_claim,'revision',p_revision,'action','edit','date',p_date,'description',p_description,'amount',p_amount);
begin
 select * into claim from private.expense_claims where id=p_claim;
 if not found then raise exception 'expense unavailable' using errcode='42501';end if;
 perform 1 from public.companies where id=claim.company_id for key share;
 perform 1 from private.expense_approval_settings where company_id=claim.company_id for share;
 if not coalesce((private.expense_review_access(claim.company_id)->>'can_review')::boolean,false)
  or not exists(select 1 from public.company_members where company_id=claim.company_id and user_id=auth.uid() and role::text in ('owner','admin','manager')) then
  raise exception 'manager expense reviewer required' using errcode='42501';end if;
 select * into claim from private.expense_claims where id=p_claim for update;
 select * into old from private.expense_review_confirmations where command_id=p_command_id;
 if found then
  if old.actor_id is distinct from auth.uid() or old.command is distinct from command then raise exception 'fixed expense edit differs' using errcode='23505';end if;
  return old.result;
 end if;
 if p_command_id is null or p_date is null or p_date < date '1900-01-01' or p_date > (clock_timestamp() at time zone 'Asia/Tokyo')::date
  or p_description is null or length(btrim(p_description)) not between 1 and 1000 or p_amount is null or p_amount not between 1 and 999999999 then
  raise exception 'invalid expense edit' using errcode='22023';end if;
 if claim.revision is distinct from p_revision then raise exception 'expense changed; reload' using errcode='40001';end if;
 if claim.withdrawn then raise exception 'withdrawn expense unavailable' using errcode='22023';end if;
 update private.expense_claims set incurred_on=p_date,description=btrim(p_description),amount_yen=p_amount,
  approval='pending',allocation='unallocated',counterparty_id=null,counterparty_name=null,revision=revision+1 where id=p_claim;
 select to_jsonb(e) into result from private.expense_claims e where id=p_claim;
 result:=result||jsonb_build_object('review_action','edit','reviewed_at',clock_timestamp(),'reviewed_by',auth.uid(),'before_row',to_jsonb(claim));
 insert into private.expense_review_confirmations(command_id,claim_id,company_id,actor_id,command,result)
 values(p_command_id,p_claim,claim.company_id,auth.uid(),command,result);
 return result;
end $$;
create function public.expense_review_edit(p_command_id uuid,p_claim uuid,p_revision integer,p_date date,p_description text,p_amount integer)
returns jsonb language sql security invoker set search_path='' as $$select private.expense_review_edit(p_command_id,p_claim,p_revision,p_date,p_description,p_amount)$$;
revoke all on function private.expense_review_edit(uuid,uuid,integer,date,text,integer),public.expense_review_edit(uuid,uuid,integer,date,text,integer) from public,anon;
grant execute on function private.expense_review_edit(uuid,uuid,integer,date,text,integer),public.expense_review_edit(uuid,uuid,integer,date,text,integer) to authenticated;
