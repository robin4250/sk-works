-- Disposable fixture reconstructed from read-only catalog shapes, no live rows.
create role authenticated;
create schema auth;
create schema private;
create function auth.uid() returns uuid language sql stable as $$select (nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'sub')::uuid$$;
create table public.companies(id uuid primary key);
create table public.workers(id uuid primary key,company_id uuid not null references public.companies(id),user_id uuid not null);
create table public.document_requirements(id uuid primary key,company_id uuid not null,name text not null,is_active boolean not null);
create table public.worker_document_statuses(company_id uuid,worker_id uuid,requirement_id uuid,status text,original_verified boolean,updated_by uuid,updated_at timestamptz,attachment_path text,notes text,unique(worker_id,requirement_id));
create table private.account_deletion_access_restrictions(user_id uuid primary key);
create function private.account_access_allowed() returns boolean language sql stable security definer set search_path='' as $$select auth.uid() is not null and not exists(select 1 from private.account_deletion_access_restrictions where user_id=auth.uid())$$;
create function private.has_company_feature(uuid,text) returns boolean language sql stable as $$select false$$;
create table public.worker_private_bank_accounts(
 worker_id uuid primary key references public.workers(id),company_id uuid not null references public.companies(id),
 bank_name text not null check(length(trim(bank_name)) between 1 and 100),
 branch_name text not null check(length(trim(branch_name)) between 1 and 100),
 account_type text not null check(account_type in ('普通','当座','貯蓄')),
 account_number text not null check(account_number ~ '^[0-9]{7}$'),
 account_holder text not null check(length(trim(account_holder)) between 1 and 100),updated_at timestamptz not null default now());
alter table public.worker_private_bank_accounts enable row level security;
create policy account_deletion_access_guard on public.worker_private_bank_accounts as restrictive for all to authenticated
 using((select private.account_access_allowed())) with check((select private.account_access_allowed()));
create policy bank_read on public.worker_private_bank_accounts for select to authenticated using(
 exists(select 1 from public.workers w where w.id=worker_id and w.company_id=worker_private_bank_accounts.company_id and w.user_id=(select auth.uid()))
 or private.has_company_feature(company_id,'can_manage_payroll'));
create policy bank_self_insert on public.worker_private_bank_accounts for insert to authenticated with check(
 exists(select 1 from public.workers w where w.id=worker_id and w.company_id=worker_private_bank_accounts.company_id and w.user_id=(select auth.uid())));
create policy bank_self_update on public.worker_private_bank_accounts for update to authenticated using(
 exists(select 1 from public.workers w where w.id=worker_id and w.company_id=worker_private_bank_accounts.company_id and w.user_id=(select auth.uid())))
 with check(exists(select 1 from public.workers w where w.id=worker_id and w.company_id=worker_private_bank_accounts.company_id and w.user_id=(select auth.uid())));
create function private.sync_bank_document_status() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or not exists(select 1 from public.workers w where w.id=new.worker_id and w.company_id=new.company_id and w.user_id=auth.uid()) then raise exception 'own bank account required';end if;
 new.updated_at:=now();
 insert into public.worker_document_statuses(company_id,worker_id,requirement_id,status,original_verified,updated_by,updated_at)
 select new.company_id,new.worker_id,dr.id,'submitted',false,auth.uid(),now() from public.document_requirements dr
 where dr.company_id=new.company_id and dr.name='銀行口座情報' and dr.is_active
 on conflict(worker_id,requirement_id) do update set status='submitted',original_verified=false,updated_by=auth.uid(),updated_at=now();
 return new;
end $$;
create trigger sync_bank_document_status before insert or update on public.worker_private_bank_accounts for each row execute function private.sync_bank_document_status();
grant usage on schema public,auth,private to authenticated;
grant execute on function auth.uid(),private.account_access_allowed(),private.has_company_feature(uuid,text) to authenticated;
grant select on public.workers to authenticated;
grant insert,select,update on public.worker_private_bank_accounts to authenticated;
revoke all on public.worker_document_statuses,private.account_deletion_access_restrictions from authenticated;
