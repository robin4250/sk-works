-- Personal expense submission. No payroll totals or existing documents change.
create table private.expense_claims (
 id uuid primary key,
 company_id uuid not null,
 applicant_id uuid not null,
 applicant_name text not null,
 created_by uuid not null,
 incurred_on date not null,
 description text not null check(length(btrim(description)) between 1 and 1000),
 amount_yen integer not null check(amount_yen between 1 and 999999999),
 submitted_at timestamptz not null default clock_timestamp(),
 approval text not null default 'pending' check(approval in ('pending','approved','rejected')),
 allocation text not null default 'unallocated' check(allocation in ('unallocated','ownCompany','subcontractor','customer')),
 counterparty_id uuid,
 counterparty_name text,
 revision integer not null default 1,
 check((allocation in ('subcontractor','customer') and counterparty_id is not null) or
       (allocation in ('unallocated','ownCompany') and counterparty_id is null))
);
alter table private.expense_claims enable row level security;
revoke all on private.expense_claims from public,anon,authenticated;
create index expense_claims_personal_month on private.expense_claims(company_id,created_by,applicant_id,incurred_on,id);

create function private.expense_personal_scopes() returns jsonb
language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or not private.account_access_allowed() then raise exception 'account unavailable' using errcode='42501'; end if;
 return (select coalesce(jsonb_agg(jsonb_build_object('company_id',c.id,'company_name',c.name,'worker_id',w.id,'worker_name',w.name) order by c.id,w.id),'[]'::jsonb)
  from public.workers w join public.companies c on c.id=w.company_id
  where w.user_id=auth.uid() and w.status='active'
  and exists(select 1 from public.company_members cm where cm.company_id=c.id and cm.user_id=auth.uid()));
end $$;
create function private.expense_personal_exact(p_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or not private.account_access_allowed() then raise exception 'account unavailable' using errcode='42501'; end if;
 return (select to_jsonb(e) from private.expense_claims e where e.id=p_id and e.created_by=auth.uid()
  and exists(select 1 from public.company_members cm join public.companies c on c.id=cm.company_id where cm.company_id=e.company_id and cm.user_id=auth.uid()));
end $$;
create function private.expense_personal_history(p_company uuid,p_worker uuid,p_month date) returns jsonb
language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or not private.account_access_allowed() or p_month is null or
  not exists(select 1 from public.company_members cm join public.companies c on c.id=cm.company_id where c.id=p_company and cm.user_id=auth.uid()) or
  not exists(select 1 from public.workers w where w.id=p_worker and w.company_id=p_company and w.user_id=auth.uid()) then
  raise exception 'personal expenses unavailable' using errcode='42501';
 end if;
 return (select coalesce(jsonb_agg(to_jsonb(e) order by e.incurred_on,e.submitted_at,e.id),'[]'::jsonb)
  from private.expense_claims e where e.company_id=p_company and e.applicant_id=p_worker and e.created_by=auth.uid()
  and e.incurred_on >= date_trunc('month',p_month)::date
  and e.incurred_on < (date_trunc('month',p_month)+interval '1 month')::date);
end $$;
create function private.expense_personal_submit(p_id uuid,p_company uuid,p_worker uuid,p_date date,p_description text,p_amount integer) returns jsonb
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
 select * into existing from private.expense_claims where id=p_id;
 if found then
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
 select * into existing from private.expense_claims where id=p_id;
 if existing.created_by is distinct from auth.uid() or existing.company_id is distinct from p_company or
  existing.applicant_id is distinct from p_worker or existing.incurred_on is distinct from p_date or
  existing.description is distinct from btrim(p_description) or existing.amount_yen is distinct from p_amount then
  raise exception 'fixed expense differs' using errcode='23505';
 end if;
 return to_jsonb(existing);
end $$;
create function public.expense_personal_scopes() returns jsonb language sql security invoker set search_path='' as $$select private.expense_personal_scopes()$$;
create function public.expense_personal_exact(p_id uuid) returns jsonb language sql security invoker set search_path='' as $$select private.expense_personal_exact(p_id)$$;
create function public.expense_personal_history(p_company uuid,p_worker uuid,p_month date) returns jsonb language sql security invoker set search_path='' as $$select private.expense_personal_history(p_company,p_worker,p_month)$$;
create function public.expense_personal_submit(p_id uuid,p_company uuid,p_worker uuid,p_date date,p_description text,p_amount integer) returns jsonb language sql security invoker set search_path='' as $$select private.expense_personal_submit(p_id,p_company,p_worker,p_date,p_description,p_amount)$$;
revoke all on function private.expense_personal_scopes(),public.expense_personal_scopes(),private.expense_personal_exact(uuid),public.expense_personal_exact(uuid),private.expense_personal_history(uuid,uuid,date),public.expense_personal_history(uuid,uuid,date),private.expense_personal_submit(uuid,uuid,uuid,date,text,integer),public.expense_personal_submit(uuid,uuid,uuid,date,text,integer) from public,anon;
grant execute on function private.expense_personal_scopes(),public.expense_personal_scopes(),private.expense_personal_exact(uuid),public.expense_personal_exact(uuid),private.expense_personal_history(uuid,uuid,date),public.expense_personal_history(uuid,uuid,date),private.expense_personal_submit(uuid,uuid,uuid,date,text,integer),public.expense_personal_submit(uuid,uuid,uuid,date,text,integer) to authenticated;
