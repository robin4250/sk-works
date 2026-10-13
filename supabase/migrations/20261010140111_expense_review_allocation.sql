-- Expense-only approvers; later changes do not alter other approval pages.
create table private.expense_approval_settings (
 company_id uuid primary key, approver_ids uuid[] not null,
 revision integer not null default 1,
 check(cardinality(approver_ids) between 1 and 3)
);
alter table private.expense_approval_settings enable row level security;
revoke all on private.expense_approval_settings from public,anon,authenticated;
insert into private.expense_approval_settings(company_id,approver_ids)
select a.company_id,array_agg(distinct a.user_id order by a.user_id)
from public.company_approval_assignees a join public.company_members m on m.company_id=a.company_id and m.user_id=a.user_id
join public.companies c on c.id=a.company_id
where m.role::text in ('owner','admin','manager','viewer')
group by a.company_id having count(distinct a.user_id) between 1 and 3;
create table private.expense_claim_events (
 command_id uuid primary key, company_id uuid not null, claim_id uuid not null,
 actor_id uuid not null, command jsonb not null, result jsonb not null,
 created_at timestamptz not null default clock_timestamp()
);
alter table private.expense_claim_events enable row level security;
revoke all on private.expense_claim_events from public,anon,authenticated;
create index expense_claim_events_claim on private.expense_claim_events(company_id,claim_id,created_at);

