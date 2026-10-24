-- Synthetic runtime fixture. Production data and real Auth are not used.
-- The actual legacy identity migration is loaded by the workflow before this.
alter table public.companies enable row level security;
alter table public.company_rate_settings enable row level security;
create table company_common_allowance_private.unit_aliases (
 company_id uuid primary key,units jsonb not null check(jsonb_typeof(units)='object'),
 observations jsonb not null default '{}'::jsonb check(jsonb_typeof(observations)='object'),
 adopted_by uuid not null,adopted_at timestamptz not null default clock_timestamp()
);
alter table company_common_allowance_private.unit_aliases enable row level security;
create function company_common_allowance_private.current_units(cid uuid) returns jsonb
language sql stable set search_path='' as $$
 select jsonb_strip_nulls(jsonb_build_object(
 coalesce(nullif(trim(r.allowance_1_name),''),'__none1'),coalesce(nullif(trim(r.allowance_1_unit),''),'回'),
 coalesce(nullif(trim(r.allowance_2_name),''),'__none2'),coalesce(nullif(trim(r.allowance_2_unit),''),'回'),
 coalesce(nullif(trim(r.allowance_3_name),''),'__none3'),coalesce(nullif(trim(r.allowance_3_unit),''),'回')))-'__none1'-'__none2'-'__none3'
 from public.company_rate_settings r where r.company_id=cid
$$;
create function company_common_allowance_private.protect_unit_aliases() returns trigger
language plpgsql volatile security definer set search_path='' as $$
declare baseline jsonb;current_map jsonb;observed jsonb;xid text:=pg_postmaster_start_time()::text||':'||pg_current_xact_id()::text;
begin
 select units,observations into baseline,observed from company_common_allowance_private.unit_aliases where company_id=new.company_id for update;
 if not found then return new;end if;
 current_map:=company_common_allowance_private.current_units(new.company_id);
 if exists(select 1 from jsonb_each(current_map) x where baseline ? x.key and baseline->x.key is distinct from x.value and observed->>x.key is distinct from xid) then
  raise exception 'past allowance display unit requires dated compatibility' using errcode='22023';end if;
 select observed||coalesce(jsonb_object_agg(x.key,to_jsonb(xid)) filter(where not(baseline ? x.key)),'{}'::jsonb) into observed from jsonb_each(current_map) x;
 update company_common_allowance_private.unit_aliases set units=baseline||current_map,observations=observed where company_id=new.company_id;
 return new;
end $$;
create trigger company_common_allowance_unit_compat after update on public.company_rate_settings
for each row execute function company_common_allowance_private.protect_unit_aliases();

create table private.fixture_invoice_refresh_calls(company_id uuid,customer_id uuid,month date);
create table public.sites(id uuid primary key,company_id uuid,customer_id uuid);
create table public.attendance_entries(company_id uuid,site_id uuid,work_date date);
create table public.invoices(id uuid primary key,company_id uuid,total_yen integer,finalized boolean);
create function private.refresh_automatic_invoice(cid uuid,customer uuid,p_month date)
returns void language sql security definer set search_path='' as $$
  insert into private.fixture_invoice_refresh_calls values(cid,customer,p_month)
$$;
CREATE OR REPLACE FUNCTION private.company_tax_refresh_invoice()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r record; begin
 for r in select distinct s.customer_id,date_trunc('month',e.work_date)::date as month from public.attendance_entries e
 join public.sites s on s.id=e.site_id and s.company_id=e.company_id where e.company_id=new.id and s.customer_id is not null order by 1,2 loop
 perform private.refresh_automatic_invoice(new.id,r.customer_id,r.month);
 end loop;
 return null;
end;
$function$
;
create trigger company_tax_refresh_invoice after update of tax_rate on public.companies
for each row execute function private.company_tax_refresh_invoice();
insert into public.sites values
 ('30000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000001'),
 ('30000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000002','40000000-0000-0000-0000-000000000002');
insert into public.attendance_entries values
 ('10000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','2026-10-01'),
 ('10000000-0000-0000-0000-000000000002','30000000-0000-0000-0000-000000000002','2026-10-01');
insert into public.invoices values
 ('50000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001',12000,true),
 ('50000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000002',13000,false);
select set_config('fixture.actor','20000000-0000-0000-0000-000000000001',false);
select public.adopt_company_allowance_identity(
 '10000000-0000-0000-0000-000000000001',
 (select company_allowance_identity_private.slots(r) from public.company_rate_settings r
  where company_id='10000000-0000-0000-0000-000000000001'),true);
insert into company_common_allowance_private.unit_aliases(company_id,units,adopted_by)
values('10000000-0000-0000-0000-000000000001',
 company_common_allowance_private.current_units('10000000-0000-0000-0000-000000000001'),
 '20000000-0000-0000-0000-000000000001');
create function private.fixture_rate_originals() returns jsonb language sql stable as $$
 select jsonb_build_object(
 'companies',(select jsonb_agg(to_jsonb(t) order by id) from public.companies t),
 'rates',(select jsonb_agg(to_jsonb(t) order by company_id) from public.company_rate_settings t),
 'identities',(select jsonb_agg(to_jsonb(t) order by id) from company_allowance_identity_private.identities t),
 'state',(select jsonb_agg(to_jsonb(t) order by company_id) from company_allowance_identity_private.state t),
 'history',(select jsonb_agg(to_jsonb(t) order by company_id,version) from company_allowance_identity_private.history t),
 'aliases',(select jsonb_agg(to_jsonb(t) order by company_id) from company_common_allowance_private.unit_aliases t),
 'invoice_refresh',(select coalesce(jsonb_agg(to_jsonb(t)),'[]') from private.fixture_invoice_refresh_calls t),
 'invoices',(select jsonb_agg(to_jsonb(t) order by id) from public.invoices t))
$$;
create table private.fixture_rate_install_before as select private.fixture_rate_originals() value;
do $$begin
 assert (select md5(prosrc)='a518232a914a4b498a3a7a04a6e92bbd' from pg_proc where oid='company_allowance_identity_private.track_settings()'::regprocedure);
 assert (select md5(prosrc)='e3c8da66a355ffb1f80cc8b04f186c47' from pg_proc where oid='company_common_allowance_private.protect_unit_aliases()'::regprocedure);
 assert (select md5(prosrc)='2e15dd3f5e40ae7efeb9ff6a810fb04c' from pg_proc where oid='private.company_tax_refresh_invoice()'::regprocedure);
end $$;
