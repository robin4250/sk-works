-- Disposable PostgreSQL/PGlite fixture only; never run this setup on production.
create role anon; create role authenticated;
create schema auth; create schema private;
create function auth.uid() returns uuid language sql stable as $$
select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
create table public.company_members(company_id uuid,user_id uuid,role text);
create table public.workers(id uuid primary key,company_id uuid not null,
 name text,affiliation text default 'employee',role text,phone text,
 status text default 'active',created_at timestamptz default now(),updated_at timestamptz default now());
alter table public.workers enable row level security;
create policy worker_read on public.workers for select to authenticated using(
 exists(select 1 from public.company_members c where c.company_id=workers.company_id and c.user_id=auth.uid()));
grant usage on schema auth,private to authenticated;
grant select on public.company_members to authenticated;
grant select(id,company_id,name,role,status) on public.workers to authenticated;
create table public.worker_personnel_profiles(worker_id uuid primary key,company_id uuid,
 blood_type text,address text,emergency_name text,emergency_relation text,emergency_phone text,
 emergency_address text,family_composition text,created_by uuid,updated_by uuid,updated_at timestamptz);
create table public.worker_family_members(id uuid default gen_random_uuid(),company_id uuid,worker_id uuid,
 name text,relation text,birth_date date,is_dependent boolean,created_by uuid,updated_by uuid);
create table public.worker_personnel_approvers(company_id uuid,user_id uuid);
create table public.worker_personnel_change_requests(id uuid default gen_random_uuid(),company_id uuid,
 worker_id uuid,requested_by uuid,proposed jsonb,required_approvals int,status text default 'pending',resolved_at timestamptz);
create table public.app_notifications(company_id uuid,recipient_user_id uuid,kind text,title text,
 body text,action_key text,action_id uuid);
create function private.can_edit_worker_personnel(wid uuid) returns boolean language sql stable as $$
select exists(select 1 from public.workers w join public.company_members c on c.company_id=w.company_id
 where w.id=wid and c.user_id=auth.uid() and c.role in ('owner','admin','manager')) $$;
insert into public.company_members values
 ('10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000001','owner'),
 ('10000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000002','owner');
-- Pre-migration existing workers must receive stable numbers without replacing unrelated fields.
insert into public.workers(id,company_id,name,role) values
 ('40000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','先行社員','大工'),
 ('40000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001','後続社員','鳶');
-- ASSERTIONS

do $$begin
 if (select employee_number from public.workers where id='40000000-0000-0000-0000-000000000001')<>'S0001' then raise exception 'backfill first'; end if;
 if (select employee_number from public.workers where id='40000000-0000-0000-0000-000000000002')<>'S0002' then raise exception 'backfill second'; end if;
 if (select role from public.workers where id='40000000-0000-0000-0000-000000000001')<>'大工' then raise exception 'existing job overwritten'; end if;
end $$;
insert into public.workers(id,company_id,name,employee_number) values
 ('40000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000001','予約番号',' s0003 '),
 ('40000000-0000-0000-0000-000000000004','10000000-0000-0000-0000-000000000001','自動番号','  '),
 ('40000000-0000-0000-0000-000000000005','10000000-0000-0000-0000-000000000002','別会社','s0001');
do $$begin
 if (select employee_number from public.workers where id='40000000-0000-0000-0000-000000000004')<>'S0004' then raise exception 'manual number not skipped'; end if;
 begin
  update public.workers set employee_number=' s0001 ' where id='40000000-0000-0000-0000-000000000002';
  raise exception 'duplicate accepted';
 exception when unique_violation then
  if sqlerrm<>'employee_number_duplicate' then raise exception 'wrong duplicate message'; end if;
 end;
end $$;
-- Preserve the user's manual casing while rejecting case-insensitive duplicates.
update public.workers set employee_number=' ab-12 ' where id='40000000-0000-0000-0000-000000000003';
do $$begin
 if (select employee_number from public.workers where id='40000000-0000-0000-0000-000000000003')<>'ab-12' then raise exception 'manual case changed'; end if;
 begin
  update public.workers set employee_number='AB-12' where id='40000000-0000-0000-0000-000000000002';
  raise exception 'case-insensitive duplicate accepted';
 exception when unique_violation then
  if sqlerrm<>'employee_number_duplicate' then raise exception 'wrong case duplicate message'; end if;
 end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',false);
