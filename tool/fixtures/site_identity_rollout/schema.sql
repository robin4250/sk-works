-- Disposable localhost PostgreSQL fixture derived from #1099 0d70b877.
-- Never apply to Supabase or an existing database.
create role anon;create role authenticated;grant usage on schema public to authenticated;create schema auth;create schema private;
 create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('test.uid',true),'')::uuid$$;
 create table public.company_members(company_id uuid,user_id uuid,role text);
 create table public.sites(id uuid primary key,company_id uuid,name text,formal_name text);
 create table private.document_deliveries(id uuid primary key,sender_company_id uuid,recipient_company_id uuid);
 create table private.company_data_delivery_items(id uuid primary key,delivery_id uuid,payload_kind text,payload jsonb);
 create table private.site_share_inbox(data_item_id uuid primary key,recipient_company_id uuid,status text);
 create table public.attendance_entries(id uuid primary key,site_id uuid references public.sites(id),amount integer);
 grant insert on public.attendance_entries to authenticated;
 