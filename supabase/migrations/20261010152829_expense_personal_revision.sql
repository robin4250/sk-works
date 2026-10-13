-- Retain original submissions, change receipts and finalized document snapshots.
alter table private.expense_claims add column withdrawn boolean not null default false;
alter table private.expense_claims add constraint expense_withdrawn_state
 check(not withdrawn or (approval='rejected' and allocation='unallocated' and counterparty_id is null));
create table private.expense_personal_changes (
 command_id uuid primary key, company_id uuid not null, claim_id uuid not null,
 actor_id uuid not null, command jsonb not null, before_row jsonb not null,
 result jsonb not null, created_at timestamptz not null default clock_timestamp()
);
alter table private.expense_personal_changes enable row level security;
revoke all on private.expense_personal_changes from public,anon,authenticated;
create index expense_personal_changes_claim on private.expense_personal_changes(company_id,claim_id,created_at);
create function private.guard_withdrawn_expense() returns trigger
language plpgsql set search_path='' as $$
begin
 if old.withdrawn then raise exception 'withdrawn expense cannot change' using errcode='22023'; end if;
 return new;
end $$;
create trigger guard_withdrawn_expense before update on private.expense_claims
 for each row execute function private.guard_withdrawn_expense();
revoke all on function private.guard_withdrawn_expense() from public,anon,authenticated;

