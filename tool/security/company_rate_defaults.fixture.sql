-- Synthetic contract fixture only: authorization is a narrow fixture stub.
create role anon;
create role authenticated;
create role service_role;
create schema auth;
create schema private;
create function private.account_access_allowed() returns boolean language sql stable as $$
  select coalesce(current_setting('fixture.account_blocked',true),'')<>'true'
$$;
create function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('fixture.actor',true),'')::uuid
$$;
create table public.companies(id uuid primary key,tax_rate numeric(5,2),default_welfare_rate numeric(6,3),updated_at timestamptz);
create table public.company_members(company_id uuid,user_id uuid,role text);
create table public.company_rate_settings(company_id uuid primary key,overtime_hour_rate_yen int,
  early_hour_rate_yen int,night_hour_rate_yen int,holiday_day_rate_yen int,
  allowance_1_name text,allowance_1_amount_yen int,allowance_1_unit text,
  allowance_2_name text,allowance_2_amount_yen int,allowance_2_unit text,
  allowance_3_name text,allowance_3_amount_yen int,allowance_3_unit text,
  updated_by uuid,updated_at timestamptz);
create schema company_common_allowance_private;
grant usage on schema company_common_allowance_private to authenticated;
create function company_common_allowance_private.authorize(cid uuid,editing boolean)
returns void language plpgsql security definer set search_path='' as $$begin
  if auth.uid() is null or not exists(select 1 from public.company_members
    where company_id=cid and user_id=auth.uid() and role in ('owner','admin')) then
    raise exception 'forbidden' using errcode='42501';
  end if;
end $$;

insert into public.companies values
 ('10000000-0000-0000-0000-000000000001',10,15,now()),
 ('10000000-0000-0000-0000-000000000002',8,12,now());
insert into public.company_members values
 ('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','owner'),
 ('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000002','employee');
insert into public.company_rate_settings values
 ('10000000-0000-0000-0000-000000000001',1000,1100,1200,1300,
 'fixture old one',3000,'件','fixture old two',2000,'時間','fixture old three',1000,'回',null,now());
