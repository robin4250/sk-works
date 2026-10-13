-- Local isolated SQL harness: prerequisite fixtures emulate the existing schema.
-- Run only against a fresh disposable PostgreSQL/PGlite instance; never production.
create role anon; create role authenticated;
create schema auth; create schema private;
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
create table auth.users(id uuid primary key);
create table public.companies(id uuid primary key);
create table public.company_members(company_id uuid,user_id uuid,role text);
create table public.user_profiles(user_id uuid,display_name text);
create function private.has_company_feature(cid uuid,feature text) returns boolean language sql stable as $$
select exists(select 1 from public.company_members where company_id=cid and user_id=auth.uid() and role in ('owner','admin','manager'))$$;
create table public.invoices(id uuid primary key,company_id uuid references public.companies,customer_id uuid,
 billing_period_start date,billing_period_end date,status text,subtotal int,tax int,welfare_amount int,
 adjustments int,grand_total int,detail_mode text,snapshot jsonb,updated_at timestamptz,finalized_at timestamptz);
create table public.invoice_site_calculations(id uuid primary key,invoice_id uuid references public.invoices on delete cascade,subtotal int);
create table public.invoice_detail_lines(id uuid primary key,invoice_site_calculation_id uuid references public.invoice_site_calculations on delete cascade,amount int);
create table public.app_notifications(recipient_user_id uuid,action_key text,action_id uuid);
create function private.enqueue_notification(uuid,uuid,text,text,text,text,uuid) returns void language sql as $$select$$;
insert into auth.users values('00000000-0000-0000-0000-000000000001'),('00000000-0000-0000-0000-000000000002'),('00000000-0000-0000-0000-000000000003'),('00000000-0000-0000-0000-000000000004');
insert into public.companies values('10000000-0000-0000-0000-000000000001'),('10000000-0000-0000-0000-000000000002');
insert into public.company_members values
('10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000001','owner'),
('10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002','member'),
('10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000003','member'),
('10000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000004','owner');