create function private.expense_personal_change(p_command_id uuid,p_claim uuid,p_revision integer,p_action text,
 p_date date default null,p_description text default null,p_amount integer default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare claim private.expense_claims%rowtype; old private.expense_personal_changes%rowtype; result jsonb;
 command jsonb:=jsonb_build_object('claim',p_claim,'revision',p_revision,'action',p_action,'date',p_date,'description',p_description,'amount',p_amount);
begin
 if auth.uid() is null or not private.account_access_allowed() then raise exception 'account unavailable' using errcode='42501'; end if;
 select * into claim from private.expense_claims where id=p_claim and created_by=auth.uid();
 if not found or not exists(select 1 from public.company_members where company_id=claim.company_id and user_id=auth.uid()) then
  raise exception 'own expense required' using errcode='42501';
 end if;
 perform 1 from public.companies where id=claim.company_id for key share;
 if not found then raise exception 'company unavailable' using errcode='42501'; end if;
 perform 1 from public.workers where id=claim.applicant_id and company_id=claim.company_id and user_id=auth.uid() for key share;
 if not found then raise exception 'own worker required' using errcode='42501'; end if;
 select * into claim from private.expense_claims where id=p_claim for update;
 select * into old from private.expense_personal_changes where command_id=p_command_id;
 if found then
  if old.actor_id is distinct from auth.uid() or old.command is distinct from command then
   raise exception 'fixed personal command differs' using errcode='23505';
  end if;
  return old.result;
 end if;
 if not exists(select 1 from public.workers where id=claim.applicant_id and status='active') then
  raise exception 'active worker required' using errcode='42501';
 end if;
 if p_command_id is null or p_revision is null or p_action is null or p_action not in ('edit','withdraw') then
  raise exception 'invalid personal command' using errcode='22023';
 end if;
 if claim.revision<>p_revision then raise exception 'expense changed; reload' using errcode='40001'; end if;
 if claim.withdrawn then raise exception 'withdrawn expense cannot change' using errcode='22023'; end if;
 if p_action='edit' then
  if p_date is null or p_date < date '1900-01-01' or p_date > (clock_timestamp() at time zone 'Asia/Tokyo')::date or
   p_description is null or length(btrim(p_description)) not between 1 and 1000 or p_amount is null or p_amount not between 1 and 999999999 then
   raise exception 'invalid expense edit' using errcode='22023';
  end if;
  update private.expense_claims set incurred_on=p_date,description=btrim(p_description),amount_yen=p_amount,
   approval='pending',allocation='unallocated',counterparty_id=null,counterparty_name=null,revision=revision+1 where id=p_claim;
 else
  if p_date is not null or p_description is not null or p_amount is not null then raise exception 'withdraw has no new content' using errcode='22023'; end if;
  update private.expense_claims set withdrawn=true,approval='rejected',allocation='unallocated',
   counterparty_id=null,counterparty_name=null,revision=revision+1 where id=p_claim;
 end if;
 select to_jsonb(e) into result from private.expense_claims e where id=p_claim;
 insert into private.expense_personal_changes(command_id,company_id,claim_id,actor_id,command,before_row,result)
 values(p_command_id,claim.company_id,p_claim,auth.uid(),command,to_jsonb(claim),result);
 return result;
end $$;
create function public.expense_personal_change(p_command_id uuid,p_claim uuid,p_revision integer,p_action text,
 p_date date default null,p_description text default null,p_amount integer default null) returns jsonb
language sql security invoker set search_path='' as $$
 select private.expense_personal_change(p_command_id,p_claim,p_revision,p_action,p_date,p_description,p_amount);
$$;
revoke all on function private.expense_personal_change(uuid,uuid,integer,text,date,text,integer),public.expense_personal_change(uuid,uuid,integer,text,date,text,integer) from public,anon;
grant execute on function private.expense_personal_change(uuid,uuid,integer,text,date,text,integer),public.expense_personal_change(uuid,uuid,integer,text,date,text,integer) to authenticated;

-- An original submission response lost before an edit remains recoverable.
-- History/workspace readers continue to return the current revision.
create or replace function private.expense_personal_exact(p_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or not private.account_access_allowed() then raise exception 'account unavailable' using errcode='42501'; end if;
 return (select coalesce((select x.before_row from private.expense_personal_changes x
   where x.company_id=e.company_id and x.claim_id=e.id order by (x.before_row->>'revision')::integer limit 1),to_jsonb(e))
  from private.expense_claims e where e.id=p_id and e.created_by=auth.uid()
  and exists(select 1 from public.company_members cm join public.companies c on c.id=cm.company_id where cm.company_id=e.company_id and cm.user_id=auth.uid()));
end $$;

create or replace function private.expense_personal_submit(p_id uuid,p_company uuid,p_worker uuid,p_date date,p_description text,p_amount integer) returns jsonb
language plpgsql security definer set search_path='' as $$
declare existing private.expense_claims%rowtype; worker_name text;
begin
 if auth.uid() is null or not private.account_access_allowed() or p_id is null or
  not exists(select 1 from public.company_members where company_id=p_company and user_id=auth.uid()) then
  raise exception 'personal submission unavailable' using errcode='42501';
 end if;
 perform 1 from public.companies where id=p_company for key share;
 if not found then raise exception 'company unavailable' using errcode='42501'; end if;
 select name into worker_name from public.workers where id=p_worker and company_id=p_company and user_id=auth.uid() for key share;
 if not found then raise exception 'own worker required' using errcode='42501'; end if;
 -- Same UUID retries remain recoverable after an approval or worker retirement.
 select * into existing from jsonb_populate_record(null::private.expense_claims,private.expense_personal_exact(p_id));
 if existing.id is not null then
  if existing.created_by is distinct from auth.uid() or existing.company_id is distinct from p_company or
   existing.applicant_id is distinct from p_worker or existing.incurred_on is distinct from p_date or
   existing.description is distinct from btrim(p_description) or existing.amount_yen is distinct from p_amount then
   raise exception 'fixed expense differs' using errcode='23505';
  end if;
  return to_jsonb(existing);
 end if;
 if not exists(select 1 from public.workers where id=p_worker and status='active') then raise exception 'active worker required' using errcode='42501'; end if;
 if p_date is null or p_date < date '1900-01-01' or p_date > (clock_timestamp() at time zone 'Asia/Tokyo')::date or
  p_description is null or length(btrim(p_description)) not between 1 and 1000 or p_amount is null or p_amount not between 1 and 999999999 then
  raise exception 'invalid expense submission' using errcode='22023';
 end if;
 insert into private.expense_claims(id,company_id,applicant_id,applicant_name,created_by,incurred_on,description,amount_yen)
 values(p_id,p_company,p_worker,worker_name,auth.uid(),p_date,btrim(p_description),p_amount)
 on conflict(id) do nothing;
 select * into existing from jsonb_populate_record(null::private.expense_claims,private.expense_personal_exact(p_id));
 if existing.created_by is distinct from auth.uid() or existing.company_id is distinct from p_company or
  existing.applicant_id is distinct from p_worker or existing.incurred_on is distinct from p_date or
  existing.description is distinct from btrim(p_description) or existing.amount_yen is distinct from p_amount then
  raise exception 'fixed expense differs' using errcode='23505';
 end if;
 return to_jsonb(existing);
end $$;