create function private.expense_review_access(p_company uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare role_name text; selected uuid[];
begin
 if auth.uid() is null or not private.account_access_allowed() then raise exception 'account unavailable' using errcode='42501'; end if;
 select m.role::text into role_name from public.company_members m join public.companies c on c.id=m.company_id where m.company_id=p_company and m.user_id=auth.uid();
 if not found then raise exception 'company membership required' using errcode='42501'; end if;
 select approver_ids into selected from private.expense_approval_settings where company_id=p_company;
 return jsonb_build_object('can_configure',role_name in ('owner','admin'),'can_review',role_name in ('owner','admin','manager','viewer') and auth.uid()=any(coalesce(selected,'{}'::uuid[])));
end $$;
create function private.expense_management_companies() returns jsonb
language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or not private.account_access_allowed() then raise exception 'account unavailable' using errcode='42501'; end if;
 return (select coalesce(jsonb_agg(jsonb_build_object('company_id',c.id,'company_name',c.name) order by c.id),'[]'::jsonb)
 from public.companies c join public.company_members m on m.company_id=c.id and m.user_id=auth.uid()
 where m.role::text in ('owner','admin') or exists(select 1 from private.expense_approval_settings s where s.company_id=c.id and auth.uid()=any(s.approver_ids)));
end $$;
create function private.expense_review_workspace(p_company uuid,p_month date) returns jsonb
language plpgsql security definer set search_path='' as $$
declare access jsonb; setting private.expense_approval_settings%rowtype; claims jsonb; choices jsonb; candidates jsonb;
begin
 access:=private.expense_review_access(p_company);
 if p_month is null or not ((access->>'can_configure')::boolean or (access->>'can_review')::boolean) then raise exception 'expense reviewer required' using errcode='42501'; end if;
 select * into setting from private.expense_approval_settings where company_id=p_company;
 select coalesce(jsonb_agg(to_jsonb(e) order by e.incurred_on,e.submitted_at,e.id),'[]'::jsonb) into claims from private.expense_claims e
 where e.company_id=p_company and e.incurred_on>=date_trunc('month',p_month)::date and e.incurred_on<(date_trunc('month',p_month)+interval '1 month')::date;
 select coalesce(jsonb_agg(v order by v->>'category',v->>'name',v->>'id'),'[]'::jsonb) into choices from (
  select jsonb_build_object('category','ownCompany','id',null,'name',null) v
  union all select jsonb_build_object('category','customer','id',id,'name',name) from public.customers where company_id=p_company
  union all select jsonb_build_object('category','subcontractor','id',id,'name',name) from public.partner_companies where company_id=p_company
 ) x;
 if (access->>'can_configure')::boolean then
  select coalesce(jsonb_agg(jsonb_build_object('user_id',m.user_id,'name',coalesce((select min(w.name) from public.workers w where w.company_id=m.company_id and w.user_id=m.user_id),m.user_id::text)) order by m.user_id),'[]'::jsonb)
  into candidates from public.company_members m where m.company_id=p_company and m.role::text in ('owner','admin','manager','viewer');
 end if;
 return access||jsonb_build_object('company_id',p_company,'claims',claims,'destinations',choices,
  'approver_ids',coalesce(setting.approver_ids,'{}'::uuid[]),'settings_revision',coalesce(setting.revision,0),'candidates',coalesce(candidates,'[]'::jsonb));
end $$;
create function private.set_expense_approvers(p_company uuid,p_users uuid[],p_revision integer) returns jsonb
language plpgsql security definer set search_path='' as $$
declare setting private.expense_approval_settings%rowtype;
begin
 perform 1 from public.companies where id=p_company for update;
 if not coalesce((private.expense_review_access(p_company)->>'can_configure')::boolean,false) then raise exception 'expense settings require administrator' using errcode='42501'; end if;
 if cardinality(p_users) is null or cardinality(p_users) not between 1 and 3 or
  (select count(distinct x) from unnest(p_users) x)<>cardinality(p_users) or
  exists(select 1 from unnest(p_users) x where not exists(select 1 from public.company_members where company_id=p_company and user_id=x and role::text in ('owner','admin','manager','viewer')))  then raise exception 'select one to three company approvers' using errcode='22023'; end if;
 select * into setting from private.expense_approval_settings where company_id=p_company for update;
 if coalesce(setting.revision,0) is distinct from p_revision then raise exception 'expense settings changed; reload' using errcode='40001'; end if;
 insert into private.expense_approval_settings(company_id,approver_ids,revision) values(p_company,p_users,1)
 on conflict(company_id) do update set approver_ids=excluded.approver_ids,revision=expense_approval_settings.revision+1;
 return private.expense_review_workspace(p_company,current_date);
end $$;
create function private.expense_review_command(p_command_id uuid,p_claim uuid,p_revision integer,p_action text,p_allocation text default null,p_counterparty uuid default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare claim private.expense_claims%rowtype; setting private.expense_approval_settings%rowtype; old private.expense_claim_events%rowtype;
 command jsonb:=jsonb_build_object('claim',p_claim,'revision',p_revision,'action',p_action,'allocation',p_allocation,'counterparty',p_counterparty);
 result jsonb; partner_name text;
begin
 select * into claim from private.expense_claims where id=p_claim;
 if not found then raise exception 'expense unavailable' using errcode='42501'; end if;
 perform 1 from public.companies where id=claim.company_id for key share;
 select * into setting from private.expense_approval_settings where company_id=claim.company_id for share;
 if not coalesce((private.expense_review_access(claim.company_id)->>'can_review')::boolean,false) then raise exception 'selected expense approver required' using errcode='42501'; end if;
 if p_command_id is null or p_action is null or p_action not in ('approve','reject','allocate') then raise exception 'invalid expense command' using errcode='22023'; end if;
 select * into claim from private.expense_claims where id=p_claim for update;
 select * into old from private.expense_claim_events where command_id=p_command_id;
 if found then
  if old.actor_id is distinct from auth.uid() or old.command is distinct from command then raise exception 'fixed expense command differs' using errcode='23505'; end if;
  return old.result;
 end if;
 if claim.revision is distinct from p_revision then raise exception 'expense changed; reload' using errcode='40001'; end if;
 -- Match the existing assignee workflow: self review is allowed only when
 -- the company has one selected approver. Allocation is a separate operation.
 if p_action in ('approve','reject') and claim.created_by=auth.uid() and cardinality(setting.approver_ids)>1 then raise exception 'another selected approver must review own claim' using errcode='42501'; end if;
 if p_action in ('approve','reject') and (p_allocation is not null or p_counterparty is not null) then raise exception 'decision cannot allocate simultaneously'; end if;
 if p_action='approve' and claim.approval<>'approved' then
  update private.expense_claims set approval='approved',allocation='ownCompany',counterparty_id=null,counterparty_name=null,revision=revision+1 where id=p_claim;
 elsif p_action='reject' and claim.approval<>'rejected' then
  update private.expense_claims set approval='rejected',revision=revision+1 where id=p_claim;
 elsif p_action='allocate' then
  if claim.approval<>'approved' then raise exception 'approve before allocation'; end if;
  if p_allocation='ownCompany' and p_counterparty is null then partner_name:=null;
  elsif p_allocation='customer' then
   select name into partner_name from public.customers where id=p_counterparty and company_id=claim.company_id for key share;
   if not found then raise exception 'company customer required' using errcode='42501'; end if;
  elsif p_allocation='subcontractor' then
   select name into partner_name from public.partner_companies where id=p_counterparty and company_id=claim.company_id for key share;
   if not found then raise exception 'company subcontractor required' using errcode='42501'; end if;
  else raise exception 'invalid expense allocation'; end if;
  update private.expense_claims set allocation=p_allocation,counterparty_id=p_counterparty,counterparty_name=partner_name,revision=revision+1 where id=p_claim;
 end if;
 select to_jsonb(e) into result from private.expense_claims e where id=p_claim;
 insert into private.expense_claim_events(command_id,company_id,claim_id,actor_id,command,result) values(p_command_id,claim.company_id,p_claim,auth.uid(),command,result);
 return result;
end $$;
create function public.expense_management_companies() returns jsonb language sql security invoker set search_path='' as $$select private.expense_management_companies()$$;
create function public.expense_review_workspace(p_company uuid,p_month date) returns jsonb language sql security invoker set search_path='' as $$select private.expense_review_workspace(p_company,p_month)$$;
create function public.set_expense_approvers(p_company uuid,p_users uuid[],p_revision integer) returns jsonb language sql security invoker set search_path='' as $$select private.set_expense_approvers(p_company,p_users,p_revision)$$;
create function public.expense_review_command(p_command_id uuid,p_claim uuid,p_revision integer,p_action text,p_allocation text default null,p_counterparty uuid default null) returns jsonb language sql security invoker set search_path='' as $$select private.expense_review_command(p_command_id,p_claim,p_revision,p_action,p_allocation,p_counterparty)$$;
revoke all on function private.expense_review_access(uuid) from public,anon,authenticated;
revoke all on function private.expense_management_companies(),public.expense_management_companies(),private.expense_review_workspace(uuid,date),public.expense_review_workspace(uuid,date),private.set_expense_approvers(uuid,uuid[],integer),public.set_expense_approvers(uuid,uuid[],integer),private.expense_review_command(uuid,uuid,integer,text,text,uuid),public.expense_review_command(uuid,uuid,integer,text,text,uuid) from public,anon;
grant execute on function private.expense_management_companies(),public.expense_management_companies(),private.expense_review_workspace(uuid,date),public.expense_review_workspace(uuid,date),private.set_expense_approvers(uuid,uuid[],integer),public.set_expense_approvers(uuid,uuid[],integer),private.expense_review_command(uuid,uuid,integer,text,text,uuid),public.expense_review_command(uuid,uuid,integer,text,text,uuid) to authenticated;