select public.save_worker_personnel_profile('40000000-0000-0000-0000-000000000001',
 '{"employee_number":" staff-9 ","department":"工事部","hire_date":"2026-04-01","role":"現場監督","name":"先行社員"}');
do $$declare p jsonb; begin
 p:=private.worker_personnel_payload('40000000-0000-0000-0000-000000000001');
 if p->>'employee_number'<>'staff-9' or p->>'department'<>'工事部' or p->>'hire_date'<>'2026-04-01' or p->>'role'<>'現場監督' then raise exception 'personnel payload mismatch'; end if;
 if not exists(select 1 from jsonb_array_elements(private.employee_personnel_rows()) v where v->>'employee_number'='staff-9' and v->>'hire_date'='2026-04-01') then raise exception 'personnel projection missing'; end if;
 begin
  perform public.save_worker_personnel_profile('40000000-0000-0000-0000-000000000002','{"employee_number":"staff-9"}');
  raise exception 'RPC duplicate accepted';
 exception when unique_violation then null;
 end;
 begin
  perform public.save_worker_personnel_profile('40000000-0000-0000-0000-000000000005','{"employee_number":"stolen"}');
  raise exception 'other company modified';
 exception when others then
  if sqlerrm='other company modified' then raise; end if;
 end;
end $$;
-- Omitted keys preserve metadata; explicit blank clears department/date and auto-numbers ID.
select public.save_worker_personnel_profile('40000000-0000-0000-0000-000000000001','{"name":"改名","role":"現場監督"}');
do $$begin
 if (select hire_date from public.workers where id='40000000-0000-0000-0000-000000000001')<>'2026-04-01'::date then raise exception 'omitted date erased'; end if;
end $$;
select public.save_worker_personnel_profile('40000000-0000-0000-0000-000000000001','{"name":"改名","employee_number":"","department":"","hire_date":""}');
do $$begin
 if not exists(select 1 from public.workers where id='40000000-0000-0000-0000-000000000001' and employee_number='S0005' and department is null and hire_date is null) then raise exception 'clear/auto behavior'; end if;
 if has_table_privilege('authenticated','private.worker_employee_number_counters','select') then raise exception 'counter leakage'; end if;
 if has_function_privilege('anon','private.assign_worker_employee_number()','execute') then raise exception 'trigger callable by anon'; end if;
end $$;

-- Managers still propose edits; new employment fields do not bypass approvals.
update public.company_members set role='manager'
where user_id='00000000-0000-0000-0000-000000000001';
insert into public.worker_personnel_approvers values
 ('10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000003');
do $$declare r jsonb; begin
 r:=public.save_worker_personnel_profile('40000000-0000-0000-0000-000000000001',
 '{"name":"改名","employee_number":"PROPOSED-1","department":"管理部","hire_date":"2026-05-01"}');
 if r->>'status'<>'pending' then raise exception 'manager bypassed approval'; end if;
 if (select employee_number from public.workers where id='40000000-0000-0000-0000-000000000001')<>'S0005' then raise exception 'pending proposal applied early'; end if;
 if not exists(select 1 from public.worker_personnel_change_requests where proposed->>'employee_number'='PROPOSED-1' and proposed->>'hire_date'='2026-05-01') then raise exception 'new fields absent from proposal'; end if;
 if has_function_privilege('anon','public.save_worker_personnel_profile(uuid,jsonb)','execute') then raise exception 'anon save grant'; end if;
end $$;

set role authenticated;
do $$begin
 if (select count(*) from public.workers)<>4 then raise exception 'workers RLS changed'; end if;
 if not exists(select 1 from public.workers where employee_number='S0005') then raise exception 'new columns not granted'; end if;
end $$;
reset role;
