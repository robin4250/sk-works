export const ids=Array.from({length:10},(_,i)=>`00000000-0000-4000-8000-${String(i+1).padStart(12,'0')}`);
export const [A,B,U,V,R,S1,S2,ST1,ST2,C]=ids;
// Minimal schema mirrors the named repository columns/constraints; feature/auth
// gates below are deterministic fixtures, not production authorization proofs.
export const schema=`
create role anon;create role authenticated;create schema private;create schema auth;
create function auth.uid() returns uuid language sql as $$select nullif(current_setting('test.actor',true),'')::uuid$$;
create function private.account_access_allowed() returns boolean language sql as $$select auth.uid() is not null and coalesce(current_setting('test.allowed',true),'yes')<>'no'$$;
create table company_members(company_id uuid,user_id uuid,role text);
create function private.can_manage_vehicle_routes(uuid,text) returns boolean language sql security definer set search_path='' as $$select exists(select 1 from public.company_members where company_id=$1 and user_id=auth.uid() and role in('owner','admin','manager'))$$;
create function private.require_master_optional_feature(text) returns void language plpgsql as $$begin if current_setting('test.feature',true)='off' then raise exception 'feature off' using errcode='55000';end if;end$$;
create table companies(id uuid primary key);

create table sites(id uuid primary key,company_id uuid);
create table customers(id uuid primary key,company_id uuid);
create table partner_companies(id uuid primary key,company_id uuid);
create table vehicles(id uuid primary key,company_id uuid);
create table route_assignments(id uuid primary key default gen_random_uuid(),company_id uuid not null references companies(id),
 service_date date,route_name text not null check(length(btrim(route_name)) between 1 and 120),notes text check(notes is null or length(notes)<=2000),
 vehicle_id uuid,site_id uuid,driver_user_id uuid,is_active boolean not null default true,
 responsible_name text check(responsible_name is null or length(responsible_name)<=120),responsible_phone text check(responsible_phone is null or length(responsible_phone)<=40),
 created_by uuid,updated_by uuid,created_at timestamptz default now(),updated_at timestamptz default now());
create table route_stops(id uuid primary key default gen_random_uuid(),company_id uuid not null references companies(id),
 route_assignment_id uuid not null references route_assignments(id),stop_order integer not null check(stop_order>=0),
 site_id uuid references sites(id),address text,source_kind text check(source_kind is null or source_kind in('site','customer','partner','parking','address')),
 source_id uuid,source_label text,latitude double precision,longitude double precision,created_by uuid,updated_by uuid,
 created_at timestamptz default now(),updated_at timestamptz default now(),unique(route_assignment_id,stop_order),
 check(site_id is not null or nullif(trim(address),'') is not null));
create table attendance_verifications(id uuid primary key default gen_random_uuid(),company_id uuid,route_assignment_id uuid references route_assignments(id));
create table daily_reports(id uuid primary key default gen_random_uuid(),company_id uuid,route_assignment_id uuid references route_assignments(id));
create table private.route_journey_captures(id uuid primary key default gen_random_uuid(),company_id uuid,route_assignment_id uuid,route_stop_id uuid,payload jsonb);
create table private.route_visit_reports(id uuid primary key default gen_random_uuid(),company_id uuid,route_assignment_id uuid,route_stop_id uuid,status text);
insert into companies values('${A}'),('${B}');
insert into company_members values('${A}','${U}','admin'),('${B}','${V}','admin');
insert into sites values('${S1}','${A}'),('${S2}','${B}');
insert into customers values('${C}','${A}');
insert into vehicles values('${C}','${A}');
insert into partner_companies values('${C}','${A}');
insert into route_assignments(id,company_id,route_name,notes,created_by) values('${R}','${A}','old route','old notes','${U}');
insert into route_stops(id,company_id,route_assignment_id,stop_order,site_id,address,source_kind,source_id,created_by)
values('${ST1}','${A}','${R}',0,'${S1}','old A','site','${S1}','${U}'),
('${ST2}','${A}','${R}',1,null,'old B','address',null,'${U}');
select set_config('test.actor','${U}',false);
create function private.fail_late_stop() returns trigger language plpgsql as $$begin
 if current_setting('test.fail_stop',true)='yes' then raise exception 'fixture late stop failure' using errcode='P0001';end if;return NEW;end$$;
create trigger zz_fixture_late_failure before insert or update on route_stops for each row execute function private.fail_late_stop();
`;

