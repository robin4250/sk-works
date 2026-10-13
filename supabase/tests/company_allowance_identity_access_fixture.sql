-- Disposable PG17/PGlite only. Existing auth/guard source is not modified.
create role anon;create role authenticated;
create schema auth;create schema private;
create function auth.uid() returns uuid language sql as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
create function private.account_access_allowed() returns boolean language sql as $$select coalesce(current_setting('fixture.account_blocked',true),'')<>'true'$$;
create table public.companies(id uuid primary key,name text,tax_rate numeric default 10,default_welfare_rate numeric default 0,updated_at timestamptz);
create table public.company_members(company_id uuid,user_id uuid,role text);
create table public.company_rate_settings(
 company_id uuid primary key references companies(id) on delete cascade,
 overtime_hour_rate_yen integer default 0,early_hour_rate_yen integer default 0,
 night_hour_rate_yen integer default 0,holiday_day_rate_yen integer default 0,
 allowance_1_name text,allowance_1_amount_yen integer default 0,
 allowance_2_name text,allowance_2_amount_yen integer default 0,
 allowance_3_name text,allowance_3_amount_yen integer default 0,
 updated_by uuid,updated_at timestamptz);
alter table public.company_rate_settings enable row level security;
revoke all on public.company_rate_settings from public,anon,authenticated;
create table public.payroll_statements(id uuid primary key,detail jsonb,gross_pay integer);
insert into companies(id,name) values('10000000-0000-0000-0000-000000000001','Company A'),('10000000-0000-0000-0000-000000000002','Company B');
insert into company_rate_settings(company_id,allowance_1_name,allowance_1_amount_yen,allowance_2_name,allowance_2_amount_yen)
values('10000000-0000-0000-0000-000000000001','既存手当',700,'既存手当',800),('10000000-0000-0000-0000-000000000002','他社',900,null,0);
insert into company_members values
('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','admin'),
('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000002','member'),
('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000003','viewer'),
('10000000-0000-0000-0000-000000000002','20000000-0000-0000-0000-000000000004','owner');
insert into payroll_statements values('30000000-0000-0000-0000-000000000001','{"label":"過去手当","amount":1234}',1234);
